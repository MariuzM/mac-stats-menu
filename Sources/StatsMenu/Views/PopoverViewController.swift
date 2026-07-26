import AppKit

private enum MetricKind: Hashable {
    case cpu, memory, gpu, disk, network
}

final class PopoverViewController: NSViewController {
    private let engine: StatsEngine
    private let rowCount = 5
    private let networkProcesses = NetworkProcessMonitor()
    private let gpuProcesses = GPUProcessMonitor()
    private let diskProcesses = DiskProcessMonitor()

    private let cpuRow = MetricRow(title: "CPU", color: .systemBlue)
    private let memRow = MetricRow(title: "Memory", color: .systemGreen)
    private let gpuRow = MetricRow(title: "GPU", color: .systemPurple)
    private let diskRow = DualRateRow(
        title: "Disk", leftPrefix: "R ", rightPrefix: "W ",
        leftColor: .systemIndigo, rightColor: .systemPink)
    private let networkRow = DualRateRow(
        title: "Network", leftPrefix: "↓ ", rightPrefix: "↑ ",
        leftColor: .systemTeal, rightColor: .systemOrange)
    private let claudeRow = UsageRow(title: "Claude Code", color: Theme.claude, lineCount: 3)
    private let codexRow = UsageRow(title: "Codex", color: Theme.codex, lineCount: 2)

    private var latestProcesses: [ProcessSample] = []
    private var latestNet: [NetworkProcessSample] = []
    private var latestGPU: [GPUProcessSample] = []
    private var latestDisk: [DiskProcessSample] = []
    private var latestClaude: ClaudeLiveLimits?
    private var claudeFetchStarted = false
    private var claudeFetchDone = false
    private var latestCodex: CodexLiveLimits?
    private var codexFetchStarted = false
    private var codexFetchDone = false

    private var activeKind: MetricKind?
    private weak var anchorView: NSView?
    private var closeWorkItem: DispatchWorkItem?
    private let sampleQueue = DispatchQueue(label: "StatsMenu.flyout-sampling", qos: .userInitiated)
    private var sampleInFlight = false
    private var lastSampleTime: [MetricKind: TimeInterval] = [:]

    init(engine: StatsEngine) {
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        FlyoutController.shared.hide()
    }

    override func loadView() {
        let title = NSTextField(labelWithString: "Stats")
        title.font = .boldSystemFont(ofSize: 13)

        let settings = NSButton(
            image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")!,
            target: self, action: #selector(openSettings))
        settings.isBordered = false
        settings.bezelStyle = .regularSquare

        let quit = NSButton(
            image: NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")!,
            target: self, action: #selector(quit))
        quit.isBordered = false
        quit.bezelStyle = .regularSquare

        let header = NSStackView(views: [title, NSView(), settings, quit])
        header.orientation = .horizontal
        header.spacing = 8

        cpuRow.onHover = { [weak self] entered in self?.handleHover(.cpu, anchor: self?.cpuRow, entered: entered) }
        memRow.onHover = { [weak self] entered in self?.handleHover(.memory, anchor: self?.memRow, entered: entered) }
        gpuRow.onHover = { [weak self] entered in self?.handleHover(.gpu, anchor: self?.gpuRow, entered: entered) }
        diskRow.onHover = { [weak self] entered in self?.handleHover(.disk, anchor: self?.diskRow, entered: entered) }
        networkRow.onHover = { [weak self] entered in
            self?.handleHover(.network, anchor: self?.networkRow, entered: entered)
        }

        let stack = NSStackView(views: [
            header, cpuRow, memRow, gpuRow, diskRow, networkRow,
            claudeRow, codexRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.panelBackground.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.widthAnchor.constraint(equalToConstant: 260),
        ])
        view = container
    }

    func ownsWindow(_ window: NSWindow?) -> Bool {
        window != nil && window === FlyoutController.shared.window
    }

    func refresh() {
        cpuRow.update(value: "\(Int(engine.cpu.rounded()))%", subtitle: nil, history: engine.cpuHistory)
        memRow.update(
            value: "\(Int(engine.memory.percent.rounded()))%",
            subtitle:
                "\(ByteFormat.gigabytes(engine.memory.usedBytes)) of \(ByteFormat.gigabytes(engine.memory.totalBytes))",
            history: engine.memHistory)
        gpuRow.update(value: "\(Int(engine.gpu.rounded()))%", subtitle: nil, history: engine.gpuHistory)
        diskRow.update(
            left: ByteFormat.rate(engine.disk.readBytesPerSec),
            right: ByteFormat.rate(engine.disk.writeBytesPerSec),
            subtitle:
                "\(ByteFormat.gigabytes(engine.disk.usedBytes)) of \(ByteFormat.gigabytes(engine.disk.totalBytes)) used",
            leftHistory: engine.diskReadHistory, rightHistory: engine.diskWriteHistory)
        networkRow.update(
            left: ByteFormat.rate(engine.network.downBytesPerSec),
            right: ByteFormat.rate(engine.network.upBytesPerSec),
            subtitle: nil,
            leftHistory: engine.downHistory, rightHistory: engine.upHistory)
        let showClaude = UsageSettings.showClaude
        claudeRow.isHidden = !showClaude
        if showClaude {
            updateClaudeRow()
            refreshClaudeUsage()
        }
        let showCodex = UsageSettings.showCodex
        codexRow.isHidden = !showCodex
        if showCodex {
            updateCodexRow()
            refreshCodexUsage()
        }

        if let kind = activeKind {
            sampleAsync(kind)
        }
    }

    private func updateClaudeRow() {
        guard let limits = latestClaude else {
            let placeholder = claudeFetchDone ? "—" : "…"
            claudeRow.update(lines: [("Session", 0, placeholder), ("Week", 0, placeholder), nil])
            return
        }
        let session = limitLine(limits.sessionPercent, limits.sessionResetsAt)
        let week = limitLine(limits.weekPercent, limits.weekResetsAt)
        let model = limits.modelName.map { name -> (title: String, fraction: Double, text: String) in
            let line = limitLine(limits.modelWeekPercent, limits.modelWeekResetsAt)
            return (name, line.0, line.1)
        }
        claudeRow.update(lines: [("Session", session.0, session.1), ("Week", week.0, week.1), model])
    }

    private func limitLine(_ percent: Double?, _ resetsAt: Date?) -> (Double, String) {
        guard let percent else { return (0, "—") }
        var text = "\(Int(percent.rounded()))%"
        if let resetsAt, resetsAt > Date() {
            text += " · \(remainingText(until: resetsAt))"
        }
        return (min(1, percent / 100), text)
    }

    private func remainingText(until date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        if minutes >= 2880 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    private func refreshClaudeUsage() {
        guard !claudeFetchStarted else { return }
        claudeFetchStarted = true
        latestClaude = ClaudeUsageMonitor.shared.cached
        updateClaudeRow()
        claudeRow.setLoading(true)
        ClaudeUsageMonitor.shared.fetch { [weak self] limits in
            DispatchQueue.main.async {
                guard let self else { return }
                self.claudeRow.setLoading(false)
                self.claudeFetchDone = true
                self.latestClaude = limits
                self.updateClaudeRow()
            }
        }
    }

    private func updateCodexRow() {
        guard let limits = latestCodex else {
            let placeholder = codexFetchDone ? "—" : "…"
            codexRow.update(lines: [("Usage", 0, placeholder), nil])
            return
        }
        let plan = limits.plan.flatMap { p -> String? in
            p == "unknown" ? nil : p.replacingOccurrences(of: "_", with: " ").capitalized
        }
        codexRow.update(
            subtitle: plan,
            lines: [limits.primary.map(codexLine), limits.secondary.map(codexLine)])
    }

    private func codexLine(_ window: CodexLimitWindow) -> (title: String, fraction: Double, text: String) {
        let line = limitLine(window.usedPercent, window.resetsAt)
        return (limitWindowTitle(window.durationMinutes), line.0, line.1)
    }

    private func limitWindowTitle(_ minutes: Int?) -> String {
        guard let minutes else { return "Usage" }
        switch minutes {
        case 300: return "5h"
        case 1_440: return "Day"
        case 10_080: return "Week"
        default:
            if minutes.isMultiple(of: 1_440) { return "\(minutes / 1_440)d" }
            if minutes.isMultiple(of: 60) { return "\(minutes / 60)h" }
            return "\(minutes)m"
        }
    }

    private func refreshCodexUsage() {
        guard !codexFetchStarted else { return }
        codexFetchStarted = true
        latestCodex = CodexUsageMonitor.shared.cached
        updateCodexRow()
        codexRow.setLoading(true)
        CodexUsageMonitor.shared.fetch { [weak self] limits in
            DispatchQueue.main.async {
                guard let self else { return }
                self.codexRow.setLoading(false)
                self.codexFetchDone = true
                self.latestCodex = limits
                self.updateCodexRow()
            }
        }
    }

    private func handleHover(_ kind: MetricKind, anchor: NSView?, entered: Bool) {
        guard let anchor else { return }
        if entered {
            closeWorkItem?.cancel()
            activeKind = kind
            anchorView = anchor
            presentDetail()
            sampleAsync(kind)
        } else {
            scheduleClose()
        }
    }

    private func scheduleClose() {
        closeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.activeKind = nil
            FlyoutController.shared.hide()
        }
        closeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func presentDetail() {
        guard let kind = activeKind, let anchor = anchorView else { return }
        FlyoutController.shared.show(sections: detailSections(for: kind), relativeTo: anchor)
    }

    private func sampleAsync(_ kind: MetricKind) {
        guard !sampleInFlight else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let sampleKind: MetricKind = kind == .memory ? .cpu : kind
        guard now - (lastSampleTime[sampleKind] ?? -.infinity) >= SamplingSettings.panelInterval else { return }
        lastSampleTime[sampleKind] = now
        sampleInFlight = true
        sampleQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                var processes: [ProcessSample]?
                var gpu: [GPUProcessSample]?
                var disk: [DiskProcessSample]?
                var net: [NetworkProcessSample]?
                switch kind {
                case .cpu, .memory: processes = ProcessMonitor.sample()
                case .gpu: gpu = self.gpuProcesses.sample()
                case .disk: disk = self.diskProcesses.sample()
                case .network: net = self.networkProcesses.sample()
                }
                DispatchQueue.main.async {
                    self.sampleInFlight = false
                    if let processes { self.latestProcesses = processes }
                    if let gpu { self.latestGPU = gpu }
                    if let disk { self.latestDisk = disk }
                    if let net { self.latestNet = net }
                    guard let active = self.activeKind else { return }
                    let sharesProcessSample =
                        (kind == .cpu || kind == .memory)
                        && (active == .cpu || active == .memory)
                    guard active == kind || sharesProcessSample else { return }
                    FlyoutController.shared.updateContent(sections: self.detailSections(for: active))
                }
            }
        }
    }

    private func detailSections(for kind: MetricKind) -> [(String, [DetailItem])] {
        switch kind {
        case .cpu:
            let items = top(latestProcesses) { $0.cpu }
                .map { item(pid: $0.pid, name: $0.name, value: String(format: "%.1f%%", $0.cpu)) }
            return [("Top CPU", items)]
        case .memory:
            let items = top(latestProcesses) { Double($0.memBytes) }
                .map { item(pid: $0.pid, name: $0.name, value: ByteFormat.megabytes($0.memBytes)) }
            return [("Top Memory", items)]
        case .gpu:
            let items = top(latestGPU) { $0.percent }
                .map { item(pid: $0.pid, name: $0.name, value: String(format: "%.1f%%", $0.percent)) }
            return [("Top GPU", items)]
        case .disk:
            let read = top(latestDisk) { $0.readBytesPerSec }
                .map { item(pid: $0.pid, name: $0.name, value: ByteFormat.rate($0.readBytesPerSec)) }
            let write = top(latestDisk) { $0.writeBytesPerSec }
                .map { item(pid: $0.pid, name: $0.name, value: ByteFormat.rate($0.writeBytesPerSec)) }
            return [("Top Read", read), ("Top Write", write)]
        case .network:
            let down = top(latestNet) { $0.downBytesPerSec }
                .map { item(pid: $0.pid, name: $0.name, value: ByteFormat.rate($0.downBytesPerSec)) }
            let up = top(latestNet) { $0.upBytesPerSec }
                .map { item(pid: $0.pid, name: $0.name, value: ByteFormat.rate($0.upBytesPerSec)) }
            return [("Top Download", down), ("Top Upload", up)]
        }
    }

    // The flyout only displays five rows. Maintaining those five while walking
    // the samples avoids sorting (and copying) the full system process list.
    private func top<Element>(_ values: [Element], score: (Element) -> Double) -> [Element] {
        var ranked: [(score: Double, value: Element)] = []
        ranked.reserveCapacity(rowCount)

        for value in values {
            let valueScore = score(value)
            guard valueScore > 0 else { continue }
            let insertion = ranked.firstIndex { valueScore > $0.score } ?? ranked.endIndex
            guard insertion < rowCount else { continue }
            ranked.insert((valueScore, value), at: insertion)
            if ranked.count > rowCount {
                ranked.removeLast()
            }
        }
        return ranked.map(\.value)
    }

    private func item(pid: Int, name: String, value: String) -> DetailItem {
        let info = AppInfo.lookup(pid: pid)
        return DetailItem(icon: info.icon, name: info.name ?? name, value: value)
    }

    @objc private func openSettings() {
        FlyoutController.shared.hide()
        activeKind = nil
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

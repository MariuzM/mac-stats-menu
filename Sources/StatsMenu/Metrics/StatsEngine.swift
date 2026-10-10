import Foundation

final class StatsEngine {
    static let historyLength = 60

    private(set) var cpu: Double = 0
    private(set) var memory: MemorySample = .zero
    private(set) var gpu: Double = 0
    private(set) var network: NetworkSample = .zero
    private(set) var disk: DiskSample = .zero

    private(set) var cpuHistory: [Double] = []
    private(set) var memHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []
    private(set) var downHistory: [Double] = []
    private(set) var upHistory: [Double] = []
    private(set) var diskReadHistory: [Double] = []
    private(set) var diskWriteHistory: [Double] = []

    var onUpdate: (() -> Void)?

    private let cpuMonitor = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()
    private let gpuMonitor = GPUMonitor()
    private let networkMonitor = NetworkMonitor()
    private let diskMonitor = DiskMonitor()

    private var interval: TimeInterval
    private var timer: Timer?
    private var isDetailed = false
    private var lastGPUSampleTime: TimeInterval = -.infinity
    private var lastDiskSampleTime: TimeInterval = -.infinity
    private var settingsObserver: NSObjectProtocol?

    // IOKit property dictionaries are considerably more expensive than the Mach
    // and interface counters. Keep them fresh while the panel is visible, but do
    // not continuously query data that cannot be seen while it is closed.
    init(interval: TimeInterval = SamplingSettings.menuBarInterval) {
        self.interval = interval
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .samplingSettingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applySamplingSettings()
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func start() {
        sampleOnce()
        scheduleTimer()
    }

    func setInterval(_ value: TimeInterval) {
        guard value != interval else { return }
        interval = value
        if timer != nil {
            scheduleTimer()
        }
    }

    func setDetailed(_ detailed: Bool) {
        guard detailed != isDetailed else { return }
        isDetailed = detailed
        setInterval(detailed ? SamplingSettings.panelInterval : SamplingSettings.menuBarInterval)

        // Refresh slow metrics on the next panel sample instead of leaving a
        // value that may be up to 30 seconds old.
        if detailed {
            lastGPUSampleTime = -.infinity
            lastDiskSampleTime = -.infinity
        }
    }

    private func applySamplingSettings() {
        setInterval(isDetailed ? SamplingSettings.panelInterval : SamplingSettings.menuBarInterval)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.sampleOnce()
        }
        timer.tolerance = interval * (isDetailed ? 0.1 : 0.4)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func sampleOnce() {
        autoreleasepool {
            let now = ProcessInfo.processInfo.systemUptime
            cpu = cpuMonitor.sample()
            memory = memoryMonitor.sample()
            network = networkMonitor.sample()

            if isDetailed || now - lastGPUSampleTime >= SamplingSettings.backgroundGPUInterval {
                gpu = gpuMonitor.sample()
                lastGPUSampleTime = now
            }
            if isDetailed || now - lastDiskSampleTime >= SamplingSettings.backgroundDiskInterval {
                disk = diskMonitor.sample()
                lastDiskSampleTime = now
            }
        }

        append(&cpuHistory, cpu)
        append(&memHistory, memory.percent)
        append(&gpuHistory, gpu)
        append(&downHistory, network.downBytesPerSec)
        append(&upHistory, network.upBytesPerSec)
        append(&diskReadHistory, disk.readBytesPerSec)
        append(&diskWriteHistory, disk.writeBytesPerSec)

        onUpdate?()
    }

    private func append(_ values: inout [Double], _ value: Double) {
        values.append(value)
        if values.count > Self.historyLength {
            values.removeFirst(values.count - Self.historyLength)
        }
    }
}

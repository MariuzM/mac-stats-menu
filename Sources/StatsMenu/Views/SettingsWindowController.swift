import AppKit
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("LaunchAtLogin toggle failed: \(error.localizedDescription)")
        }
    }
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let launchToggle = NSButton(
        checkboxWithTitle: "Launch at login",
        target: nil, action: nil)
    private let highContrastToggle = NSButton(
        checkboxWithTitle: "High-contrast menu bar colors",
        target: nil, action: nil)
    private let menuBarInterval = NSPopUpButton()
    private let panelInterval = NSPopUpButton()
    private let gpuInterval = NSPopUpButton()
    private let diskInterval = NSPopUpButton()
    private let claudeUsageToggle = NSButton(
        checkboxWithTitle: "Show Claude Code stats",
        target: nil, action: nil)
    private let codexUsageToggle = NSButton(
        checkboxWithTitle: "Show Codex stats",
        target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 570),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildContent() {
        let heading = NSTextField(labelWithString: "General")
        heading.font = .boldSystemFont(ofSize: 13)

        launchToggle.target = self
        launchToggle.action = #selector(toggleLaunch)
        highContrastToggle.target = self
        highContrastToggle.action = #selector(toggleHighContrast)
        highContrastToggle.toolTip = "Adds a dark background and stronger colors for light or translucent menu bars."

        let hint = NSTextField(labelWithString: "Start StatsMenu automatically when you log in.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let separator = NSBox()
        separator.boxType = .separator

        let samplingHeading = NSTextField(labelWithString: "Refresh timings")
        samplingHeading.font = .boldSystemFont(ofSize: 13)

        let samplingHint = NSTextField(labelWithString: "Longer intervals use less CPU. Changes apply immediately.")
        samplingHint.font = .systemFont(ofSize: 11)
        samplingHint.textColor = .secondaryLabelColor

        configure(menuBarInterval, values: [2, 5, 10, 15, 30])
        configure(panelInterval, values: [1, 2, 3, 5, 10])
        configure(gpuInterval, values: [5, 10, 15, 30, 60])
        configure(diskInterval, values: [10, 30, 60, 120])

        let grid = NSGridView(views: [
            [label("Menu bar"), menuBarInterval],
            [label("Open panel"), panelInterval],
            [label("Background GPU"), gpuInterval],
            [label("Background disk"), diskInterval],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowSpacing = 7
        grid.columnSpacing = 12

        let restore = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        restore.bezelStyle = .rounded

        let claudeSeparator = NSBox()
        claudeSeparator.boxType = .separator

        let claudeHeading = NSTextField(labelWithString: "Claude Code")
        claudeHeading.font = .boldSystemFont(ofSize: 13)

        claudeUsageToggle.target = self
        claudeUsageToggle.action = #selector(toggleClaudeUsage)

        let codexSeparator = NSBox()
        codexSeparator.boxType = .separator

        let codexHeading = NSTextField(labelWithString: "Codex")
        codexHeading.font = .boldSystemFont(ofSize: 13)

        codexUsageToggle.target = self
        codexUsageToggle.action = #selector(toggleCodexUsage)

        let stack = NSStackView(views: [
            heading, launchToggle, hint, highContrastToggle, separator,
            samplingHeading, samplingHint, grid, restore,
            claudeSeparator, claudeHeading, claudeUsageToggle,
            codexSeparator, codexHeading, codexUsageToggle,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(16, after: highContrastToggle)
        stack.setCustomSpacing(14, after: separator)
        stack.setCustomSpacing(16, after: restore)
        stack.setCustomSpacing(14, after: claudeSeparator)
        stack.setCustomSpacing(16, after: claudeUsageToggle)
        stack.setCustomSpacing(14, after: codexSeparator)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            claudeSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            codexSeparator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            grid.widthAnchor.constraint(equalToConstant: 300),
        ])
        window?.contentView = container
    }

    private func label(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.alignment = .right
        return field
    }

    private func configure(_ button: NSPopUpButton, values: [TimeInterval]) {
        button.removeAllItems()
        button.target = self
        button.action = #selector(samplingChanged)
        for value in values {
            let title = value == 1 ? "1 second" : "\(Int(value)) seconds"
            button.addItem(withTitle: title)
            button.lastItem?.representedObject = NSNumber(value: value)
        }
    }

    private func select(_ value: TimeInterval, in button: NSPopUpButton) {
        let items = button.itemArray
        guard
            let closest = items.min(by: {
                abs((($0.representedObject as? NSNumber)?.doubleValue ?? 0) - value)
                    < abs((($1.representedObject as? NSNumber)?.doubleValue ?? 0) - value)
            })
        else { return }
        button.select(closest)
    }

    private func selectedValue(_ button: NSPopUpButton) -> TimeInterval {
        (button.selectedItem?.representedObject as? NSNumber)?.doubleValue ?? 1
    }

    private func refreshSamplingControls() {
        select(SamplingSettings.menuBarInterval, in: menuBarInterval)
        select(SamplingSettings.panelInterval, in: panelInterval)
        select(SamplingSettings.backgroundGPUInterval, in: gpuInterval)
        select(SamplingSettings.backgroundDiskInterval, in: diskInterval)
    }

    private func refreshUsageControls() {
        claudeUsageToggle.state = UsageSettings.showClaude ? .on : .off
        codexUsageToggle.state = UsageSettings.showCodex ? .on : .off
    }

    func show() {
        launchToggle.state = LaunchAtLogin.isEnabled ? .on : .off
        highContrastToggle.state = AppearanceSettings.highContrastMenuBar ? .on : .off
        refreshSamplingControls()
        refreshUsageControls()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLaunch(_ sender: NSButton) {
        LaunchAtLogin.setEnabled(sender.state == .on)
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func toggleHighContrast(_ sender: NSButton) {
        AppearanceSettings.highContrastMenuBar = sender.state == .on
    }

    @objc private func samplingChanged() {
        SamplingSettings.update(
            menuBar: selectedValue(menuBarInterval),
            panel: selectedValue(panelInterval),
            gpu: selectedValue(gpuInterval),
            disk: selectedValue(diskInterval)
        )
    }

    @objc private func restoreDefaults() {
        SamplingSettings.restoreDefaults()
        refreshSamplingControls()
    }

    @objc private func toggleClaudeUsage(_ sender: NSButton) {
        UsageSettings.showClaude = sender.state == .on
    }

    @objc private func toggleCodexUsage(_ sender: NSButton) {
        UsageSettings.showCodex = sender.state == .on
    }
}

import AppKit

final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let engine: StatsEngine
    private var panel: NSPanel?
    private var panelVC: PopoverViewController?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var lastSignature: String = ""
    private var appearanceObserver: NSObjectProtocol?

    init(engine: StatsEngine) {
        self.engine = engine
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePanel)
        }

        engine.onUpdate = { [weak self] in self?.refresh() }
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .menuBarAppearanceDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    private func refresh() {
        let signature = StatusBarRenderer.signature(for: engine)
        if signature != lastSignature {
            lastSignature = signature
            statusItem.button?.image = StatusBarRenderer.image(for: engine)
        }
        if panel?.isVisible == true {
            panelVC?.refresh()
        }
    }

    @objc private func togglePanel() {
        if panel != nil {
            closePanel()
            return
        }
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        let vc = PopoverViewController(engine: engine)
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentViewController = vc
        panelVC = vc
        self.panel = panel

        engine.setDetailed(true)
        vc.refresh()

        let size = vc.view.fittingSize
        panel.setContentSize(size)

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonRect.midX - size.width / 2
        if let screen = buttonWindow.screen {
            x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: buttonRect.minY - size.height - 6))
        panel.orderFront(nil)

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            self?.closePanel()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] e in
            guard let self, let panel = self.panel else { return e }
            if e.window !== panel,
                e.window !== self.statusItem.button?.window,
                self.panelVC?.ownsWindow(e.window) != true
            {
                self.closePanel()
            }
            return e
        }
    }

    private func closePanel() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
        panelVC = nil
        engine.setDetailed(false)
        AppInfo.clearCache()
        malloc_zone_pressure_relief(nil, 0)
    }
}

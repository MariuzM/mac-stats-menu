import Foundation

extension Notification.Name {
    static let samplingSettingsDidChange = Notification.Name("StatsMenu.samplingSettingsDidChange")
}

enum SamplingSettings {
    private enum Key {
        static let menuBar = "sampling.menuBarInterval"
        static let panel = "sampling.panelInterval"
        static let gpu = "sampling.backgroundGPUInterval"
        static let disk = "sampling.backgroundDiskInterval"
    }

    static let defaults:
        (
            menuBar: TimeInterval, panel: TimeInterval,
            gpu: TimeInterval, disk: TimeInterval
        ) = (5, 2, 10, 30)

    static var menuBarInterval: TimeInterval { value(for: Key.menuBar, fallback: defaults.menuBar) }
    static var panelInterval: TimeInterval { value(for: Key.panel, fallback: defaults.panel) }
    static var backgroundGPUInterval: TimeInterval { value(for: Key.gpu, fallback: defaults.gpu) }
    static var backgroundDiskInterval: TimeInterval { value(for: Key.disk, fallback: defaults.disk) }

    static func update(
        menuBar: TimeInterval, panel: TimeInterval,
        gpu: TimeInterval, disk: TimeInterval
    ) {
        let store = UserDefaults.standard
        store.set(menuBar, forKey: Key.menuBar)
        store.set(panel, forKey: Key.panel)
        store.set(gpu, forKey: Key.gpu)
        store.set(disk, forKey: Key.disk)
        NotificationCenter.default.post(name: .samplingSettingsDidChange, object: nil)
    }

    static func restoreDefaults() {
        update(
            menuBar: defaults.menuBar, panel: defaults.panel,
            gpu: defaults.gpu, disk: defaults.disk)
    }

    private static func value(for key: String, fallback: TimeInterval) -> TimeInterval {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return max(0.5, UserDefaults.standard.double(forKey: key))
    }
}

import Foundation

enum UsageSettings {
    private static let claudeKey = "claude.showUsage"
    private static let codexKey = "codex.showUsage"

    static var showClaude: Bool {
        get { UserDefaults.standard.object(forKey: claudeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: claudeKey) }
    }

    static var showCodex: Bool {
        get { UserDefaults.standard.object(forKey: codexKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: codexKey) }
    }
}

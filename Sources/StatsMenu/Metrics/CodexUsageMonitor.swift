import Foundation

struct CodexLimitWindow {
    let usedPercent: Double
    let durationMinutes: Int?
    let resetsAt: Date?
}

struct CodexLiveLimits {
    let plan: String?
    let primary: CodexLimitWindow?
    let secondary: CodexLimitWindow?
}

final class CodexUsageMonitor {
    static let shared = CodexUsageMonitor()

    private(set) var cached: CodexLiveLimits?
    private let queue = DispatchQueue(label: "StatsMenu.codex-usage", qos: .userInitiated)

    private var codexPath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/codex",
            "\(home)/.codex/packages/standalone/current/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func fetch(completion: @escaping (CodexLiveLimits?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let limits = self.runUsageCommand()
            if let limits { self.cached = limits }
            completion(limits ?? self.cached)
        }
    }

    private func runUsageCommand() -> CodexLiveLimits? {
        guard let path = codexPath else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let responseReady = DispatchSemaphore(value: 0)
        let responseQueue = DispatchQueue(label: "StatsMenu.codex-usage.response")
        var buffer = Data()
        var response: CodexLiveLimits?
        var didSignal = false

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            responseQueue.sync {
                buffer.append(data)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    guard response == nil,
                        let parsed = Self.parseRateLimitsResponse(line)
                    else { continue }
                    response = parsed
                    if !didSignal {
                        didSignal = true
                        responseReady.signal()
                    }
                }
            }
        }

        do {
            try process.run()
            try sendRequests(to: stdin.fileHandleForWriting)
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            return nil
        }

        _ = responseReady.wait(timeout: .now() + 8)
        stdout.fileHandleForReading.readabilityHandler = nil
        try? stdin.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        return responseQueue.sync { response }
    }

    private func sendRequests(to handle: FileHandle) throws {
        let messages: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "stats-menu",
                        "title": "StatsMenu",
                        "version": "1.0",
                    ]
                ],
            ],
            ["method": "initialized", "params": [String: Any]()],
            ["method": "account/rateLimits/read", "id": 1],
        ]

        for message in messages {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try handle.write(contentsOf: data)
        }
    }

    static func parseRateLimitsResponse(_ data: Data) -> CodexLiveLimits? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (object["id"] as? NSNumber)?.intValue == 1,
            let result = object["result"] as? [String: Any]
        else { return nil }

        let snapshot: [String: Any]?
        if let rateLimits = result["rateLimits"] as? [String: Any] {
            snapshot = rateLimits
        } else if let buckets = result["rateLimitsByLimitId"] as? [String: Any] {
            snapshot = buckets["codex"] as? [String: Any] ?? buckets.values.first as? [String: Any]
        } else {
            snapshot = nil
        }

        guard let snapshot else { return nil }
        let primary = parseWindow(snapshot["primary"])
        let secondary = parseWindow(snapshot["secondary"])
        guard primary != nil || secondary != nil else { return nil }

        return CodexLiveLimits(
            plan: snapshot["planType"] as? String,
            primary: primary,
            secondary: secondary)
    }

    private static func parseWindow(_ value: Any?) -> CodexLimitWindow? {
        guard let window = value as? [String: Any],
            let usedPercent = window["usedPercent"] as? NSNumber
        else { return nil }
        let duration = (window["windowDurationMins"] as? NSNumber)?.intValue
        let resetsAt = (window["resetsAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue) }
        return CodexLimitWindow(
            usedPercent: usedPercent.doubleValue,
            durationMinutes: duration,
            resetsAt: resetsAt)
    }
}

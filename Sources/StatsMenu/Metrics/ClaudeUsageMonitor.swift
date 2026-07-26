import Foundation

struct ClaudeLiveLimits {
    let sessionPercent: Double?
    let sessionResetsAt: Date?
    let weekPercent: Double?
    let weekResetsAt: Date?
    let modelName: String?
    let modelWeekPercent: Double?
    let modelWeekResetsAt: Date?
}

final class ClaudeUsageMonitor {
    static let shared = ClaudeUsageMonitor()

    private(set) var cached: ClaudeLiveLimits?
    private let queue = DispatchQueue(label: "StatsMenu.claude-usage", qos: .userInitiated)

    private var claudePath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func fetch(completion: @escaping (ClaudeLiveLimits?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let limits = self.runUsageCommand()
            if let limits { self.cached = limits }
            completion(limits ?? self.cached)
        }
    }

    private func runUsageCommand() -> ClaudeLiveLimits? {
        guard let path = claudePath else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-p", "/usage"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let kill = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: kill)
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        kill.cancel()

        guard process.terminationStatus == 0,
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        return parse(text)
    }

    private func parse(_ text: String) -> ClaudeLiveLimits? {
        let session = limitLine(#"Current session:\s*([\d.]+)% used(?:[^\n]*?resets ([^\n]+))?"#, in: text)
        let week = limitLine(
            #"Current week(?: \(all models\))?:\s*([\d.]+)% used(?:[^\n]*?resets ([^\n]+))?"#, in: text)
        let model = modelLine(in: text)
        guard session != nil || week != nil || model != nil else { return nil }
        return ClaudeLiveLimits(
            sessionPercent: session?.percent,
            sessionResetsAt: session?.resetsAt,
            weekPercent: week?.percent,
            weekResetsAt: week?.resetsAt,
            modelName: model?.name,
            modelWeekPercent: model?.percent,
            modelWeekResetsAt: model?.resetsAt)
    }

    private func limitLine(_ pattern: String, in text: String) -> (percent: Double, resetsAt: Date?)? {
        guard let groups = firstMatch(pattern, in: text),
            let percent = groups.first.flatMap({ $0 }).flatMap(Double.init)
        else { return nil }
        let resetsAt = groups.count > 1 ? groups[1].flatMap(resetDate) : nil
        return (percent, resetsAt)
    }

    private func modelLine(in text: String) -> (name: String, percent: Double, resetsAt: Date?)? {
        guard
            let groups = firstMatch(
                #"Current week \(((?!all models)[^)]+)\):\s*([\d.]+)% used(?:[^\n]*?resets ([^\n]+))?"#, in: text),
            groups.count >= 2,
            let name = groups[0],
            let percent = groups[1].flatMap(Double.init)
        else { return nil }
        let resetsAt = groups.count > 2 ? groups[2].flatMap(resetDate) : nil
        return (name, percent, resetsAt)
    }

    private func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else {
            return nil
        }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    private func resetDate(_ string: String) -> Date? {
        var body = string.trimmingCharacters(in: .whitespaces)
        var timeZone = TimeZone.current
        if let open = body.range(of: "("), let close = body.range(of: ")", options: .backwards),
            open.upperBound < close.lowerBound
        {
            if let tz = TimeZone(identifier: String(body[open.upperBound..<close.lowerBound])) {
                timeZone = tz
            }
            body = String(body[..<open.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        let year = Calendar.current.component(.year, from: Date())
        for dateFormat in ["MMM d 'at' ha yyyy", "MMM d 'at' h:mma yyyy"] {
            formatter.dateFormat = dateFormat
            for candidate in [year, year + 1] {
                if let date = formatter.date(from: "\(body) \(candidate)"),
                    date.timeIntervalSinceNow > -86_400
                {
                    return date
                }
            }
        }

        let calendar = Calendar(identifier: .gregorian)
        for timeFormat in ["ha", "h:mma"] {
            formatter.dateFormat = timeFormat
            guard let time = formatter.date(from: body) else { continue }
            let components = calendar.dateComponents(in: timeZone, from: time)
            var localCalendar = calendar
            localCalendar.timeZone = timeZone
            let now = Date()
            guard
                var candidate = localCalendar.date(
                    bySettingHour: components.hour ?? 0,
                    minute: components.minute ?? 0,
                    second: 0,
                    of: now)
            else { continue }
            if candidate <= now {
                candidate = localCalendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
        }
        return nil
    }
}

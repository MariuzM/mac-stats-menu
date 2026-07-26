import Foundation

struct ProcessSample {
    let pid: Int
    let name: String
    let cpu: Double
    let memBytes: UInt64
}

enum ProcessMonitor {
    static func sample() -> [ProcessSample] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aco", "pid=,pcpu=,rss=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var result: [ProcessSample] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                let pid = Int(parts[0]),
                let cpu = Double(parts[1]),
                let rssKB = UInt64(parts[2])
            else { continue }
            result.append(
                ProcessSample(
                    pid: pid,
                    name: String(parts[3]),
                    cpu: cpu,
                    memBytes: rssKB * 1024
                ))
        }
        return result
    }
}

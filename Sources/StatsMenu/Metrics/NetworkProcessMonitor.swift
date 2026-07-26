import Foundation

struct NetworkProcessSample {
    let name: String
    let pid: Int
    let downBytesPerSec: Double
    let upBytesPerSec: Double
}

final class NetworkProcessMonitor {
    private struct Counters {
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    private var previous: [String: Counters] = [:]
    private var prevTime: TimeInterval = 0

    func sample() -> [NetworkProcessSample] {
        let current = readCounters()
        let now = ProcessInfo.processInfo.systemUptime
        defer {
            previous = current
            prevTime = now
        }

        guard prevTime > 0 else { return [] }
        let dt = now - prevTime
        guard dt > 0 else { return [] }

        var result: [NetworkProcessSample] = []
        for (key, counters) in current {
            guard let prev = previous[key] else { continue }
            let down = counters.bytesIn >= prev.bytesIn ? Double(counters.bytesIn - prev.bytesIn) / dt : 0
            let up = counters.bytesOut >= prev.bytesOut ? Double(counters.bytesOut - prev.bytesOut) / dt : 0
            guard down > 0 || up > 0 else { continue }

            guard let dot = key.lastIndex(of: "."),
                let pid = Int(key[key.index(after: dot)...])
            else { continue }
            let name = String(key[..<dot])
            result.append(
                NetworkProcessSample(
                    name: name, pid: pid,
                    downBytesPerSec: down,
                    upBytesPerSec: up
                ))
        }
        return result
    }

    private func readCounters() -> [String: Counters] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-P", "-x", "-L", "1", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var result: [String: Counters] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3,
                !fields[0].isEmpty,
                fields[0].contains("."),
                let bytesIn = UInt64(fields[1]),
                let bytesOut = UInt64(fields[2])
            else { continue }
            result[String(fields[0])] = Counters(bytesIn: bytesIn, bytesOut: bytesOut)
        }
        return result
    }
}

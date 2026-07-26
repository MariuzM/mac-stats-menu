import Foundation
import IOKit

struct GPUProcessSample {
    let pid: Int
    let name: String
    let percent: Double
}

final class GPUProcessMonitor {
    private var previous: [Int: UInt64] = [:]
    private var prevTime: TimeInterval = 0

    func sample() -> [GPUProcessSample] {
        let current = readAccumulatedTimes()
        let now = ProcessInfo.processInfo.systemUptime
        defer {
            previous = current.times
            prevTime = now
        }

        guard prevTime > 0 else { return [] }
        let dt = now - prevTime
        guard dt > 0 else { return [] }

        var result: [GPUProcessSample] = []
        for (pid, accumulated) in current.times {
            guard let prev = previous[pid], accumulated >= prev else { continue }
            let deltaNanos = accumulated - prev
            let percent = Double(deltaNanos) / (dt * 1_000_000_000) * 100
            guard percent > 0 else { continue }
            result.append(
                GPUProcessSample(
                    pid: pid,
                    name: current.names[pid] ?? "pid \(pid)",
                    percent: min(100, percent)
                ))
        }
        return result
    }

    private func readAccumulatedTimes() -> (times: [Int: UInt64], names: [Int: String]) {
        var times: [Int: UInt64] = [:]
        var names: [Int: String] = [:]

        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator
            ) == KERN_SUCCESS
        else {
            return (times, names)
        }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            walk(entry, times: &times, names: &names)
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return (times, names)
    }

    private func walk(_ entry: io_registry_entry_t, times: inout [Int: UInt64], names: inout [Int: String]) {
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &children) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(children) }

        var child = IOIteratorNext(children)
        while child != 0 {
            accumulate(child, times: &times, names: &names)
            walk(child, times: &times, names: &names)
            IOObjectRelease(child)
            child = IOIteratorNext(children)
        }
    }

    private func accumulate(_ entry: io_registry_entry_t, times: inout [Int: UInt64], names: inout [Int: String]) {
        guard let creator = string(entry, "IOUserClientCreator"),
            let (pid, name) = parseCreator(creator)
        else { return }

        names[pid] = name

        guard
            let raw = IORegistryEntryCreateCFProperty(
                entry, "AppUsage" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue(),
            let usages = raw as? [[String: Any]]
        else { return }

        var total: UInt64 = times[pid] ?? 0
        for usage in usages {
            if let gpuTime = usage["accumulatedGPUTime"] as? NSNumber {
                total &+= gpuTime.uint64Value
            }
        }
        times[pid] = total
    }

    private func parseCreator(_ value: String) -> (pid: Int, name: String)? {
        let parts = value.split(separator: ",", maxSplits: 1)
        guard let first = parts.first else { return nil }
        let pidTokens = first.split(separator: " ")
        guard pidTokens.count == 2, pidTokens[0] == "pid", let pid = Int(pidTokens[1]) else { return nil }
        let name = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "pid \(pid)"
        return (pid, name)
    }

    private func string(_ entry: io_registry_entry_t, _ key: String) -> String? {
        guard
            let raw = IORegistryEntryCreateCFProperty(
                entry, key as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue()
        else { return nil }
        return raw as? String
    }
}

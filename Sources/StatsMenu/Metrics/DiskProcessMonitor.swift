import Foundation

struct DiskProcessSample {
    let name: String
    let pid: Int
    let readBytesPerSec: Double
    let writeBytesPerSec: Double
}

final class DiskProcessMonitor {
    private struct Counters {
        let read: UInt64
        let write: UInt64
    }

    private var previous: [Int: Counters] = [:]
    private var prevTime: TimeInterval = 0

    func sample() -> [DiskProcessSample] {
        let current = readCounters()
        let now = ProcessInfo.processInfo.systemUptime
        defer {
            previous = current.mapValues { $0.counters }
            prevTime = now
        }

        guard prevTime > 0, now > prevTime else { return [] }
        let dt = now - prevTime

        var result: [DiskProcessSample] = []
        for (pid, entry) in current {
            guard let prev = previous[pid] else { continue }
            let read = entry.counters.read >= prev.read ? Double(entry.counters.read - prev.read) / dt : 0
            let write = entry.counters.write >= prev.write ? Double(entry.counters.write - prev.write) / dt : 0
            guard read > 0 || write > 0 else { continue }
            result.append(
                DiskProcessSample(
                    name: entry.name, pid: pid,
                    readBytesPerSec: read,
                    writeBytesPerSec: write
                ))
        }
        return result
    }

    private func readCounters() -> [Int: (name: String, counters: Counters)] {
        let capacity = Int(proc_listallpids(nil, 0)) + 32
        guard capacity > 32 else { return [:] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride))
        guard count > 0 else { return [:] }

        var result: [Int: (name: String, counters: Counters)] = [:]
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard status == 0 else { continue }

            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)
            guard !name.isEmpty else { continue }

            result[Int(pid)] = (
                name,
                Counters(
                    read: info.ri_diskio_bytesread,
                    write: info.ri_diskio_byteswritten
                )
            )
        }
        return result
    }
}

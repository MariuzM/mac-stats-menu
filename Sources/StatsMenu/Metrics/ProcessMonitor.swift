import Foundation

struct ProcessSample {
    let pid: Int
    let name: String
    let cpu: Double
    let memBytes: UInt64
    let readBytesPerSec: Double
    let writeBytesPerSec: Double
}

final class ProcessMonitor {
    private struct Counters {
        let cpuNanos: UInt64
        let read: UInt64
        let write: UInt64
    }

    private var previous: [Int: Counters] = [:]
    private var prevTime: TimeInterval = 0
    private var names: [Int: String] = [:]
    private var pidBuffer: [pid_t] = []

    func sample(maxAge: TimeInterval) -> [ProcessSample]? {
        let now = ProcessInfo.processInfo.systemUptime
        var current: [Int: Counters] = [:]
        current.reserveCapacity(previous.count > 0 ? previous.count : 512)

        let listed = listPIDs()
        guard !listed.isEmpty else { return nil }

        let dt = now - prevTime
        let hasBaseline = prevTime > 0 && dt > 0 && dt <= maxAge
        var result: [ProcessSample] = []
        if hasBaseline { result.reserveCapacity(listed.count) }

        var live = Set<Int>()
        live.reserveCapacity(listed.count)

        for pid in listed where pid > 0 {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard status == 0 else { continue }

            let key = Int(pid)
            live.insert(key)
            let counters = Counters(
                cpuNanos: info.ri_user_time &+ info.ri_system_time,
                read: info.ri_diskio_bytesread,
                write: info.ri_diskio_byteswritten)
            current[key] = counters

            guard hasBaseline, let prev = previous[key] else { continue }

            let cpuDelta = counters.cpuNanos >= prev.cpuNanos ? counters.cpuNanos - prev.cpuNanos : 0
            let cpu = Double(cpuDelta) / (dt * 1_000_000_000) * 100
            let read = counters.read >= prev.read ? Double(counters.read - prev.read) / dt : 0
            let write = counters.write >= prev.write ? Double(counters.write - prev.write) / dt : 0
            let mem = info.ri_phys_footprint

            guard cpu > 0 || mem > 0 || read > 0 || write > 0 else { continue }
            guard let name = name(for: pid) else { continue }

            result.append(
                ProcessSample(
                    pid: key,
                    name: name,
                    cpu: min(100, cpu),
                    memBytes: mem,
                    readBytesPerSec: read,
                    writeBytesPerSec: write
                ))
        }

        previous = current
        prevTime = now
        names = names.filter { live.contains($0.key) }
        return hasBaseline ? result : nil
    }

    private func listPIDs() -> ArraySlice<pid_t> {
        let needed = Int(proc_listallpids(nil, 0))
        guard needed > 0 else { return [] }
        let capacity = needed + 64
        if pidBuffer.count < capacity {
            pidBuffer = [pid_t](repeating: 0, count: capacity)
        }
        let count = pidBuffer.withUnsafeMutableBufferPointer { buffer -> Int32 in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.stride))
        }
        guard count > 0 else { return [] }
        return pidBuffer.prefix(Int(count))
    }

    private func name(for pid: pid_t) -> String? {
        let key = Int(pid)
        if let cached = names[key] { return cached }
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        let name = String(cString: buffer)
        guard !name.isEmpty else { return nil }
        names[key] = name
        return name
    }
}

import Foundation
import IOKit

struct DiskSample {
    let readBytesPerSec: Double
    let writeBytesPerSec: Double
    let usedBytes: UInt64
    let totalBytes: UInt64

    static let zero = DiskSample(readBytesPerSec: 0, writeBytesPerSec: 0, usedBytes: 0, totalBytes: 0)
}

final class DiskMonitor {
    private var services: [io_registry_entry_t] = []
    private var prevRead: UInt64 = 0
    private var prevWrite: UInt64 = 0
    private var prevTime: TimeInterval = 0
    private var cachedSpace: (used: UInt64, total: UInt64) = (0, 0)
    private var lastSpaceTime: TimeInterval = -1

    init() {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("IOBlockStorageDriver"),
                &iterator) == KERN_SUCCESS
        else { return }
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            services.append(entry)
            entry = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
    }

    deinit {
        services.forEach { IOObjectRelease($0) }
    }

    func sample() -> DiskSample {
        let (totalRead, totalWrite) = counters()
        let now = ProcessInfo.processInfo.systemUptime

        if lastSpaceTime < 0 || now - lastSpaceTime >= 30 {
            cachedSpace = space()
            lastSpaceTime = now
        }

        defer {
            prevRead = totalRead
            prevWrite = totalWrite
            prevTime = now
        }

        guard prevTime > 0, now > prevTime else {
            return DiskSample(
                readBytesPerSec: 0, writeBytesPerSec: 0,
                usedBytes: cachedSpace.used, totalBytes: cachedSpace.total)
        }
        let dt = now - prevTime
        let read = totalRead >= prevRead ? Double(totalRead - prevRead) / dt : 0
        let write = totalWrite >= prevWrite ? Double(totalWrite - prevWrite) / dt : 0
        return DiskSample(
            readBytesPerSec: read, writeBytesPerSec: write,
            usedBytes: cachedSpace.used, totalBytes: cachedSpace.total)
    }

    private func counters() -> (UInt64, UInt64) {
        var read: UInt64 = 0
        var write: UInt64 = 0
        for entry in services {
            guard
                let props = IORegistryEntryCreateCFProperty(
                    entry, "Statistics" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? [String: Any]
            else { continue }
            read &+= (props["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write &+= (props["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (read, write)
    }

    private func space() -> (used: UInt64, total: UInt64) {
        let url = URL(fileURLWithPath: "/")
        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            ]),
            let total = values.volumeTotalCapacity,
            let free = values.volumeAvailableCapacityForImportantUsage,
            total > 0
        else { return (0, 0) }
        let totalBytes = UInt64(total)
        let freeBytes = UInt64(max(0, free))
        return (totalBytes &- min(freeBytes, totalBytes), totalBytes)
    }
}

import Foundation
import IOKit

final class GPUMonitor {
    private var services: [io_registry_entry_t] = []

    init() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return
        }
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

    func sample() -> Double {
        var maxUtil = 0.0
        for entry in services {
            guard
                let raw = IORegistryEntryCreateCFProperty(
                    entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue(),
                let perf = raw as? [String: Any]
            else { continue }

            let util =
                number(perf["Device Utilization %"])
                ?? number(perf["GPU Activity(%)"])
                ?? 0
            maxUtil = max(maxUtil, util)
        }
        return min(100, maxUtil)
    }

    private func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}

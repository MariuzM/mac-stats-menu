import Foundation

enum ByteFormat {
    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    static func megabytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }

    static func rate(_ bps: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bps
        var unit = 0
        while value >= 1000 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        let number =
            (unit == 0 || value >= 100)
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(number) \(units[unit])"
    }
}

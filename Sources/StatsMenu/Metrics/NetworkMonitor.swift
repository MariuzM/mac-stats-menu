import Foundation

struct NetworkSample {
    let downBytesPerSec: Double
    let upBytesPerSec: Double

    static let zero = NetworkSample(downBytesPerSec: 0, upBytesPerSec: 0)
}

final class NetworkMonitor {
    private var prevIn: UInt64 = 0
    private var prevOut: UInt64 = 0
    private var prevTime: TimeInterval = 0

    func sample() -> NetworkSample {
        let (totalIn, totalOut) = counters()
        let now = ProcessInfo.processInfo.systemUptime
        defer {
            prevIn = totalIn
            prevOut = totalOut
            prevTime = now
        }

        guard prevTime > 0 else { return .zero }
        let dt = now - prevTime
        guard dt > 0 else { return .zero }

        let down = totalIn >= prevIn ? Double(totalIn - prevIn) / dt : 0
        let up = totalOut >= prevOut ? Double(totalOut - prevOut) / dt : 0
        return NetworkSample(downBytesPerSec: down, upBytesPerSec: up)
    }

    private func counters() -> (UInt64, UInt64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var ptr = addrs
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard let addr = cur.pointee.ifa_addr,
                addr.pointee.sa_family == UInt8(AF_LINK),
                (flags & IFF_UP) != 0,
                (flags & IFF_LOOPBACK) == 0,
                let data = cur.pointee.ifa_data
            else { continue }

            let net = data.assumingMemoryBound(to: if_data.self)
            totalIn += UInt64(net.pointee.ifi_ibytes)
            totalOut += UInt64(net.pointee.ifi_obytes)
        }
        return (totalIn, totalOut)
    }
}

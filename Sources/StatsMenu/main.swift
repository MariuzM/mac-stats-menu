import AppKit

private func blockingFetch<T>(_ fetch: (@escaping (T?) -> Void) -> Void) -> T? {
    let semaphore = DispatchSemaphore(value: 0)
    var result: T?
    fetch { value in
        result = value
        semaphore.signal()
    }
    semaphore.wait()
    return result
}

if CommandLine.arguments.contains("--claude-usage") {
    if let limits = blockingFetch(ClaudeUsageMonitor.shared.fetch) {
        print(
            "5h: \(limits.sessionPercent.map { "\($0)%" } ?? "—") resets \(limits.sessionResetsAt.map(String.init(describing:)) ?? "—")"
        )
        print(
            "7d: \(limits.weekPercent.map { "\($0)%" } ?? "—") resets \(limits.weekResetsAt.map(String.init(describing:)) ?? "—")"
        )
        if let name = limits.modelName {
            print(
                "7d \(name): \(limits.modelWeekPercent.map { "\($0)%" } ?? "—") resets \(limits.modelWeekResetsAt.map(String.init(describing:)) ?? "—")"
            )
        }
    } else {
        print("no data")
    }
    exit(0)
}

if CommandLine.arguments.contains("--codex-usage") {
    if let limits = blockingFetch(CodexUsageMonitor.shared.fetch) {
        print("plan: \(limits.plan ?? "—")")
        for window in [limits.primary, limits.secondary].compactMap({ $0 }) {
            let duration = window.durationMinutes.map { "\($0)m" } ?? "window"
            let reset = window.resetsAt.map(String.init(describing:)) ?? "—"
            print("\(duration): \(window.usedPercent)% resets \(reset)")
        }
    } else {
        print("no data")
    }
    exit(0)
}

if CommandLine.arguments.contains("--print") {
    let engine = StatsEngine()
    let netProcs = NetworkProcessMonitor()
    engine.sampleOnce()
    _ = netProcs.sample()
    Thread.sleep(forTimeInterval: 2.0)
    engine.sampleOnce()
    let procs = netProcs.sample()

    let mem = engine.memory
    let net = engine.network
    print(
        String(
            format: "CPU %.1f%%   MEM %.1f%% (%.2f / %.2f GB)   GPU %.1f%%",
            engine.cpu, mem.percent,
            Double(mem.usedBytes) / 1_073_741_824,
            Double(mem.totalBytes) / 1_073_741_824,
            engine.gpu
        ))
    print("NET  down \(ByteFormat.rate(net.downBytesPerSec))   up \(ByteFormat.rate(net.upBytesPerSec))")
    print("Top download:")
    for p in procs.sorted(by: { $0.downBytesPerSec > $1.downBytesPerSec }).prefix(5) where p.downBytesPerSec > 0 {
        print("  \(ByteFormat.rate(p.downBytesPerSec))\t\(p.name)")
    }
    print("Top upload:")
    for p in procs.sorted(by: { $0.upBytesPerSec > $1.upBytesPerSec }).prefix(5) where p.upBytesPerSec > 0 {
        print("  \(ByteFormat.rate(p.upBytesPerSec))\t\(p.name)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

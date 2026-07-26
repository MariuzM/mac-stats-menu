import AppKit
import UniformTypeIdentifiers

enum AppInfo {
    struct Info {
        let icon: NSImage
        let name: String?
    }

    private static let iconSide: CGFloat = 16
    private static var cache: [Int: Info] = [:]
    private static let fallbackIcon = downsample(NSWorkspace.shared.icon(for: .unixExecutable))

    static func lookup(pid: Int) -> Info {
        if let cached = cache[pid] { return cached }
        let app = NSRunningApplication(processIdentifier: pid_t(pid))
        let icon = app?.icon.map(downsample) ?? fallbackIcon
        let info = Info(icon: icon, name: app?.localizedName)
        cache[pid] = info
        return info
    }

    static func clearCache() {
        cache.removeAll(keepingCapacity: false)
    }

    private static func downsample(_ image: NSImage) -> NSImage {
        let pixels = Int(iconSide * 2)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )
        else { return image }
        rep.size = NSSize(width: iconSide, height: iconSide)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: iconSide, height: iconSide))
        NSGraphicsContext.restoreGraphicsState()

        let out = NSImage(size: NSSize(width: iconSide, height: iconSide))
        out.addRepresentation(rep)
        return out
    }
}

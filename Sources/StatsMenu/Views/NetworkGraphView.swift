import AppKit

final class NetworkGraphView: NSView {
    var down: [Double] = [] { didSet { needsDisplay = true } }
    var up: [Double] = [] { didSet { needsDisplay = true } }
    var downColor: NSColor = .systemTeal
    var upColor: NSColor = .systemOrange

    override var isFlipped: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 44) }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: b, xRadius: 4, yRadius: 4).fill()

        let maxVal = max(down.max() ?? 0, up.max() ?? 0, 1)
        drawSeries(down, max: maxVal, in: b, color: downColor, fill: true)
        drawSeries(up, max: maxVal, in: b, color: upColor, fill: false)
    }

    private func drawSeries(_ values: [Double], max maxVal: Double, in b: NSRect, color: NSColor, fill: Bool) {
        guard values.count > 1 else { return }
        let n = values.count
        let stepX = b.width / CGFloat(n - 1)

        func point(_ i: Int) -> NSPoint {
            let v = min(1, values[i] / maxVal)
            return NSPoint(
                x: b.minX + CGFloat(i) * stepX,
                y: b.minY + CGFloat(v) * (b.height - 2) + 1)
        }

        let path = NSBezierPath()
        path.move(to: point(0))
        for i in 1..<n { path.line(to: point(i)) }

        color.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        if fill {
            path.line(to: NSPoint(x: b.maxX, y: b.minY))
            path.line(to: NSPoint(x: b.minX, y: b.minY))
            path.close()
            color.withAlphaComponent(0.18).setFill()
            path.fill()
        }
    }
}

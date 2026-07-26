import AppKit

final class MetricGraphView: NSView {
    var color: NSColor = .systemBlue
    var history: [Double] = [] {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 44) }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: b, xRadius: 4, yRadius: 4).fill()

        guard history.count > 1 else { return }
        let n = history.count
        let stepX = b.width / CGFloat(n - 1)

        func point(_ i: Int) -> NSPoint {
            let v = max(0, min(100, history[i]))
            return NSPoint(
                x: b.minX + CGFloat(i) * stepX,
                y: b.minY + CGFloat(v / 100) * (b.height - 2) + 1)
        }

        let line = NSBezierPath()
        line.move(to: point(0))
        for i in 1..<n { line.line(to: point(i)) }

        let area = line.copy() as! NSBezierPath
        area.line(to: NSPoint(x: b.maxX, y: b.minY))
        area.line(to: NSPoint(x: b.minX, y: b.minY))
        area.close()
        color.withAlphaComponent(0.18).setFill()
        area.fill()

        color.setStroke()
        line.lineWidth = 1.5
        line.stroke()
    }
}

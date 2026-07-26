import AppKit

final class UsageRow: NSStackView {
    private let baseTitle: String
    private let titleLabel: NSTextField
    private let lines: [LimitLineView]
    private let spinner = NSProgressIndicator()

    init(title: String, color: NSColor, lineCount: Int) {
        baseTitle = title
        titleLabel = NSTextField(labelWithString: title)
        lines = (0..<lineCount).map { _ in LimitLineView(color: color) }
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 5

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        spinner.style = .spinning
        spinner.controlSize = .mini
        spinner.isDisplayedWhenStopped = false

        let head = NSStackView(views: [titleLabel, spinner])
        head.orientation = .horizontal
        head.spacing = 6

        addArrangedSubview(head)
        for line in lines {
            line.isHidden = true
            addArrangedSubview(line)
            line.widthAnchor.constraint(equalToConstant: 232).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func setLoading(_ loading: Bool) {
        if loading {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    func update(subtitle: String? = nil, lines updates: [(title: String, fraction: Double, text: String)?]) {
        titleLabel.stringValue = subtitle.map { "\(baseTitle) · \($0)" } ?? baseTitle
        for (i, line) in lines.enumerated() {
            guard i < updates.count, let update = updates[i] else {
                line.isHidden = true
                continue
            }
            line.update(title: update.title, fraction: update.fraction, text: update.text)
            line.isHidden = false
        }
    }
}

private final class LimitLineView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let bar: UsageBarView

    init(color: NSColor) {
        bar = UsageBarView(color: color)
        super.init(frame: .zero)
        titleLabel.font = .systemFont(ofSize: 10)
        titleLabel.textColor = .secondaryLabelColor

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(bar)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 44),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 84),
            bar.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            bar.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -6),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(title: String, fraction: Double, text: String) {
        titleLabel.stringValue = title
        bar.fraction = fraction
        valueLabel.stringValue = text
    }
}

private final class UsageBarView: NSView {
    private let color: NSColor
    var fraction: Double = 0 { didSet { needsDisplay = true } }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let barHeight: CGFloat = 5
        let y = (bounds.height - barHeight) / 2
        let track = NSRect(x: 0, y: y, width: bounds.width, height: barHeight)
        NSColor.white.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()

        let width = track.width * CGFloat(max(0, min(1, fraction)))
        guard width > 0 else { return }
        color.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 0, y: y, width: max(barHeight, width), height: barHeight),
            xRadius: 2.5, yRadius: 2.5
        ).fill()
    }
}

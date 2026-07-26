import AppKit

class HoverStackView: NSStackView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

final class MetricRow: HoverStackView {
    private let valueLabel = NSTextField(labelWithString: "0%")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let graph = MetricGraphView()

    init(title: String, color: NSColor) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 3

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = color

        let head = NSStackView(views: [titleLabel, NSView(), valueLabel])
        head.orientation = .horizontal
        head.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor

        graph.color = color
        graph.translatesAutoresizingMaskIntoConstraints = false

        addArrangedSubview(head)
        addArrangedSubview(subtitleLabel)
        addArrangedSubview(graph)

        NSLayoutConstraint.activate([
            head.widthAnchor.constraint(equalToConstant: 232),
            graph.widthAnchor.constraint(equalToConstant: 232),
            graph.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(value: String, subtitle: String?, history: [Double]) {
        valueLabel.stringValue = value
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = subtitle == nil
        graph.history = history
    }
}

final class DualRateRow: HoverStackView {
    private let leftPrefix: String
    private let rightPrefix: String
    private let leftLabel = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let graph = NetworkGraphView()

    init(title: String, leftPrefix: String, rightPrefix: String, leftColor: NSColor, rightColor: NSColor) {
        self.leftPrefix = leftPrefix
        self.rightPrefix = rightPrefix
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 3

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        leftLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        leftLabel.textColor = leftColor
        rightLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        rightLabel.textColor = rightColor

        let head = NSStackView(views: [titleLabel, NSView(), leftLabel, rightLabel])
        head.orientation = .horizontal
        head.spacing = 8
        head.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor

        graph.downColor = leftColor
        graph.upColor = rightColor
        graph.translatesAutoresizingMaskIntoConstraints = false

        addArrangedSubview(head)
        addArrangedSubview(subtitleLabel)
        addArrangedSubview(graph)

        NSLayoutConstraint.activate([
            head.widthAnchor.constraint(equalToConstant: 232),
            graph.widthAnchor.constraint(equalToConstant: 232),
            graph.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(left: String, right: String, subtitle: String?, leftHistory: [Double], rightHistory: [Double]) {
        leftLabel.stringValue = leftPrefix + left
        rightLabel.stringValue = rightPrefix + right
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = subtitle == nil
        graph.down = leftHistory
        graph.up = rightHistory
    }
}

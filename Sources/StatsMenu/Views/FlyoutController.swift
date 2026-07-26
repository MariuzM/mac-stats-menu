import AppKit

struct DetailItem {
    let icon: NSImage
    let name: String
    let value: String
}

final class FlyoutController {
    static let shared = FlyoutController()

    private let detailVC = DetailListViewController(rowCount: 5)
    private let panel: NSPanel

    var window: NSWindow? { panel }

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentViewController = detailVC
    }

    func show(sections: [(String, [DetailItem])], relativeTo view: NSView) {
        detailVC.update(sections: sections)
        guard let window = view.window else { return }

        let size = detailVC.view.fittingSize
        panel.setContentSize(size)

        let rectInWindow = view.convert(view.bounds, to: nil)
        let screenRect = window.convertToScreen(rectInWindow)
        let gap: CGFloat = 8
        let origin = NSPoint(
            x: screenRect.minX - size.width - gap,
            y: screenRect.maxY - size.height)
        panel.setFrameOrigin(origin)

        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    func updateContent(sections: [(String, [DetailItem])]) {
        guard panel.isVisible else { return }
        detailVC.update(sections: sections)
        let size = detailVC.view.fittingSize
        if panel.frame.size != size {
            let frame = panel.frame
            panel.setFrame(
                NSRect(
                    x: frame.minX, y: frame.maxY - size.height,
                    width: size.width, height: size.height), display: true)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class DetailListViewController: NSViewController {
    private final class Group {
        let header = NSTextField(labelWithString: "")
        let rows: [ProcessRow]
        init(rowCount: Int) {
            rows = (0..<rowCount).map { _ in ProcessRow(width: 256) }
            header.font = .systemFont(ofSize: 10, weight: .semibold)
            header.textColor = .secondaryLabelColor
        }
    }

    private let emptyLabel = NSTextField(labelWithString: "Gathering…")
    private let groups: [Group]
    private var stack: NSStackView!

    init(rowCount: Int) {
        groups = [Group(rowCount: rowCount), Group(rowCount: rowCount)]
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.textColor = .tertiaryLabelColor

        var views: [NSView] = [emptyLabel]
        for group in groups {
            views.append(group.header)
            views += group.rows as [NSView]
        }

        stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        for group in groups.dropFirst() {
            stack.setCustomSpacing(12, after: previousView(before: group.header, in: views))
        }
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.panelBackground.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.widthAnchor.constraint(equalToConstant: 280),
        ])
        view = container
    }

    private func previousView(before target: NSView, in views: [NSView]) -> NSView {
        guard let idx = views.firstIndex(where: { $0 === target }), idx > 0 else { return target }
        return views[idx - 1]
    }

    func update(sections: [(String, [DetailItem])]) {
        let total = sections.reduce(0) { $0 + $1.1.count }
        emptyLabel.isHidden = total > 0

        for (i, group) in groups.enumerated() {
            if i < sections.count {
                let (title, items) = sections[i]
                group.header.stringValue = title.uppercased()
                group.header.isHidden = false
                for (j, row) in group.rows.enumerated() {
                    if j < items.count {
                        row.update(item: items[j])
                        row.isHidden = false
                    } else {
                        row.isHidden = true
                    }
                }
            } else {
                group.header.isHidden = true
                group.rows.forEach { $0.isHidden = true }
            }
        }
    }
}

private final class ProcessRow: NSStackView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    init(width: CGFloat) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        distribution = .fill
        spacing = 6

        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.usesSingleLineMode = true
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addArrangedSubview(iconView)
        addArrangedSubview(nameLabel)
        addArrangedSubview(valueLabel)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 18),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(item: DetailItem) {
        iconView.image = item.icon
        nameLabel.stringValue = item.name
        valueLabel.stringValue = item.value
    }
}

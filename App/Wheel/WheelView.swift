import AppKit

/// The radial ring: a disc of HUD material, one view per slot, and the
/// neutral centre showing the dragged file(s). Coordinates handed in and
/// out are relative to the wheel centre (y up), see `WheelGeometry`.
@MainActor
final class WheelView: NSView {
    /// Square side: the whole hit disc, which leaves room for a hovered slot to grow.
    static let side = 2 * WheelGeometry.hitRadius

    /// The window server sends drags in fully transparent pixels to the
    /// window below, so the hit disc gets an all but invisible fill.
    private static let hitDiscFill = NSColor.black.withAlphaComponent(0.01)

    private let material = NSVisualEffectView()
    private let centerView = WheelCenterView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private var slotViews: [WheelSlotView] = []
    private(set) var geometry = WheelGeometry(slotCount: 0)

    var highlightedSlot: Int? {
        didSet {
            guard highlightedSlot != oldValue else { return }
            let next = highlightedSlot.map { ($0 + 1) % max(slotViews.count, 1) }
            for (index, view) in slotViews.enumerated() {
                view.setHighlighted(index == highlightedSlot)
                // No hairline along either edge of the hovered segment.
                view.drawsSeparator = index != highlightedSlot && index != next
            }
        }
    }

    var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true

        let radius = WheelGeometry.outerRadius
        material.frame = NSRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = Self.discMask(radius: radius)
        addSubview(material)

        centerView.frame = NSRect(
            x: center.x - WheelGeometry.innerRadius, y: center.y - WheelGeometry.innerRadius,
            width: 2 * WheelGeometry.innerRadius, height: 2 * WheelGeometry.innerRadius
        )
        addSubview(centerView)

        emptyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        let ringMiddle = (WheelGeometry.innerRadius + WheelGeometry.outerRadius) / 2
        emptyLabel.frame = NSRect(x: center.x - 100, y: center.y + ringMiddle - 26, width: 200, height: 52)
        emptyLabel.isHidden = true
        addSubview(emptyLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setItems(_ items: [WheelItem], emptyMessage: String) {
        if !slotViews.isEmpty, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Theme.swapDuration
            layer?.add(fade, forKey: "swap")
        }
        slotViews.forEach { $0.removeFromSuperview() }
        geometry = WheelGeometry(slotCount: items.count)
        slotViews = items.enumerated().map { index, item in
            let view = WheelSlotView(frame: bounds, item: item, index: index, geometry: geometry)
            addSubview(view, positioned: .below, relativeTo: centerView)
            return view
        }
        emptyLabel.stringValue = emptyMessage
        emptyLabel.isHidden = !items.isEmpty
        highlightedSlot = nil
    }

    func setFiles(_ files: [URL]) {
        centerView.setFiles(files)
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.hitDiscFill.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    private static func discMask(radius: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: 2 * radius, height: 2 * radius), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}

// MARK: - Slot

/// One slot of the ring. Covers the whole wheel so that its wedge can be
/// drawn and scaled around the wheel centre.
@MainActor
private final class WheelSlotView: NSView {
    private static let angularGap: CGFloat = 0.012
    private static let iconPointSize: CGFloat = 18
    private static let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    /// Segments without a symbol (resize presets) show their label alone, larger.
    private static let labelOnlyFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let maxLabelWidth: CGFloat = 116

    private let index: Int
    private let geometry: WheelGeometry
    private let icon = PassiveImageView()
    private let label = NSTextField(labelWithString: "")
    private var isHighlighted = false
    var drawsSeparator = true {
        didSet { if drawsSeparator != oldValue { needsDisplay = true } }
    }

    init(frame: NSRect, item: WheelItem, index: Int, geometry: WheelGeometry) {
        self.index = index
        self.geometry = geometry
        super.init(frame: frame)
        wantsLayer = true

        let (title, symbol): (String, String) = switch item {
        case .segment(let segment): (segment.title, segment.symbol)
        case .more: (WheelItem.moreTitle, WheelItem.moreSymbol)
        case .back: (WheelItem.backTitle, WheelItem.backSymbol)
        }

        label.stringValue = title
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true

        let midRadius = (WheelGeometry.innerRadius + WheelGeometry.outerRadius) / 2
        let anchor = geometry.point(inSlot: index, radius: midRadius)
        let center = CGPoint(x: bounds.midX + anchor.x, y: bounds.midY + anchor.y)
        let arcLength = geometry.slotAngle * midRadius
        let labelWidth = min(arcLength * 0.85, Self.maxLabelWidth)
        if symbol.isEmpty {
            label.font = Self.labelOnlyFont
            label.maximumNumberOfLines = 1
            label.frame = NSRect(x: center.x - labelWidth / 2, y: center.y - 9, width: labelWidth, height: 18)
        } else {
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: Self.iconPointSize, weight: .medium))
            icon.frame = NSRect(x: center.x - 14, y: center.y + 2, width: 28, height: 24)
            addSubview(icon)
            label.font = Self.labelFont
            label.maximumNumberOfLines = 2
            label.frame = NSRect(x: center.x - labelWidth / 2, y: center.y - 28, width: labelWidth, height: 28)
        }
        addSubview(label)
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Hit-testing is done geometrically by the drop target, never by views.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setHighlighted(_ highlighted: Bool) {
        guard highlighted != isHighlighted else { return }
        isHighlighted = highlighted
        applyColors()
        needsDisplay = true

        let scale = highlighted ? Theme.hoverScale : 1
        let target = CATransform3D.scale(scale, about: CGPoint(x: bounds.midX, y: bounds.midY))
        guard let layer else { return }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = layer.presentation()?.transform ?? layer.transform
            animation.toValue = target
            animation.duration = Theme.hoverDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "hover")
        }
        layer.transform = target
    }

    private func applyColors() {
        let color: NSColor = isHighlighted ? Theme.onAccent : .labelColor
        icon.contentTintColor = color
        label.textColor = color
    }

    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let half = geometry.slotAngle / 2

        if isHighlighted {
            let path = Self.wedge(
                center: center,
                from: geometry.midAngle(ofSlot: index) - half + Self.angularGap,
                to: geometry.midAngle(ofSlot: index) + half - Self.angularGap
            )
            Theme.accent.setFill()
            path.fill()
        }

        // Each slot draws the separator at its own start edge.
        guard drawsSeparator, geometry.slotCount > 1 else { return }
        let start = geometry.midAngle(ofSlot: index) - half
        let separator = NSBezierPath()
        separator.move(to: Self.point(center, WheelGeometry.innerRadius, start))
        separator.line(to: Self.point(center, WheelGeometry.outerRadius, start))
        separator.lineWidth = 1
        NSColor.separatorColor.setStroke()
        separator.stroke()
    }

    /// Point at `radius`, `angle` radians clockwise from the top.
    private static func point(_ center: CGPoint, _ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * sin(angle), y: center.y + radius * cos(angle))
    }

    /// Ring sector between two clockwise-from-top angles.
    private static func wedge(center: CGPoint, from start: CGFloat, to end: CGFloat) -> NSBezierPath {
        // AppKit arcs use degrees, counter-clockwise from +x.
        func degrees(_ angle: CGFloat) -> CGFloat { 90 - angle * 180 / .pi }
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: WheelGeometry.outerRadius,
                       startAngle: degrees(start), endAngle: degrees(end), clockwise: true)
        path.appendArc(withCenter: center, radius: WheelGeometry.innerRadius,
                       startAngle: degrees(end), endAngle: degrees(start), clockwise: false)
        path.close()
        return path
    }
}

// MARK: - Centre

/// Neutral zone: icon and name of the dragged file, "×N" for several.
@MainActor
private final class WheelCenterView: NSView {
    private let icon = PassiveImageView()
    private let name = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        name.font = .systemFont(ofSize: 11)
        name.textColor = .labelColor
        name.alignment = .center
        name.lineBreakMode = .byTruncatingMiddle
        count.font = .systemFont(ofSize: 11, weight: .semibold)
        count.textColor = .secondaryLabelColor
        count.alignment = .center
        [icon, name, count].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let side: CGFloat = 36
        icon.frame = NSRect(x: bounds.midX - side / 2, y: bounds.midY - 8, width: side, height: side)
        name.frame = NSRect(x: 10, y: bounds.midY - 26, width: bounds.width - 20, height: 14)
        count.frame = NSRect(x: 10, y: bounds.midY - 40, width: bounds.width - 20, height: 14)
    }

    func setFiles(_ files: [URL]) {
        guard let first = files.first else { return }
        icon.image = NSWorkspace.shared.icon(for: FileTypes.type(of: first))
        // Several files: their number, not the first name ("Vacances ×3" read as copies).
        name.stringValue = files.count > 1 ? "\(files.count)\u{00A0}éléments" : first.lastPathComponent
        count.stringValue = ""
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
        circle.fill()
        NSColor.separatorColor.setStroke()
        circle.stroke()
    }
}

// MARK: - Title

/// "Convertir   ⌘ Outils   ⌃ Actions" in a small capsule above the ring:
/// the current wheel, then the keys of the others (a sub-wheel shows its title only).
@MainActor
final class WheelTitleView: NSView {
    static let height: CGFloat = 26

    private let material = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = Self.height / 2
        material.layer?.masksToBounds = true
        addSubview(material)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setMode(_ mode: WheelMode, title: String? = nil, triggers: TriggerMapping = .standard) {
        let heading = title ?? mode.title
        let text = NSMutableAttributedString(
            string: heading,
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor]
        )
        // The other wheels, named, so the keys need not be remembered. A
        // sub-wheel keeps its title alone: switching is rarely needed there.
        if heading == mode.title {
            for other in WheelMode.allCases where other != mode {
                text.append(NSAttributedString(
                    string: "   \(triggers.key(for: other).glyph)\u{00A0}\(other.title)",
                    attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
                ))
            }
        }
        // An attributed value ignores the field's own alignment.
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        text.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: text.length))
        label.attributedStringValue = text

        // Measure with the field itself: modifier glyphs come from a
        // fallback font that NSAttributedString.size() underestimates.
        let textSize = label.intrinsicContentSize
        let padding: CGFloat = 14
        let width = ceil(textSize.width) + 2 * padding
        material.frame = NSRect(x: (bounds.width - width) / 2, y: 0, width: width, height: Self.height)
        label.frame = NSRect(x: material.frame.minX, y: (Self.height - textSize.height) / 2,
                             width: width, height: textSize.height)
    }
}

/// Image view that is never a drop target. NSImageView registers for file
/// and image drags by default, which made every icon a dead spot on the wheel.
private final class PassiveImageView: NSImageView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        unregisterDraggedTypes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension CATransform3D {
    /// Scale around `center`, for layers whose anchor point is the origin
    /// (the AppKit default for layer-backed views).
    static func scale(_ factor: CGFloat, about center: CGPoint) -> CATransform3D {
        var transform = CATransform3DMakeTranslation(-center.x, -center.y, 0)
        transform = CATransform3DConcat(transform, CATransform3DMakeScale(factor, factor, 1))
        return CATransform3DConcat(transform, CATransform3DMakeTranslation(center.x, center.y, 0))
    }
}

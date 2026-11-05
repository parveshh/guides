import AppKit
import GuidesCore

@MainActor
final class OverlayCanvas: NSView {
    var model: EditorModel!
    var usableRect = CGRect.zero
    var onEscape: (() -> Void)?
    var onChange: (() -> Void)?
    var onCopy: (() -> Void)?
    private var dragStart: GuideDocument?
    private var draggingID: UUID?
    private var labels: [(CGRect, GuideGap)] = []
    private let rulerSize: CGFloat = 24
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func cancelOrHide() {
        if let dragStart {
            model.document = dragStart
            self.dragStart = nil
            draggingID = nil
            onChange?()
        } else { onEscape?() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOrHide() }
        else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" { onCopy?() }
        else { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        guard model.presentation.mode == .editing else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if model.presentation.tool == .guides, topRuler.contains(point) || leftRuler.contains(point) {
            dragStart = model.document
            let axis: GuideAxis = topRuler.contains(point) ? .horizontal : .vertical
            draggingID = model.document.add(axis: axis, position: axis.position(of: point))
        } else if let (_, gap) = labels.first(where: { $0.0.contains(point) }) {
            model.document.select(gap.ids)
        } else if let guide = model.document.guides.min(by: {
            abs($0.position - $0.axis.position(of: point)) < abs($1.position - $1.axis.position(of: point))
        }), abs(guide.position - guide.axis.position(of: point)) <= 6 {
            dragStart = model.document
            draggingID = guide.id
            model.document.select([guide.id])
        } else { model.document.select([]) }
        onChange?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let id = draggingID, let guide = model.document.guides.first(where: { $0.id == id }) else { return }
        let point = DisplayGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds.size)
        model.document.move(id: id, to: guide.axis.position(of: point))
        onChange?()
    }

    override func mouseUp(with event: NSEvent) {
        draggingID = nil
        dragStart = nil
    }

    private var topRuler: CGRect { CGRect(x: usableRect.minX, y: usableRect.minY, width: usableRect.width, height: rulerSize) }
    private var leftRuler: CGRect { CGRect(x: usableRect.minX, y: usableRect.minY + rulerSize, width: rulerSize, height: max(0, usableRect.height - rulerSize)) }

    override func draw(_ dirtyRect: NSRect) {
        guard model.presentation.mode != .hidden else { return }
        labels.removeAll()
        if model.presentation.mode == .editing { drawRulers() }
        for guide in model.document.guides {
            let start = guide.axis == .horizontal ? CGPoint(x: 0, y: guide.position) : CGPoint(x: guide.position, y: 0)
            let end = guide.axis == .horizontal ? CGPoint(x: bounds.width, y: guide.position) : CGPoint(x: guide.position, y: bounds.height)
            line(from: start, to: end, selected: model.document.selection.contains(guide.id))
        }
        let selected = model.document.selectedGap
        let gaps = model.document.adjacentGaps.sorted { a, b in
            let aSelected = Set(a.ids) == Set(selected?.ids ?? [])
            let bSelected = Set(b.ids) == Set(selected?.ids ?? [])
            return aSelected && !bSelected
        }
        var occupied: [CGRect] = []
        for gap in gaps {
            let selected = Set(gap.ids) == Set(model.document.selection)
            let anchor = gap.axis == .vertical
                ? CGPoint(x: gap.midpoint, y: usableRect.minY + 145)
                : CGPoint(x: usableRect.minX + 88, y: gap.midpoint)
            let text = MeasurementText.screenPoints(gap.distance)
            let rect = labelRect(text, centered: anchor)
            guard selected || !occupied.contains(where: { $0.intersects(rect) }) else { continue }
            occupied.append(rect)
            let start = gap.axis == .vertical ? CGPoint(x: gap.first.position, y: anchor.y) : CGPoint(x: anchor.x, y: gap.first.position)
            let end = gap.axis == .vertical ? CGPoint(x: gap.second.position, y: anchor.y) : CGPoint(x: anchor.x, y: gap.second.position)
            line(from: start, to: end, selected: selected)
            drawLabel(text, rect: rect, selected: selected)
            labels.append((rect, gap))
        }
        let text = model.presentation.mode == .pinned
            ? "Pinned · Manual · Screen pt · Edit Guides to resume"
            : "Drag from a ruler · Click a distance to copy · Esc hides"
        let rect = labelRect(text, centered: CGPoint(x: usableRect.midX, y: usableRect.maxY - 24))
        drawLabel(text, rect: rect, selected: false)
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
    }

    private func labelRect(_ text: String, centered point: CGPoint) -> CGRect {
        let size = (text as NSString).size(withAttributes: textAttributes)
        let width = min(size.width + 16, usableRect.width)
        return CGRect(x: min(max(point.x - width / 2, usableRect.minX), usableRect.maxX - width),
                      y: min(max(point.y - 12, usableRect.minY), usableRect.maxY - 24), width: width, height: 24)
    }

    private func drawLabel(_ text: String, rect: CGRect, selected: Bool) {
        NSColor(white: 0.08, alpha: 0.97).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        path.fill()
        (selected ? NSColor.systemYellow : NSColor(white: 0.55, alpha: 1)).setStroke()
        path.lineWidth = 1
        path.stroke()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 5), withAttributes: textAttributes)
    }

    private func line(from start: CGPoint, to end: CGPoint, selected: Bool) {
        let path = NSBezierPath()
        path.move(to: start); path.line(to: end)
        NSColor.black.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 3
        path.stroke()
        (selected ? NSColor.systemYellow : NSColor.cyan).setStroke()
        path.lineWidth = 1 / (window?.backingScaleFactor ?? 1)
        path.stroke()
    }

    private func drawRulers() {
        NSColor(white: 0.1, alpha: 0.97).setFill()
        topRuler.fill(); leftRuler.fill()
        for x in stride(from: ceil(usableRect.minX / 10) * 10, through: usableRect.maxX, by: 10) {
            let major = Int(x) % 100 == 0
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x, y: topRuler.maxY))
            path.line(to: CGPoint(x: x, y: topRuler.maxY - (major ? 10 : 5)))
            NSColor.gray.setStroke(); path.lineWidth = 1; path.stroke()
            if major { ("\(Int(x))" as NSString).draw(at: CGPoint(x: x + 3, y: topRuler.minY + 2), withAttributes: textAttributes) }
        }
        for y in stride(from: ceil(leftRuler.minY / 10) * 10, through: leftRuler.maxY, by: 10) {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: leftRuler.maxX, y: y))
            path.line(to: CGPoint(x: leftRuler.maxX - (Int(y) % 100 == 0 ? 10 : 5), y: y))
            NSColor.gray.setStroke(); path.lineWidth = 1; path.stroke()
        }
    }
}

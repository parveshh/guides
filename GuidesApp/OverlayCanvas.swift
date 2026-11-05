import AppKit
import GuidesCore

@MainActor
final class OverlayCanvas: NSView {
    var model: EditorModel!
    var usableRect = CGRect.zero
    var onEscape: (() -> Void)?
    var onChange: (() -> Void)?
    var onCopy: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    private var dragStart: MeasurementDocument?
    private var draggingID: UUID?
    private enum AreaDrag {
        case create(start: CGPoint, id: UUID)
        case move(start: CGPoint, rect: CGRect)
        case resize(handle: AreaHandle, rect: CGRect)
    }
    private var areaDrag: AreaDrag?
    private var labels: [(CGRect, GuideGap)] = []
    private let rulerSize: CGFloat = 24
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @discardableResult
    func cancelGesture() -> Bool {
        guard let dragStart else { return false }
        model.document = dragStart
        self.dragStart = nil
        areaDrag = nil
        draggingID = nil
        onChange?()
        return true
    }

    func cancelOrHide() { if !cancelGesture() { onEscape?() } }

    func handleCommand(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": onCopy?(); return true
        case "z":
            if event.modifierFlags.contains(.shift) { onRedo?() } else { onUndo?() }
            return true
        default: return false
        }
    }

    override func keyDown(with event: NSEvent) {
        if handleCommand(event) { return }
        if event.keyCode == 53 { cancelOrHide(); return }
        guard model.presentation.mode == .editing else { return }
        let flags = event.modifierFlags
        guard let action = KeyboardEditing.action(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
            command: flags.contains(.command), control: flags.contains(.control),
            option: flags.contains(.option), shift: flags.contains(.shift)) else {
            super.keyDown(with: event); return
        }
        cancelGesture()
        let before = model.document
        switch action {
        case .add(let axis):
            guard let window else { return }
            let point = DisplayGeometry(frame: window.frame).localPoint(fromGlobal: NSEvent.mouseLocation)
            model.document.add(axis: axis, position: axis.position(of: point))
        case .delete:
            model.document.deleteSelection()
        case .nudge(let dx, let dy, let precision):
            let step: CGFloat = precision == .backingPixel ? convertFromBacking(NSSize(width: 1, height: 1)).width
                : (precision == .tenPoints ? 10 : 1)
            model.document.nudge(dx: CGFloat(dx) * step, dy: CGFloat(dy) * step)
        }
        model.history.record(before: before, after: model.document)
        onChange?()
    }

    override func mouseDown(with event: NSEvent) {
        guard model.presentation.mode == .editing else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if model.presentation.tool == .area {
            dragStart = model.document
            if let area = model.document.area,
               let handle = AreaGeometry.hitHandle(at: point, rect: area.rect) {
                areaDrag = .resize(handle: handle, rect: area.rect)
                model.document.selectArea()
            } else if let area = model.document.area, area.rect.contains(point) {
                areaDrag = .move(start: point, rect: area.rect)
                model.document.selectArea()
            } else {
                let start = DisplayGeometry.clamp(point, to: bounds.size)
                let id = UUID()
                areaDrag = .create(start: start, id: id)
                model.document.setArea(CGRect(origin: start, size: .zero), id: id)
            }
            onChange?()
            return
        }
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
            model.document.selectGuide(guide.id, extending: event.modifierFlags.contains(.shift))
        } else { model.document.select([]) }
        onChange?()
    }

    override func mouseDragged(with event: NSEvent) {
        let current = DisplayGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds.size)
        if let areaDrag {
            switch areaDrag {
            case .create(let start, let id):
                model.document.setArea(AreaGeometry.rectangle(from: start, to: current, within: bounds.size), id: id)
            case .move(let start, let rect):
                model.document.setArea(AreaGeometry.moved(rect, dx: current.x - start.x, dy: current.y - start.y, within: bounds.size))
            case .resize(let handle, let rect):
                model.document.setArea(AreaGeometry.resized(rect, handle: handle, to: current, within: bounds.size))
            }
            onChange?()
            return
        }
        guard let id = draggingID, let guide = model.document.guides.first(where: { $0.id == id }) else { return }
        let point = DisplayGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds.size)
        model.document.move(id: id, to: guide.axis.position(of: point))
        onChange?()
    }

    override func mouseUp(with event: NSEvent) {
        if let dragStart {
            if areaDrag != nil, let rect = model.document.area?.rect, rect.width == 0 || rect.height == 0 {
                model.document = dragStart
            }
            model.history.record(before: dragStart, after: model.document)
        }
        areaDrag = nil
        draggingID = nil
        dragStart = nil
        onChange?()
    }

    private var topRuler: CGRect { CGRect(x: usableRect.minX, y: usableRect.minY, width: usableRect.width, height: rulerSize) }
    private var leftRuler: CGRect { CGRect(x: usableRect.minX, y: usableRect.minY + rulerSize, width: rulerSize, height: max(0, usableRect.height - rulerSize)) }

    override func draw(_ dirtyRect: NSRect) {
        guard model.presentation.mode != .hidden else { return }
        labels.removeAll()
        if model.presentation.mode == .editing { drawRulers() }
        drawArea()
        for guide in model.document.guides {
            let start = guide.axis == .horizontal ? CGPoint(x: 0, y: guide.position) : CGPoint(x: guide.position, y: 0)
            let end = guide.axis == .horizontal ? CGPoint(x: bounds.width, y: guide.position) : CGPoint(x: guide.position, y: bounds.height)
            line(from: start, to: end, selected: model.document.selection.contains(guide.id))
        }
        let selected = model.document.selectedGap
        var availableGaps = model.document.adjacentGaps
        if let selected, !availableGaps.contains(where: { Set($0.ids) == Set(selected.ids) }) {
            availableGaps.append(selected)
        }
        let gaps = availableGaps.sorted { a, b in
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
            : "H/V adds · Arrows nudge · ⇧ selects a pair · ⌘Z undo · Esc hides"
        let rect = labelRect(text, centered: CGPoint(x: usableRect.midX, y: usableRect.maxY - 24))
        drawLabel(text, rect: rect, selected: false)
    }

    private func drawArea() {
        guard let area = model.document.area else { return }
        let selected = model.document.isAreaSelected
        let path = NSBezierPath(rect: area.rect)
        NSColor.black.withAlphaComponent(0.85).setStroke(); path.lineWidth = 3; path.stroke()
        (selected ? NSColor.systemYellow : NSColor.cyan).setStroke()
        path.lineWidth = 1 / (window?.backingScaleFactor ?? 1); path.stroke()
        let text = "\(MeasurementText.number(area.rect.width)) × \(MeasurementText.number(area.rect.height)) screen pt"
        drawLabel(text, rect: labelRect(text, centered: CGPoint(x: area.rect.midX, y: area.rect.minY - 18)), selected: selected)
        if selected, model.presentation.mode == .editing, model.presentation.tool == .area {
            for handle in AreaHandle.allCases {
                let point = handle.point(on: area.rect)
                let handleRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                NSColor.black.setFill(); handleRect.fill()
                NSColor.systemYellow.setStroke(); NSBezierPath(rect: handleRect).stroke()
            }
        }
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

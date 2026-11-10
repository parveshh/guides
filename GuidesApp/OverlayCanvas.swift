import AppKit
import GuidesCore

@MainActor
final class OverlayCanvas: NSView {
    var model: EditorModel!
    var usableRect = CGRect.zero
    var controlsRect = CGRect.zero
    var readoutRect = CGRect.zero
    var onEscape: (() -> Void)?
    var onChange: (() -> Void)?
    var onCopy: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    private var referenceDrag: (start: CGPoint, placement: ReferencePlacement)?
    private var referenceImageID: UUID?
    private var referenceImage: NSImage?
    private var dragStart: MeasurementDocument?
    private var draggingID: UUID?
    private enum AreaDrag {
        case create(start: CGPoint, id: UUID)
        case move(start: CGPoint, rect: CGRect)
        case resize(handle: AreaHandle, rect: CGRect)
    }
    private var areaDrag: AreaDrag?
    /// True once the pointer has moved during a guide or Area gesture; a plain click keeps the halo.
    private var didDrag = false
    private var labels: [(CGRect, GuideGap)] = []
    private var accessibilityItems: [String: MeasurementAccessibilityElement] = [:]
    private let rulerSize: CGFloat = 24
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @discardableResult
    func cancelGesture() -> Bool {
        if model.annotations.cancel() { onChange?(); return true }
        if let referenceDrag {
            model.reference.overlay?.setPlacement(referenceDrag.placement, recording: false)
            self.referenceDrag = nil
            onChange?()
            return true
        }
        guard let dragStart else { return false }
        model.document = dragStart
        self.dragStart = nil
        areaDrag = nil
        draggingID = nil
        didDrag = false
        onChange?()
        return true
    }

    func cancelOrHide() {
        if cancelGesture() { return }
        if model.aligningReference { model.aligningReference = false; onChange?() }
        else { onEscape?() }
    }

    func handleCommand(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control) else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c" where !event.modifierFlags.contains(.shift): onCopy?(); return true
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
        if model.aligningReference {
            if case .nudge(let dx, let dy, let precision) = action, let placement = model.reference.overlay?.placement {
                let step: CGFloat = precision == .backingPixel ? 1 / model.backingFactor : (precision == .tenPoints ? 10 : 1)
                model.reference.overlay?.setPlacement(placement.moved(dx: CGFloat(dx) * step, dy: CGFloat(dy) * step,
                    displaySize: bounds.size))
                onChange?()
            }
            return
        }
        if model.isAnnotating {
            switch action {
            case .delete: model.annotations.deleteSelection()
            case .cycle(let backwards, _): model.annotations.cycle(backwards: backwards)
            case .nudge(let dx, let dy, let precision):
                let step: CGFloat = precision == .backingPixel ? 1 / model.backingFactor : (precision == .tenPoints ? 10 : 1)
                model.annotations.nudge(dx: CGFloat(dx) * step, dy: CGFloat(dy) * step)
            case .add: break
            }
            onChange?(); return
        }
        let before = model.document
        switch action {
        case .add(let axis):
            guard let window else { return }
            let point = DisplayGeometry(frame: window.frame).localPoint(fromGlobal: NSEvent.mouseLocation)
            model.document.add(axis: axis, position: PixelSnapping.snap(axis.position(of: point), backingFactor: model.backingFactor))
        case .delete:
            model.document.deleteSelection()
        case .cycle(let backwards, let extending):
            model.document.cycleSelection(backwards: backwards, extending: extending)
        case .nudge(let dx, let dy, let precision):
            let step: CGFloat = precision == .backingPixel ? convertFromBacking(NSSize(width: 1, height: 1)).width
                : (precision == .tenPoints ? 10 : 1)
            model.document.nudge(dx: CGFloat(dx) * step, dy: CGFloat(dy) * step)
        }
        model.history.record(before: before, after: model.document)
        onChange?()
    }

    /// Guides and Area edges placed with the pointer land on whole backing pixels.
    /// Holding Control places them freely.
    private func snapped(_ point: CGPoint, for event: NSEvent) -> CGPoint {
        event.modifierFlags.contains(.control) ? point : PixelSnapping.snap(point, backingFactor: model.backingFactor)
    }

    override func mouseDown(with event: NSEvent) {
        guard model.presentation.mode == .editing else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if model.aligningReference {
            if let placement = model.reference.overlay?.placement, placement.isVisible, placement.frame.contains(point) {
                referenceDrag = (point, placement)
            }
            return
        }
        if model.isAnnotating {
            model.annotations.begin(at: point); onChange?(); return
        }
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
                let start = snapped(DisplayGeometry.clamp(point, to: bounds.size), for: event)
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
            draggingID = model.document.add(axis: axis, position: axis.position(of: snapped(point, for: event)))
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
        if let referenceDrag {
            model.reference.overlay?.setPlacement(referenceDrag.placement.moved(dx: current.x - referenceDrag.start.x,
                dy: current.y - referenceDrag.start.y, displaySize: bounds.size), recording: false)
            onChange?()
            return
        }
        if model.annotations.isDragging {
            model.annotations.drag(to: current); onChange?(); return
        }
        if let areaDrag {
            didDrag = true
            let edge = snapped(current, for: event)
            switch areaDrag {
            case .create(let start, let id):
                model.document.setArea(AreaGeometry.rectangle(from: start, to: edge, within: bounds.size), id: id)
            case .move(let start, let rect):
                let dx = current.x - start.x, dy = current.y - start.y
                model.document.setArea(event.modifierFlags.contains(.control)
                    ? AreaGeometry.moved(rect, dx: dx, dy: dy, within: bounds.size)
                    : PixelSnapping.moved(rect, dx: dx, dy: dy, within: bounds.size, backingFactor: model.backingFactor))
            case .resize(let handle, let rect):
                model.document.setArea(AreaGeometry.resized(rect, handle: handle, to: edge, within: bounds.size))
                if let original = dragStart?.area, let area = model.document.area {
                    model.document.setCornerRadius(min(original.cornerRadius, area.maximumRadius))
                }
            }
            onChange?()
            return
        }
        guard let id = draggingID, let guide = model.document.guides.first(where: { $0.id == id }) else { return }
        didDrag = true
        model.document.move(id: id, to: guide.axis.position(of: snapped(current, for: event)))
        onChange?()
    }

    override func mouseUp(with event: NSEvent) {
        if model.annotations.isDragging { model.annotations.end() }
        if let referenceDrag, let placement = model.reference.overlay?.placement {
            model.reference.overlay?.record(before: referenceDrag.placement, after: placement)
            self.referenceDrag = nil
        }
        if let dragStart {
            if areaDrag != nil, let rect = model.document.area?.rect, rect.width == 0 || rect.height == 0 {
                model.document = dragStart
            }
            model.history.record(before: dragStart, after: model.document)
        }
        areaDrag = nil
        draggingID = nil
        didDrag = false
        dragStart = nil
        onChange?()
    }

    private var topRuler: CGRect { CGRect(x: usableRect.minX, y: usableRect.minY, width: usableRect.width, height: rulerSize) }
    private var leftRuler: CGRect {
        // The Dock reduces visibleFrame, but measurements still cover the entire display.
        CGRect(x: usableRect.minX, y: usableRect.minY + rulerSize, width: rulerSize,
               height: max(0, bounds.maxY - usableRect.minY - rulerSize))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard model.presentation.mode != .hidden else { return }
        labels.removeAll()
        drawReference()
        drawSpotlight()
        drawGrid()
        if model.presentation.mode == .editing { drawRulers() }
        drawGridOrigin()
        drawArea()
        for guide in model.document.guides {
            let start = guide.axis == .horizontal ? CGPoint(x: 0, y: guide.position) : CGPoint(x: guide.position, y: 0)
            let end = guide.axis == .horizontal ? CGPoint(x: bounds.width, y: guide.position) : CGPoint(x: guide.position, y: bounds.height)
            line(from: start, to: end, selected: model.document.selection.contains(guide.id), placing: didDrag && guide.id == draggingID)
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
        var occupied: [CGRect] = model.presentation.mode == .editing ? [controlsRect, readoutRect] : []
        if let area = model.document.area {
            occupied.append(labelRect(model.areaText(area.rect), centered: CGPoint(x: area.rect.midX, y: area.rect.minY - 18)))
        }
        for gap in gaps {
            let selected = Set(gap.ids) == Set(model.document.selection)
            let anchor = MeasurementReadoutLayout.gapAnchor(gap, usable: usableRect, toolbar: controlsRect)
            let text = model.text(gap.distance)
            let rect = labelRect(text, centered: anchor)
            guard selected || !occupied.contains(where: { $0.intersects(rect) }) else { continue }
            occupied.append(rect)
            let start = gap.axis == .vertical ? CGPoint(x: gap.first.position, y: anchor.y) : CGPoint(x: anchor.x, y: gap.first.position)
            let end = gap.axis == .vertical ? CGPoint(x: gap.second.position, y: anchor.y) : CGPoint(x: anchor.x, y: gap.second.position)
            line(from: start, to: end, selected: selected)
            if !selected || !model.showsMeasurementReadout {
                drawLabel(text, rect: rect, selected: selected)
                labels.append((rect, gap))
            }
        }
        drawAnnotations()
        drawHints()
        if let spotlight = model.annotations.document.spotlight {
            let status = "Spotlight · \(MeasurementText.number(spotlight.width)) × \(MeasurementText.number(spotlight.height)) screen pt · Outside dimming \(Int((model.annotations.document.dimOpacity * 100).rounded()))%"
            drawLabel(status, rect: labelRect(status, centered: CGPoint(x: usableRect.midX, y: usableRect.maxY - 120)), selected: false)
        }
        if let status = referenceStatus {
            drawLabel(status, rect: labelRect(status, centered: CGPoint(x: usableRect.midX, y: usableRect.maxY - 92)), selected: false)
        }
        if model.grid.isEnabled {
            drawLabel(model.gridStatus,
                rect: labelRect(model.gridStatus, centered: CGPoint(x: usableRect.midX, y: usableRect.maxY - 64)), selected: false)
        }
    }

    private var referenceStatus: String? {
        if model.reference.isLoading { return "Loading reference image…" }
        if let error = model.reference.error { return "Reference · " + error }
        guard let reference = model.reference.overlay, reference.placement.isVisible else { return nil }
        let frame = reference.placement.frame
        let detail = model.aligningReference ? "Align: drag / arrows · Esc finishes" : "Manual reference"
        return "\(detail) · \(reference.image.metadata.name) · \(MeasurementText.number(frame.width)) × \(MeasurementText.number(frame.height)) screen pt · (\(MeasurementText.number(frame.minX)), \(MeasurementText.number(frame.minY))) pt · \(Int((reference.placement.opacity * 100).rounded()))% opacity"
    }

    func refreshReferenceImage() {
        // A decode may complete during a drag of the previous image. Never apply that
        // gesture or its history to an image with a different source aspect ratio.
        if referenceImageID != model.reference.overlay?.id {
            referenceDrag = nil
            model.aligningReference = false
        }
        guard let reference = model.reference.overlay else {
            referenceImageID = nil; referenceImage = nil
            return
        }
        if referenceImageID != reference.id {
            referenceImageID = reference.id
            referenceImage = NSImage(cgImage: reference.image.preview, size: reference.sourceSize)
        }
    }

    private func drawReference() {
        guard let reference = model.reference.overlay, reference.placement.isVisible else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        referenceImage?.draw(in: reference.placement.frame, from: .zero, operation: .sourceOver,
            fraction: reference.placement.opacity, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        if model.aligningReference && model.presentation.mode == .editing {
            let border = NSBezierPath(rect: reference.placement.frame)
            NSColor.black.setStroke(); border.lineWidth = 3; border.stroke()
            NSColor.systemYellow.setStroke(); border.lineWidth = 1; border.stroke()
        }
    }

    private func drawGrid() {
        guard let geometry = model.gridGeometry else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        let path = NSBezierPath()
        for x in geometry.verticalLines {
            path.move(to: CGPoint(x: x, y: 0)); path.line(to: CGPoint(x: x, y: bounds.height))
        }
        for y in geometry.horizontalLines {
            path.move(to: CGPoint(x: 0, y: y)); path.line(to: CGPoint(x: bounds.width, y: y))
        }
        NSColor.black.withAlphaComponent(model.grid.opacity * 0.6).setStroke()
        path.lineWidth = 1.5; path.stroke()
        NSColor.cyan.withAlphaComponent(model.grid.opacity).setStroke()
        path.lineWidth = 1 / model.backingFactor; path.stroke()
    }

    private func drawGridOrigin() {
        guard model.gridGeometry != nil else { return }
        let origin = model.grid.origin
        let path = NSBezierPath(ovalIn: CGRect(x: origin.x - 5, y: origin.y - 5, width: 10, height: 10))
        path.move(to: CGPoint(x: origin.x - 9, y: origin.y)); path.line(to: CGPoint(x: origin.x + 9, y: origin.y))
        path.move(to: CGPoint(x: origin.x, y: origin.y - 9)); path.line(to: CGPoint(x: origin.x, y: origin.y + 9))
        NSColor.black.setStroke(); path.lineWidth = 3; path.stroke()
        NSColor.cyan.setStroke(); path.lineWidth = 1; path.stroke()
    }

    private func drawArea() {
        guard let area = model.document.area else { return }
        let selected = model.document.isAreaSelected
        let path = NSBezierPath(roundedRect: area.rect, xRadius: area.cornerRadius, yRadius: area.cornerRadius)
        let opacity = area.cornerRadius > 0 || model.areaDimension == .radius ? model.radiusOutlineOpacity : 1
        // While the Area is being dragged it draws as a bare 1-point core, like a guide being placed.
        let placing = didDrag && areaDrag != nil
        if !placing { OverlayStyle.halo.withAlphaComponent(0.45 * opacity).setStroke(); path.lineWidth = 3; path.stroke() }
        OverlayStyle.guide.withAlphaComponent(opacity).setStroke()
        path.lineWidth = selected && !placing ? 2 : 1; path.stroke()
        let text = model.areaText(area.rect) + (area.cornerRadius > 0 || model.areaDimension == .radius ? " · R " + model.text(area.cornerRadius) : "")
        if !selected || !model.showsMeasurementReadout {
            drawLabel(text, rect: labelRect(text, centered: CGPoint(x: area.rect.midX, y: area.rect.minY - 18)), selected: selected)
        }
        if selected, model.presentation.mode == .editing, model.presentation.tool == .area {
            for handle in AreaHandle.allCases {
                let point = handle.point(on: area.rect)
                let handle = NSBezierPath(ovalIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9))
                NSColor.white.setFill(); handle.fill()
                OverlayStyle.guide.setStroke(); handle.lineWidth = 1.5; handle.stroke()
            }
        }
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        [.font: OverlayStyle.labelFont, .foregroundColor: NSColor.white]
    }

    private func labelRect(_ text: String, centered point: CGPoint) -> CGRect {
        let size = (text as NSString).size(withAttributes: textAttributes)
        let width = min(size.width + 18, usableRect.width)
        return CGRect(x: min(max(point.x - width / 2, usableRect.minX), usableRect.maxX - width),
                      y: min(max(point.y - 12, usableRect.minY), usableRect.maxY - 24), width: width, height: 24)
    }

    private func drawLabel(_ text: String, rect: CGRect, selected: Bool) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        (selected ? OverlayStyle.guide : OverlayStyle.chip).setFill()
        path.fill()
        (selected ? NSColor(white: 1, alpha: 0.55) : OverlayStyle.chipBorder).setStroke()
        path.lineWidth = 1
        path.stroke()
        var attributes = textAttributes
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        attributes[.paragraphStyle] = paragraph
        (text as NSString).draw(in: CGRect(x: rect.minX + 8, y: rect.minY + 5, width: max(0, rect.width - 16), height: 17), withAttributes: attributes)
    }

    /// A pink core over a soft dark halo stays visible on light, dark and busy content.
    /// While a guide is being placed it draws as a bare 1-point core, so the pixels on
    /// either side of the measured position stay visible.
    private func line(from start: CGPoint, to end: CGPoint, selected: Bool, placing: Bool = false) {
        let path = NSBezierPath()
        path.move(to: start); path.line(to: end)
        let core: CGFloat = selected && !placing ? 2 : 1
        if !placing {
            OverlayStyle.halo.setStroke()
            path.lineWidth = core + 2
            path.stroke()
        }
        OverlayStyle.guide.setStroke()
        path.lineWidth = core
        path.stroke()
    }

    private func drawRulers() {
        let solid = model.rulerAppearance == .solid
        if solid {
            NSColor(white: 0.97, alpha: 1).setFill()
            topRuler.fill(); leftRuler.fill()
            NSColor(white: 0, alpha: 0.2).setFill()
            CGRect(x: leftRuler.maxX, y: topRuler.maxY - 0.5, width: topRuler.width - leftRuler.width, height: 0.5).fill()
            CGRect(x: leftRuler.maxX - 0.5, y: leftRuler.minY, width: 0.5, height: leftRuler.height).fill()
        }
        func length(_ value: CGFloat) -> CGFloat { Int(value) % 100 == 0 ? 9 : (Int(value) % 50 == 0 ? 6 : 4) }
        for x in stride(from: ceil(usableRect.minX / 10) * 10, through: usableRect.maxX, by: 10) {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x, y: topRuler.maxY))
            path.line(to: CGPoint(x: x, y: topRuler.maxY - length(x)))
            drawRulerTick(path)
            if Int(x) % 100 == 0 {
                drawRulerNumber(Int(x), at: CGPoint(x: x + 4, y: topRuler.minY + 1), vertical: false)
            }
        }
        for y in stride(from: ceil(leftRuler.minY / 10) * 10, through: leftRuler.maxY, by: 10) {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: leftRuler.maxX, y: y))
            path.line(to: CGPoint(x: leftRuler.maxX - length(y), y: y))
            drawRulerTick(path)
            if Int(y) % 100 == 0 {
                drawRulerNumber(Int(y), at: CGPoint(x: leftRuler.minX + 14, y: y + 4), vertical: true)
            }
        }
    }

    private func drawRulerTick(_ path: NSBezierPath) {
        if model.rulerAppearance == .transparent {
            // A light halo under a dark core reads on both light and dark content.
            NSColor(white: 1, alpha: 0.85).setStroke(); path.lineWidth = 3; path.stroke()
            NSColor(white: 0.1, alpha: 1).setStroke()
        } else { NSColor(white: 0.45, alpha: 1).setStroke() }
        path.lineWidth = 1
        path.stroke()
    }

    private func drawRulerNumber(_ value: Int, at point: CGPoint, vertical: Bool) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: vertical ? leftRuler : topRuler).addClip()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        if vertical { transform.rotate(byDegrees: 90) }
        transform.concat()
        let solid = model.rulerAppearance == .solid
        let text = "\(value)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: OverlayStyle.rulerFont,
            .foregroundColor: solid ? NSColor(white: 0.2, alpha: 1) : NSColor.white]
        if !solid {
            // Without a ruler background, each number carries its own chip so it reads over any content.
            let size = text.size(withAttributes: attributes)
            OverlayStyle.chip.setFill()
            NSBezierPath(roundedRect: CGRect(x: -3, y: -1, width: size.width + 6, height: size.height + 2), xRadius: 4, yRadius: 4).fill()
        }
        text.draw(at: .zero, withAttributes: attributes)
    }

    private var annotationStatus: String {
        let document = model.annotations.document
        let selected = document.selected.map { " · Selected \($0.kind.rawValue) at (\(MeasurementText.number($0.bounds.minX)), \(MeasurementText.number($0.bounds.minY))) screen pt" } ?? ""
        return "\(document.shapes.count) annotations" + selected + (document.spotlight == nil ? " · Spotlight off" : " · Spotlight on, \(Int((document.dimOpacity * 100).rounded()))% dimming")
    }

    func updateAccessibility() {
        let editing = model.presentation.mode == .editing
        setAccessibilityElement(editing)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Measurements")
        setAccessibilityValue([model.grid.isEnabled ? model.gridStatus : "Grid hidden", referenceStatus ?? "Reference hidden", annotationStatus].joined(separator: " · "))
        setAccessibilityHelp("H and V add guides at the pointer. Bracket keys select; Shift extends a parallel pair. Arrow keys move the selection.")
        guard editing else { setAccessibilityChildren([]); accessibilityItems = [:]; return }
        if model.aligningReference {
            setAccessibilityChildren([]); accessibilityItems = [:]
            setAccessibilityHelp("Align reference with arrow keys. Shift moves ten screen points; Option moves one backing pixel. Escape returns to measurements.")
            return
        }
        var updated: [String: MeasurementAccessibilityElement] = [:]
        var children: [MeasurementAccessibilityElement] = []
        func element(_ key: String, label: String, rect: CGRect, selected: Bool, action: @escaping @MainActor @Sendable () -> Void) -> MeasurementAccessibilityElement {
            let item = accessibilityItems[key] ?? MeasurementAccessibilityElement()
            item.setAccessibilityElement(true)
            item.setAccessibilityEnabled(true)
            item.setAccessibilityParent(self)
            item.setAccessibilityRole(.button)
            item.setAccessibilityLabel(label)
            item.setAccessibilityValue(selected ? "Selected" : "")
            item.setAccessibilityFrameInParentSpace(CGRect(x: rect.minX, y: bounds.maxY - rect.maxY, width: rect.width, height: rect.height))
            item.press = action
            updated[key] = item
            children.append(item)
            return item
        }
        if model.isAnnotating {
            setAccessibilityHelp("Annotation mode. Brackets select shapes; arrows nudge; Delete removes. Undo affects only annotations.")
            for shape in model.annotations.document.shapes {
                let label = "\(shape.kind.rawValue) annotation · \(shape.style.color.rawValue) · \(shape.style.stroke.rawValue) screen pt stroke" +
                    (model.annotations.document.spotlightID == shape.id ? " · Active spotlight" : "")
                _ = element(shape.id.uuidString, label: label, rect: shape.bounds.insetBy(dx: -6, dy: -6),
                    selected: model.annotations.document.selectedID == shape.id) { [weak self] in
                        guard let self, self.model.presentation.mode == .editing, self.model.isAnnotating else { return }
                        self.cancelGesture(); self.model.annotations.select(shape.id)
                        self.window?.makeFirstResponder(self); self.onChange?()
                    }
            }
            let changed = Set(updated.keys) != Set(accessibilityItems.keys)
            accessibilityItems = updated; setAccessibilityChildren(children)
            if changed { NSAccessibility.post(element: self, notification: .layoutChanged) }
            return
        }
        for guide in model.document.guides {
            let rect = guide.axis == .horizontal
                ? CGRect(x: usableRect.minX, y: guide.position - 3, width: usableRect.width, height: 6)
                : CGRect(x: guide.position - 3, y: usableRect.minY, width: 6, height: usableRect.height)
            let item = element(guide.id.uuidString,
                label: "\(guide.axis.rawValue.capitalized) guide at \(MeasurementText.screenPoints(guide.position))",
                rect: rect, selected: model.document.selection.contains(guide.id)) { [weak self] in
                    self?.selectAccessibleGuide(guide.id, extending: false)
                }
            item.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Select with current guide", handler: { [weak self] in
                guard let self, self.model.presentation.mode == .editing else { return false }
                self.selectAccessibleGuide(guide.id, extending: true)
                return true
            })])
        }
        var gaps = model.document.adjacentGaps
        if let selected = model.document.selectedGap, !gaps.contains(where: { Set($0.ids) == Set(selected.ids) }) { gaps.append(selected) }
        for gap in gaps {
            let anchor = MeasurementReadoutLayout.gapAnchor(gap, usable: usableRect, toolbar: controlsRect)
            _ = element(gap.ids.map(\.uuidString).joined(), label: "\(gap.axis == .horizontal ? "Vertical" : "Horizontal") gap \(model.text(gap.distance))",
                rect: labelRect(model.text(gap.distance), centered: anchor), selected: Set(gap.ids) == Set(model.document.selection)) { [weak self] in
                    guard let self, self.model.presentation.mode == .editing else { return }
                    self.cancelGesture(); self.model.document.select(gap.ids)
                    self.window?.makeFirstResponder(self); self.onChange?()
                }
        }
        if let area = model.document.area {
            _ = element(area.id.uuidString, label: "Area \(model.areaText(area.rect)) · Radius \(model.text(area.cornerRadius))", rect: area.rect, selected: model.document.isAreaSelected) { [weak self] in
                guard let self, self.model.presentation.mode == .editing else { return }
                self.cancelGesture(); self.model.document.selectArea(); self.model.presentation.edit(.area)
                self.window?.makeFirstResponder(self); self.onChange?()
            }
        }
        let changed = Set(updated.keys) != Set(accessibilityItems.keys)
        accessibilityItems = updated
        setAccessibilityChildren(children)
        if changed { NSAccessibility.post(element: self, notification: .layoutChanged) }
    }

    private func selectAccessibleGuide(_ id: UUID, extending: Bool) {
        guard model.presentation.mode == .editing else { return }
        cancelGesture()
        model.document.selectGuide(id, extending: extending)
        model.presentation.edit(.guides)
        window?.makeFirstResponder(self)
        onChange?()
    }
}

@MainActor
private final class MeasurementAccessibilityElement: NSAccessibilityElement {
    // AppKit installs and reads this callback on its main thread. The legacy accessibility
    // override is nonisolated; transfer only the Sendable closure, never the NSObject.
    nonisolated(unsafe) var press: (@MainActor @Sendable () -> Void)?
    override func accessibilityPerformPress() -> Bool {
        // AppKit dispatches accessibility actions on the application's main thread.
        let action = press
        return MainActor.assumeIsolated {
            guard let action else { return false }
            action()
            return true
        }
    }
}

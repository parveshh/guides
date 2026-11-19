import AppKit
import GuidesCore
import SwiftUI

/// Group canvases use their view bounds as the local coordinate system. The display canvas
/// remains the owner of rulers, annotations, reference imagery, and the full-display workspace.
@MainActor
final class GuideGroupOverlay: NSObject, NSPopoverDelegate {
    private struct Pane {
        let canvas: OverlayCanvas
        let header: NSButton
    }

    private let model: EditorModel
    private unowned let canvas: OverlayCanvas
    private unowned let root: NSView
    private let onChange: () -> Void
    private var panes: [UUID: Pane] = [:]
    private var marquee: GroupMarquee?
    private var popover: NSPopover?

    init(model: EditorModel, canvas: OverlayCanvas, root: NSView, onChange: @escaping () -> Void) {
        self.model = model
        self.canvas = canvas
        self.root = root
        self.onChange = onChange
    }

    private var showsGroups: Bool { !model.isAnnotating && !model.aligningReference }
    var activeCanvas: OverlayCanvas? {
        guard showsGroups, let id = model.groups.activeID else { return nil }
        return panes[id]?.canvas
    }
    var isBusy: Bool { marquee != nil || popover != nil || panes.values.contains { $0.canvas.hasActiveGesture } }

    func activate(_ id: UUID?) {
        guard model.groups.activeID != id else { return }
        model.groups.activeID = id
        onChange()
    }

    func cancel() {
        _ = cancelSetup()
        activeCanvas?.cancelGesture()
    }

    @discardableResult
    func cancelSetup() -> Bool {
        let hadSetup = marquee != nil || popover != nil
        popover?.close()
        marquee?.removeFromSuperview()
        marquee = nil
        return hadSetup
    }

    func sync() {
        let ids = Set(model.groups.items.map(\.id))
        for id in panes.keys.filter({ !ids.contains($0) }) {
            let removed = panes.removeValue(forKey: id)
            removed?.canvas.removeFromSuperview()
            removed?.header.removeFromSuperview()
        }
        for group in model.groups.items {
            let pane = panes[group.id] ?? makePane(group.id)
            let view = pane.canvas
            view.frame = canvas.convert(group.frame, to: root)
            view.usableRect = view.bounds
            view.controlsRect = view.convert(canvas.controlsRect, from: canvas)
            view.readoutRect = view.convert(canvas.readoutRect, from: canvas)
            view.model.backingFactor = model.backingFactor
            view.model.spacingScale = model.spacingScale
            view.model.presentation = model.presentation
            view.isHidden = !showsGroups
            view.updateAccessibility()
            view.needsDisplay = true

            let active = model.groups.activeID == group.id
            let cal = group.measurements.calibration
            let scale = cal.isConfirmed ? MeasurementText.number(cal.pointsPerPixel * 100) + "%" : "Set scale…"
            let title = (active ? "✓  " : "") + group.name + " · " + scale
            pane.header.title = title + (model.presentation.mode == .editing ? "  ▾" : "")
            pane.header.setAccessibilityLabel("Edit group " + group.name)
            pane.header.setAccessibilityValue((active ? "Active, " : "") + scale)
            pane.header.isHidden = !showsGroups
            let width = min(max(36, pane.header.fittingSize.width + 12), min(300, canvas.bounds.width))
            let x = min(group.frame.minX, max(0, canvas.bounds.maxX - width))
            let y = group.frame.minY >= canvas.usableRect.minY + 48 ? group.frame.minY - 24 : group.frame.minY
            pane.header.frame = canvas.convert(CGRect(x: x, y: y, width: width, height: 24), to: root)
        }
        let focused = activeCanvas?.model
        if model.selectedPane !== focused { model.selectedPane = focused }
    }

    private func makePane(_ id: UUID) -> Pane {
        let child = EditorModel()
        child.owner = model
        child.groupID = id
        let view = OverlayCanvas(frame: .zero)
        view.clipsToBounds = true
        view.model = child
        view.displayCanvas = canvas
        view.onActivate = { [weak self] in self?.activate(id) }
        view.onChange = { [weak self, weak child] in
            guard let self else { return }
            if let child, child.presentation.tool != model.presentation.tool {
                model.presentation.edit(child.presentation.tool)
            }
            onChange()
        }
        view.onEscape = canvas.onEscape
        view.onCopy = canvas.onCopy
        view.onUndo = canvas.onUndo
        view.onRedo = canvas.onRedo
        root.addSubview(view, positioned: .above, relativeTo: canvas)
        let button = GroupHeader(title: "", target: self, action: #selector(editHeader(_:)))
        button.bezelStyle = .smallSquare
        button.appearance = NSAppearance(named: .darkAqua)
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.lineBreakMode = .byTruncatingTail
        button.toolTip = "Activate this group and edit its name, region or scale."
        let topCanvas = root.subviews.last { $0 is OverlayCanvas }
        root.addSubview(button, positioned: .above, relativeTo: topCanvas)
        let pane = Pane(canvas: view, header: button)
        panes[id] = pane
        return pane
    }

    @objc private func editHeader(_ sender: NSButton) {
        guard let id = panes.first(where: { $0.value.header === sender })?.key else { return }
        editGroup(id)
    }

    func editGroup(_ id: UUID) {
        guard let sender = panes[id]?.header, let group = try? model.groups.group(id) else { return }
        cancel()
        activate(id)
        presentEditor(group: group, frame: group.frame, anchor: sender.bounds, view: sender)
    }

    func beginCreation() {
        guard showsGroups, model.presentation.mode == .editing else { return }
        canvas.cancelGesture()
        cancel()
        let view = GroupMarquee(frame: canvas.frame)
        view.autoresizingMask = [.width, .height]
        view.onDrawRegion = { [weak self, weak view] rect in
            guard let self, let view else { return }
            presentEditor(group: nil, frame: rect, anchor: CGRect(origin: rect.origin, size: CGSize(width: 4, height: 4)), view: view)
        }
        marquee = view
        root.addSubview(view)
        root.window?.makeFirstResponder(view)
    }

    private func presentEditor(group: GuideGroup?, frame: CGRect, anchor: CGRect, view: NSView) {
        let popup = NSPopover()
        popup.behavior = .transient
        popup.animates = false
        popup.appearance = NSAppearance(named: .darkAqua)
        let editor = GroupEditor(group: group, frame: frame, onApply: { [weak self] name, frame, percent in
            guard let self else { return }
            // Validate the whole edit before publishing it, including the effective scale.
            var groups = model.groups
            let id: UUID
            if let group {
                id = group.id
                try groups.edit(id, name: name, frame: frame, display: model.document.size)
            } else {
                id = try groups.create(name: name, frame: frame, display: model.document.size, rootPixels: model.calibration.rootPixels)
            }
            var workspace = try groups.group(id).measurements
            if let percent {
                let wasConfirmed = workspace.calibration.isConfirmed
                guard workspace.calibration.setScale(percent: percent) else { throw CommandLineError("Enter a positive finite scale.") }
                if !wasConfirmed { workspace.unit = .designPixels }
            }
            groups.update(id, measurements: workspace)
            groups.activeID = id
            model.groups = groups
            finishEditor()
        }, onCancel: { [weak self] in self?.finishEditor() }, onRemove: { [weak self] in
            guard let self, let group else { return }
            model.groups.remove(group.id)
            finishEditor()
        })
        let hosting = NSHostingController(rootView: editor)
        popup.contentViewController = hosting
        popup.contentSize = hosting.view.fittingSize
        popup.delegate = self
        popover = popup
        popup.show(relativeTo: anchor, of: view, preferredEdge: .maxY)
    }

#if DEBUG
    var fixtureEditor: GroupEditor? {
        (popover?.contentViewController as? NSHostingController<GroupEditor>)?.rootView
    }
    var draftView: NSView? { marquee }
#endif

    private func finishEditor() {
        cancelSetup()
        onChange()
        root.window?.makeFirstResponder(activeCanvas ?? canvas)
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closing = notification.object as? NSPopover, closing === popover else { return }
        popover = nil
        marquee?.removeFromSuperview()
        marquee = nil
        root.window?.makeFirstResponder(activeCanvas ?? canvas)
    }
}

/// Draw an opaque chip even when macOS composites a borderless panel over a light app.
@MainActor
private final class GroupHeader: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        OverlayStyle.chip.setFill()
        path.fill()
        OverlayStyle.chipBorder.setStroke()
        path.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white,
            .font: font ?? NSFont.systemFont(ofSize: 12), .paragraphStyle: paragraph]
        let text = title as NSString
        let height = text.size(withAttributes: attributes).height
        text.draw(in: CGRect(x: 8, y: bounds.midY - height / 2, width: max(0, bounds.width - 16), height: height),
                  withAttributes: attributes)
    }
}

@MainActor
private final class GroupMarquee: NSView {
    var onDrawRegion: ((CGRect) -> Void)?
    private var start: CGPoint?
    private var region: CGRect?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        region = nil
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        region = AreaGeometry.rectangle(from: start, to: convert(event.locationInWindow, from: nil), within: bounds.size)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        start = nil
        if let region, region.width > 0, region.height > 0 { onDrawRegion?(region) }
    }
    override func draw(_ dirtyRect: NSRect) {
        if let region {
            OverlayStyle.guide.withAlphaComponent(0.08).setFill()
            region.fill()
            OverlayStyle.guide.setStroke()
            NSBezierPath(rect: region).stroke()
        }
        let text = "Drag around a pane to create a Guide Group · Esc to cancel" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        let box = CGRect(x: bounds.midX - size.width / 2 - 12, y: bounds.midY - 16, width: size.width + 24, height: 32)
        OverlayStyle.chip.setFill()
        NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
        text.draw(at: CGPoint(x: box.minX + 12, y: box.midY - size.height / 2), withAttributes: attributes)
    }
}

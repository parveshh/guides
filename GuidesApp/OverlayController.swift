import AppKit
import GuidesCore
import KeyboardShortcuts
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class EditorModel {
    var presentation = Presentation()
    var document = MeasurementDocument(size: .zero)
    var history = DocumentHistory()
    var areaDimension: AreaDimension = .both
    var radiusOutlineOpacity: CGFloat = 0.35
    var magnifierPresented = false
    let magnifier = CornerMagnifier(source: CornerCaptureService())
    var calibration = Calibration()
    var unit: MeasurementUnit = .screenPoints
    var backingFactor: CGFloat = 1
    var controlsCompact = false
    var activationShortcut = ""
    var displayID: UInt32?
    var rulerAppearance: RulerAppearance = .solid
    var spacingScale: SpacingScale = .empty
    var breakpoints: BreakpointSet = .empty
    let reference = ReferenceOverlayModel()
    var aligningReference = false
    var annotations = AnnotationSession(size: .zero)
    var isAnnotating: Bool { presentation.tool == .annotate && !aligningReference }
    var showsMeasurementReadout: Bool { presentation.mode == .editing && !aligningReference && !isAnnotating && canCopy }
    var canUndo: Bool { aligningReference ? reference.overlay?.canUndo == true : (isAnnotating ? annotations.canUndo : history.canUndo) }
    var canRedo: Bool { aligningReference ? reference.overlay?.canRedo == true : (isAnnotating ? annotations.canRedo : history.canRedo) }
    var grid = GridConfiguration()
    var gridGeometry: GridGeometry?
    var gridStatus = ""
    var spacingDistance: CGFloat? {
        if document.isAreaSelected, let rect = document.area?.rect {
            switch areaDimension {
            case .width: return rect.width
            case .height: return rect.height
            case .both, .radius: return nil
            }
        }
        return document.selectedGap?.distance
    }
    var spacingMatch: SpacingMatch? {
        spacingDistance.flatMap { spacingScale.match(screenDistance: $0, calibration: calibration) }
    }
    var spacingHint: String {
        if !calibration.isConfirmed { return "Set scale to compare spacing tokens." }
        if document.isAreaSelected && (areaDimension == .both || areaDimension == .radius) { return "Select Width or Height to compare tokens." }
        return "This measurement cannot be compared."
    }
    var copyText: String? {
        if document.isAreaSelected, let rect = document.area?.rect, rect.width > 0, rect.height > 0 {
            return MeasurementEngine.areaText(rect, dimension: areaDimension, unit: unit,
                calibration: calibration, backingFactor: backingFactor, cornerRadius: document.area?.cornerRadius ?? 0)
        }
        return document.selectedGap.flatMap { MeasurementEngine.text($0.distance, unit: unit,
            calibration: calibration, backingFactor: backingFactor) }
    }
    var canCopy: Bool { copyText != nil }
    /// The selected measurement in screen points, for CSS and Tailwind copy formats.
    var copySubject: CopySubject? {
        if document.isAreaSelected, let area = document.area, area.rect.width > 0, area.rect.height > 0 {
            switch areaDimension {
            case .width: return .width(area.rect.width)
            case .height: return .height(area.rect.height)
            case .both: return .size(width: area.rect.width, height: area.rect.height)
            case .radius: return .radius(area.cornerRadius)
            }
        }
        return document.selectedGap.map { .gap($0.distance) }
    }
    func formattedCopy(_ format: CopyFormat) -> String? {
        copySubject.flatMap { CopyFormatter.text($0, format: format, unit: unit, calibration: calibration) }
    }
    var selectedText: String { copyText ?? "Select a measurement" }
    var contextText: String {
        let origin = document.isAreaSelected && areaDimension == .radius ? "Manual circular fit" : "Manual"
        if !unit.requiresCalibration { return "\(origin) · \(unit.rawValue)" }
        return "\(origin) · \(MeasurementText.number(calibration.pointsPerPixel * 100))% scale · \(MeasurementText.number(calibration.rootPixels))px/rem"
    }
    func text(_ distance: CGFloat) -> String {
        MeasurementEngine.text(distance, unit: unit, calibration: calibration, backingFactor: backingFactor) ?? "Unavailable"
    }
    func areaText(_ rect: CGRect) -> String {
        MeasurementEngine.areaText(rect, dimension: .both, unit: unit, calibration: calibration, backingFactor: backingFactor) ?? "Unavailable"
    }
}

@MainActor
final class OverlayPanel: NSPanel {
    var editing = false
    var onEscape: (() -> Void)?
    var onCommand: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { editing }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if TextEditingCommands.handle(event, responder: firstResponder) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if editing, event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        if editing, event.type == .keyDown, event.modifierFlags.contains(.command),
           !((firstResponder as? NSTextView)?.isFieldEditor ?? false), onCommand?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Reports when SwiftUI changes the toolbar's ideal size.
@MainActor
final class ToolbarHostingView<Content: View>: NSHostingView<Content> {
    var onIntrinsicSizeChange: (() -> Void)?
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicSizeChange?()
    }
}

@MainActor
private struct ToolbarConstraints {
    let width: NSLayoutConstraint
    let height: NSLayoutConstraint
    let top: NSLayoutConstraint
    let center: NSLayoutConstraint

    init(view: NSView, root: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        width = view.widthAnchor.constraint(equalToConstant: 1)
        height = view.heightAnchor.constraint(equalToConstant: 1)
        top = view.topAnchor.constraint(equalTo: root.topAnchor)
        center = view.centerXAnchor.constraint(equalTo: root.centerXAnchor)
        NSLayoutConstraint.activate([width, height, top, center])
    }

    func place(_ frame: CGRect, rootWidth: CGFloat) {
        width.constant = frame.width; height.constant = frame.height
        top.constant = frame.minY; center.constant = frame.midX - rootWidth / 2
    }
}

@MainActor
final class OverlayController {
    let model = EditorModel()
    private let preferences: GuidesPreferences
    private let onInspectImage: () -> Void
    private let onResizeWindow: () -> Void
    private let onSpacingTokens: () -> Void
    private let onSavedLayouts: () -> Void
    private let onProjectProfiles: () -> Void
    private let onBreakpoints: () -> Void
    private var layoutRecovery = LayoutLoadRecovery()
    private var panel: OverlayPanel?
    private var canvas: OverlayCanvas?
    private var controls: ToolbarHostingView<OverlayControls>?
    private var contextControls: ToolbarHostingView<OverlayContextControls>?
    private var mainConstraints: ToolbarConstraints?
    private var contextConstraints: ToolbarConstraints?
    private var annotationPopover: NSPopover?
    private var annotationPopoverSelection: UUID?
    private var annotationPopoverDisplay: UInt32?
    private var controlsWidthCheckPending = false
    private var readout: NSHostingView<MeasurementReadout>?
    private var previousApplication: NSRunningApplication?
    private var sessions = DisplaySessions()
    private var referencePicker: NSOpenPanel?

    init(preferences: GuidesPreferences, onInspectImage: @escaping () -> Void, onResizeWindow: @escaping () -> Void,
         onSpacingTokens: @escaping () -> Void, onSavedLayouts: @escaping () -> Void,
         onProjectProfiles: @escaping () -> Void, onBreakpoints: @escaping () -> Void) {
        self.preferences = preferences
        self.onInspectImage = onInspectImage
        self.onResizeWindow = onResizeWindow
        self.onSpacingTokens = onSpacingTokens
        self.onSavedLayouts = onSavedLayouts
        self.onProjectProfiles = onProjectProfiles
        self.onBreakpoints = onBreakpoints
        model.reference.onChange = { [weak self] in self?.saveSession(); self?.refresh() }
        model.calibration.setRootPixels(preferences.rootPixels)
        model.rulerAppearance = preferences.rulerAppearance
        model.spacingScale = preferences.spacingScale
        model.breakpoints = preferences.breakpoints
        preferences.onBreakpointsChange = { [weak self] value in
            self?.model.breakpoints = value
            self?.refresh()
        }
        preferences.onSpacingScaleChange = { [weak self] value in
            self?.model.spacingScale = value
            self?.refresh()
        }
        preferences.onRootChange = { [weak self] value in
            self?.model.calibration.setRootPixels(value)
            self?.refresh()
        }
        preferences.onRulerAppearanceChange = { [weak self] value in
            self?.model.rulerAppearance = value
            self?.refresh()
        }
    }

    func edit(_ tool: OverlayTool) {
        model.magnifierPresented = false; model.magnifier.stop()
        cancelReferenceImport()
        canvas?.cancelGesture()
        saveSession()
        layoutRecovery.invalidate(sessions.synchronize(NSScreen.screens.compactMap(\.guidesConfiguration)))
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main, let configuration = screen.guidesConfiguration,
              let session = sessions.activate(configuration.id, rootPixels: preferences.rootPixels) else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
        }
        model.presentation.edit(tool)
        updateActivationShortcut()
        model.document = session.document
        model.history = session.history
        model.calibration = session.calibration
        model.unit = session.unit
        model.areaDimension = session.areaDimension
        model.grid = session.grid
        model.annotations = session.annotations
        model.aligningReference = false
        model.reference.restore(session.reference)
        model.displayID = configuration.id
        if panel == nil { createPanel(screen: screen) }
        configureLayout(screen)
        panel?.editing = true
        panel?.ignoresMouseEvents = false
        refresh()
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeFirstResponder(canvas)
    }

    private func updateActivationShortcut() {
        model.activationShortcut = KeyboardShortcuts.getShortcut(for: .editGuides)?.description ?? ""
    }

    func toggleEditing() {
        if model.presentation.mode == .editing { pin() }
        else { edit(model.presentation.tool) }
    }

    func measureRadius() {
        edit(.area)
        model.areaDimension = .radius
        if model.document.area != nil { model.document.selectArea() }
        refresh()
    }

    func pin() {
        cancelReferenceImport()
        canvas?.cancelGesture()
        model.aligningReference = false
        model.presentation.pin()
        updateActivationShortcut()
        panel?.orderOut(nil)
        panel?.editing = false
        panel?.ignoresMouseEvents = true
        refresh()
        panel?.orderFrontRegardless()
        restoreFocusIfNeeded()
    }

    func hide() {
        cancelReferenceImport()
        canvas?.cancelGesture()
        model.aligningReference = false
        model.presentation.hide()
        panel?.editing = false
        panel?.orderOut(nil)
        refresh()
        restoreFocusIfNeeded()
    }

    func screenParametersChanged() {
        model.magnifierPresented = false; model.magnifier.stop()
        cancelReferenceImport()
        canvas?.cancelGesture()
        saveSession()
        let activeID = sessions.activeID
        let invalidated = sessions.synchronize(NSScreen.screens.compactMap(\.guidesConfiguration))
        layoutRecovery.invalidate(invalidated)
        if let activeID, invalidated.contains(activeID) {
            hide()
            model.document = MeasurementDocument(size: .zero)
            model.history = DocumentHistory()
            model.calibration = Calibration(rootPixels: preferences.rootPixels)
            model.unit = .screenPoints
            model.grid = GridConfiguration()
            model.annotations = AnnotationSession(size: .zero)
            model.reference.restore(nil)
            model.displayID = nil
        } else if let activeID, let screen = NSScreen.screens.first(where: { $0.guidesConfiguration?.id == activeID }) {
            configureLayout(screen)
        }
        refresh()
    }

    private func currentSession() -> DisplaySession {
        var session = DisplaySession(size: model.document.size, rootPixels: preferences.rootPixels)
        session.document = model.document
        session.history = model.history
        session.calibration = model.calibration
        session.unit = model.unit
        session.areaDimension = model.areaDimension
        session.grid = model.grid
        session.reference = model.reference.overlay
        session.annotations = model.annotations
        return session
    }

    private func saveSession() { sessions.save(currentSession()) }

    func prepareSavedLayouts() -> DisplayConfiguration? {
        if model.displayID == nil || model.presentation.mode == .hidden { edit(model.presentation.tool) }
        cancelReferenceImport()
        canvas?.cancelGesture()
        guard let target = NSScreen.screens.compactMap(\.guidesConfiguration).first(where: { $0.id == model.displayID }) else { return nil }
        hide()
        return target
    }

    private func layoutScreen(_ target: DisplayConfiguration) throws -> NSScreen {
        guard model.displayID == target.id, model.document.size == target.size,
              let screen = NSScreen.screens.first(where: { $0.guidesConfiguration == target }) else { throw LayoutError.unavailable }
        return screen
    }

    func captureLayout(on target: DisplayConfiguration) throws -> SavedLayoutContent {
        _ = try layoutScreen(target)
        canvas?.cancelGesture()
        return try SavedLayoutContent(session: currentSession(), backingFactor: target.backingFactor)
    }

    func canUndoLayoutLoad(on target: DisplayConfiguration) -> Bool {
        (try? layoutScreen(target)) != nil && layoutRecovery.canUndo(on: target)
    }

    func loadLayout(_ content: SavedLayoutContent, on target: DisplayConfiguration) throws {
        let screen = try layoutScreen(target)
        canvas?.cancelGesture()
        var session = currentSession()
        try layoutRecovery.load(content, into: &session, on: target)
        applyLayoutSession(session, screen: screen)
    }

    func undoLayoutLoad(on target: DisplayConfiguration) throws {
        let screen = try layoutScreen(target)
        canvas?.cancelGesture()
        var session = currentSession()
        try layoutRecovery.undo(into: &session, on: target)
        applyLayoutSession(session, screen: screen)
    }

    private func applyLayoutSession(_ session: DisplaySession, screen: NSScreen) {
        cancelReferenceImport()
        model.document = session.document
        model.history = session.history
        model.calibration = session.calibration
        model.unit = session.unit
        model.areaDimension = session.areaDimension
        model.grid = session.grid
        model.annotations = session.annotations
        model.aligningReference = false
        model.presentation.edit(model.presentation.tool)
        configureLayout(screen)
        panel?.editing = true
        panel?.ignoresMouseEvents = false
        refresh()
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeFirstResponder(canvas)
    }

    private func configureLayout(_ screen: NSScreen) {
        panel?.setFrame(screen.frame, display: true)
        let usable = DisplayGeometry(frame: screen.frame).localRect(fromGlobal: screen.visibleFrame)
        canvas?.usableRect = usable
        model.backingFactor = screen.guidesConfiguration?.backingFactor ?? 1
        // Leave room for all labels; narrower displays split only the main bar.
        model.controlsCompact = usable.width < 940
        layoutControls()
    }

    private func layoutControls() {
        guard let controls, let contextControls, let canvas, let root = panel?.contentView,
              !model.annotations.isDragging else { return }
        let available = max(0, canvas.usableRect.width - 32)
        func size(_ view: NSView) -> CGSize {
            let ideal = view.intrinsicContentSize
            return CGSize(width: min(available, max(0, ceil(ideal.width))), height: max(0, ceil(ideal.height)))
        }
        let main = size(controls), context = size(contextControls)
        let combined = CGSize(width: max(main.width, context.width), height: main.height + context.height)
        let preferred = CGRect(x: canvas.usableRect.midX - combined.width / 2, y: canvas.usableRect.minY + 32,
            width: combined.width, height: combined.height)
        let frame = AnnotationGeometry.toolbarFrame(preferred: preferred, usable: canvas.usableRect,
            spotlight: model.annotations.document.spotlight)
        mainConstraints?.place(CGRect(x: frame.midX - main.width / 2, y: frame.minY,
            width: main.width, height: main.height), rootWidth: root.bounds.width)
        contextConstraints?.place(CGRect(x: frame.midX - context.width / 2, y: frame.minY + main.height,
            width: context.width, height: context.height), rootWidth: root.bounds.width)
        // Separate hosting views leave the space around the smaller strip available to the canvas.
        canvas.controlsRect = frame
    }

    /// SwiftUI publishes new ideal sizes a turn after tool or compact-layout changes.
    private func controlsContentSizeChanged() {
        guard !controlsWidthCheckPending else { return }
        controlsWidthCheckPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.controlsWidthCheckPending = false
            self.layoutControls()
            self.panel?.contentView?.layoutSubtreeIfNeeded()
            self.positionReadout()
        }
    }

    private func restoreFocusIfNeeded() {
        // A nonactivating panel normally leaves the underlying app active already.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApplication?.activate()
        }
    }

    private func createPanel(screen: NSScreen) {
        let panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.title = "Guides Measurements"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.setAccessibilityLabel("Guides measurement overlay")
        let root = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let canvas = OverlayCanvas(frame: root.bounds)
        canvas.autoresizingMask = [.width, .height]
        canvas.model = model
        canvas.onEscape = { [weak self] in self?.hide() }
        panel.onEscape = { [weak canvas] in canvas?.cancelOrHide() }
        canvas.onChange = { [weak self] in self?.refresh() }
        canvas.onCopy = { [weak self] in self?.copySelection() }
        canvas.onUndo = { [weak self] in self?.undo() }
        canvas.onRedo = { [weak self] in self?.redo() }
        panel.onCommand = { [weak canvas] event in canvas?.handleCommand(event) ?? false }
        root.addSubview(canvas)
        let controls = ToolbarHostingView(rootView: OverlayControls(model: model,
            onRulerAppearance: { [weak self] in self?.preferences.setRulerAppearance($0) },
            onInspectImage: onInspectImage, onResizeWindow: onResizeWindow, onSpacingTokens: onSpacingTokens, onSavedLayouts: onSavedLayouts,
            onProjectProfiles: onProjectProfiles, onBreakpoints: onBreakpoints,
            onTool: { [weak self] tool in
                guard let self else { return }
                self.model.magnifierPresented = false; self.model.magnifier.stop()
                self.canvas?.cancelGesture(); self.model.aligningReference = false
                self.model.presentation.edit(tool); self.refresh()
            },
            onGrid: { [weak self] grid in
                self?.canvas?.cancelGesture(); self?.model.grid = grid; self?.refresh()
            },
            onAnnotationClear: { [weak self] in self?.editAnnotations { $0.clear() } },
            onUndo: { [weak self] in self?.undo() }, onRedo: { [weak self] in self?.redo() },
            onPin: { [weak self] in self?.pin() }, onHide: { [weak self] in self?.hide() }))
        controls.sizingOptions = [.intrinsicContentSize]
        controls.onIntrinsicSizeChange = { [weak self] in self?.controlsContentSizeChanged() }
        root.addSubview(controls)
        mainConstraints = ToolbarConstraints(view: controls, root: root)
        let contextControls = ToolbarHostingView(rootView: OverlayContextControls(model: model,
            onUnit: { [weak self] unit in self?.model.unit = unit; self?.refresh() },
            onCalibration: { [weak self] calibration in
                self?.model.calibration = calibration
                self?.preferences.setRootPixels(calibration.rootPixels)
                self?.refresh()
            },
            onGrid: { [weak self] grid in
                self?.canvas?.cancelGesture()
                self?.model.grid = grid
                self?.refresh()
            },
            onReferenceOpen: { [weak self] in self?.openReference() },
            onReferenceApply: { [weak self] placement in
                self?.canvas?.cancelGesture()
                self?.model.reference.overlay?.setPlacement(placement)
                self?.model.aligningReference = false
                self?.refresh()
            },
            onReferenceAlign: { [weak self] in
                self?.model.aligningReference = true
                self?.panel?.makeFirstResponder(self?.canvas)
                self?.refresh()
            },
            onReferenceRemove: { [weak self] in
                self?.canvas?.cancelGesture()
                self?.model.aligningReference = false
                self?.model.reference.restore(nil)
            },
            onAnnotationTool: { [weak self] tool in self?.editAnnotations { $0.setTool(tool) } },
            onAnnotationColor: { [weak self] color in self?.editAnnotations { $0.setColor(color) } },
            onAnnotationOptions: { [weak self] in self?.showAnnotationOptions() }))
        contextControls.sizingOptions = [.intrinsicContentSize]
        contextControls.onIntrinsicSizeChange = { [weak self] in self?.controlsContentSizeChanged() }
        root.addSubview(contextControls)
        contextConstraints = ToolbarConstraints(view: contextControls, root: root)
        let readout = NSHostingView(rootView: MeasurementReadout(model: model,
            onDimension: { [weak self] dimension in self?.model.areaDimension = dimension; self?.refresh() },
            onRadius: { [weak self] value in
                guard let self else { return }
                self.canvas?.cancelGesture()
                let before = self.model.document
                self.model.document.setCornerRadius(value)
                self.model.history.record(before: before, after: self.model.document)
                if !self.model.magnifierPresented { self.panel?.makeFirstResponder(self.canvas) }
                self.refresh()
            },
            onNudgeArea: { [weak self] dx, dy in
                guard let self else { return }
                self.canvas?.cancelGesture()
                let before = self.model.document
                self.model.document.nudge(dx: dx, dy: dy)
                self.model.history.record(before: before, after: self.model.document)
                self.refresh()
            },
            onOpacity: { [weak self] opacity in self?.model.radiusOutlineOpacity = opacity; self?.refresh() },
            onCopy: { [weak self] in self?.copySelection() },
            onCopyAs: { [weak self] format in self?.copyFormatted(format) },
            onCopyVariable: { [weak self] in self?.copyVariable() }))
        readout.sizingOptions = []
        readout.isHidden = true
        root.addSubview(readout)
        panel.contentView = root
        self.panel = panel
        self.canvas = canvas
        self.controls = controls
        self.contextControls = contextControls
        self.readout = readout
    }

    func clear() {
        canvas?.cancelGesture()
        let before = model.document
        model.document.clear()
        model.history.record(before: before, after: model.document)
        refresh()
    }

    private func undo() {
        canvas?.cancelGesture()
        if model.aligningReference { model.reference.overlay?.undo() }
        else if model.isAnnotating { model.annotations.undo() }
        else if let document = model.history.undo(current: model.document) { model.document = document }
        refresh()
    }

    private func redo() {
        canvas?.cancelGesture()
        if model.aligningReference { model.reference.overlay?.redo() }
        else if model.isAnnotating { model.annotations.redo() }
        else if let document = model.history.redo(current: model.document) { model.document = document }
        refresh()
    }

    private func copySelection() {
        guard !model.isAnnotating, !model.aligningReference, let text = model.copyText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyFormatted(_ format: CopyFormat) {
        guard !model.isAnnotating, !model.aligningReference, let text = model.formattedCopy(format) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        panel?.makeFirstResponder(canvas)
    }

    private func copyVariable() {
        guard let text = model.spacingMatch?.copyReference else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func editAnnotations(_ change: (inout AnnotationSession) -> Void) {
        canvas?.cancelGesture()
        change(&model.annotations)
        panel?.makeFirstResponder(canvas)
        refresh()
    }

    private func showAnnotationOptions() {
        guard model.isAnnotating, model.presentation.mode == .editing, let canvas, let contextControls else { return }
        if annotationPopover?.isShown == true { annotationPopover?.close(); return }
        canvas.cancelGesture()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)
        annotationPopoverSelection = model.annotations.document.selectedID
        annotationPopoverDisplay = model.displayID
        let options = AnnotationOptions(session: model.annotations,
            onApply: { [weak self] style, spotlight, opacity in
                self?.annotationPopover?.close()
                self?.editAnnotations { $0.apply(style: style, spotlight: spotlight, dimOpacity: opacity) }
            }, onCancel: { [weak self] in self?.annotationPopover?.close() },
            onDelete: { [weak self] in
                self?.annotationPopover?.close(); self?.editAnnotations { $0.deleteSelection() }
            })
        let hosting = NSHostingController(rootView: options)
        popover.contentViewController = hosting
        popover.contentSize = hosting.view.fittingSize
        annotationPopover = popover
        if let shape = model.annotations.document.selected {
            // A small nonempty anchor keeps the popover beside the lower edge, including for straight lines.
            let anchor = CGRect(x: shape.bounds.midX - 2, y: min(shape.bounds.maxY, canvas.bounds.maxY - 4), width: 4, height: 4)
            popover.show(relativeTo: anchor.intersection(canvas.bounds), of: canvas, preferredEdge: .maxY)
        } else {
            popover.show(relativeTo: contextControls.bounds, of: contextControls, preferredEdge: .minY)
        }
    }

    private func cancelReferenceImport() {
        let picker = referencePicker
        referencePicker = nil
        picker?.cancel(nil)
        model.reference.cancelImport()
    }

    private func openReference() {
        guard let panel, referencePicker == nil, model.presentation.mode == .editing,
              let displayID = model.displayID else { return }
        canvas?.cancelGesture()
        model.aligningReference = false
        let picker = NSOpenPanel()
        referencePicker = picker
        picker.title = "Open Reference Image"
        picker.prompt = "Use Reference"
        picker.allowedContentTypes = [.image]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        picker.beginSheetModal(for: panel) { [weak self] response in
            guard let self, self.referencePicker === picker else { return }
            self.referencePicker = nil
            guard self.model.displayID == displayID, self.model.presentation.mode == .editing else { return }
            if response == .OK, let url = picker.url {
                self.model.reference.load(url, displaySize: self.model.document.size)
            }
            self.panel?.makeFirstResponder(self.canvas)
            self.refresh()
        }
    }

    private func refresh() {
        if !model.showsMeasurementReadout || !model.document.isAreaSelected || model.areaDimension != .radius {
            model.magnifierPresented = false; model.magnifier.stop()
        }
        model.gridGeometry = nil
        model.gridStatus = ""
        if model.grid.isEnabled {
            do {
                let geometry = try GridGeometry(configuration: model.grid, size: model.document.size,
                    calibration: model.calibration, backingFactor: model.backingFactor)
                model.gridGeometry = geometry
                model.gridStatus = geometry.summary(configuration: model.grid, calibration: model.calibration)
            } catch { model.gridStatus = "Grid paused · " + error.localizedDescription }
        }
        controls?.isHidden = model.presentation.mode != .editing
        contextControls?.isHidden = model.presentation.mode != .editing
        if !model.isAnnotating || model.presentation.mode != .editing || model.annotations.isDragging
            || annotationPopoverSelection != model.annotations.document.selectedID || annotationPopoverDisplay != model.displayID {
            annotationPopover?.close()
        }
        if !model.annotations.isDragging { layoutControls() }
        panel?.contentView?.layoutSubtreeIfNeeded()
        canvas?.refreshReferenceImage()
        positionReadout()
        canvas?.updateAccessibility()
        canvas?.needsDisplay = true
    }

    private func positionReadout() {
        guard let canvas, let readout, let root = panel?.contentView else { return }
        guard model.showsMeasurementReadout else {
            readout.isHidden = true
            canvas.readoutRect = .zero
            return
        }
        let area = model.document.isAreaSelected ? model.document.area?.rect : nil
        let gap = model.document.selectedGap
        let anchor: CGPoint
        if let area { anchor = CGPoint(x: area.midX, y: area.midY) }
        else if let gap { anchor = MeasurementReadoutLayout.gapAnchor(gap, usable: canvas.usableRect, toolbar: canvas.controlsRect) }
        else { return }
        let valueWidth = (model.selectedText as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold)]).width
        let contextWidth = (model.contextText as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
        let radius = area != nil && model.areaDimension == .radius
        let hasTokens = !model.spacingScale.tokens.isEmpty && !radius
        let size = CGSize(width: min(520, max(hasTokens ? 420 : (radius ? 400 : 360), max(valueWidth, contextWidth) + 250)),
            height: (area == nil ? 80 : 124) + (hasTokens ? 100 : 0) + (radius ? 146 : 0))
        let frame = MeasurementReadoutLayout.frame(size: size, anchor: anchor, beside: gap?.axis == .horizontal,
            usable: canvas.usableRect, toolbar: canvas.controlsRect, area: area)
        readout.frame = canvas.convert(frame, to: root)
        readout.isHidden = false
        canvas.readoutRect = frame
    }
}

private extension NSScreen {
    var guidesConfiguration: DisplayConfiguration? {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return DisplayConfiguration(id: id.uint32Value, size: frame.size,
            backingFactor: convertRectToBacking(CGRect(origin: frame.origin, size: CGSize(width: 1, height: 1))).width)
    }
}

#if DEBUG
extension OverlayController {
    /// A synthetic viewport for repeatable view rendering, independent of attached hardware.
    func designSetViewport(_ size: CGSize) {
        panel?.setContentSize(size)
        canvas?.usableRect = CGRect(origin: .zero, size: size)
        model.controlsCompact = size.width < 940
        refresh()
    }

    func designSnapshotOptions(to directory: URL) {
        showAnnotationOptions()
        precondition(annotationPopover?.isShown == true, "Annotation style popover did not open")
        if let view = annotationPopover?.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            DesignSnapshots.write(view, name: "4-annotation-style", to: directory, crop: view.bounds.size, backdrop: false)
            if let popupWindow = view.window, let panel, let root = panel.contentView {
                let global = popupWindow.convertToScreen(view.convert(view.bounds, to: nil))
                let local = DisplayGeometry(frame: panel.frame).localRect(fromGlobal: global)
                DesignSnapshots.write(root, name: "4-annotate-with-style", to: directory, crop: root.bounds.size,
                    backdrop: true, floatingView: view, floatingRect: local)
            }
        }
        let selected = model.annotations.document.selectedID
        model.annotations.select(nil)
        refresh()
        precondition(annotationPopover?.isShown != true, "Style popover survived a selection change")
        model.annotations.select(selected)
        showAnnotationOptions()
        precondition(annotationPopover?.isShown == true, "Style popover did not reopen")
        model.presentation.edit(.area)
        refresh()
        precondition(annotationPopover?.isShown != true, "Style popover survived a tool change")
        model.presentation.edit(.annotate)
        showAnnotationOptions()
        pin()
        precondition(annotationPopover?.isShown != true, "Style popover survived pinning")
        model.presentation.edit(.annotate)
        panel?.editing = true; panel?.ignoresMouseEvents = false
        refresh()
        panel?.makeKeyAndOrderFront(nil)
        print("design-check: native style popover opens, reopens, and closes on selection/tool/pin changes")
    }

    /// Prints the toolbar's hit area against its content width, without triggering layout.
    func designReportToolbar(_ name: String) {
        guard let controls, !controls.isHidden else { return }
        print("design-snapshot \(name): toolbar host \(controls.frame.size), content \(controls.intrinsicContentSize), compact \(model.controlsCompact)")
        if let contextControls {
            print("design-snapshot \(name): context host \(contextControls.frame.size), content \(contextControls.intrinsicContentSize)")
        }
    }


    /// Renders this app's own overlay views over a synthetic backdrop for design review. Nothing on screen is captured.
    func designSnapshot(_ name: String, to directory: URL, configure: (EditorModel) -> Void) {
        configure(model)
        refresh()
        guard let root = panel?.contentView else { return }
        designReportToolbar(name)
        DesignSnapshots.write(root, name: name, to: directory, crop: root.bounds.size, backdrop: true)
        // Focused crops keep controls and hints readable alongside the full viewport.
        DesignSnapshots.write(root, name: name + "-toolbar", to: directory,
            origin: CGPoint(x: max(0, root.bounds.midX - 560), y: 0), crop: CGSize(width: min(1120, root.bounds.width), height: 240), backdrop: true)
        DesignSnapshots.write(root, name: name + "-hints", to: directory,
            origin: CGPoint(x: max(0, root.bounds.midX - 560), y: root.bounds.height - 260), crop: CGSize(width: min(1120, root.bounds.width), height: 260), backdrop: true)
    }
}
#endif

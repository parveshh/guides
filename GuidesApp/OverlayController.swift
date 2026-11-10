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
final class ToolbarHostingView: NSHostingView<OverlayControls> {
    var onIntrinsicSizeChange: (() -> Void)?
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicSizeChange?()
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
    private var layoutRecovery = LayoutLoadRecovery()
    private var panel: OverlayPanel?
    private var canvas: OverlayCanvas?
    private var controls: ToolbarHostingView?
    private var controlsWidthCheckPending = false
    private var readout: NSHostingView<MeasurementReadout>?
    private var previousApplication: NSRunningApplication?
    private var sessions = DisplaySessions()
    private var referencePicker: NSOpenPanel?
    private var controlsWidth: NSLayoutConstraint?
    private var controlsHeight: NSLayoutConstraint?
    private var controlsTop: NSLayoutConstraint?
    private var controlsCenterX: NSLayoutConstraint?

    init(preferences: GuidesPreferences, onInspectImage: @escaping () -> Void, onResizeWindow: @escaping () -> Void,
         onSpacingTokens: @escaping () -> Void, onSavedLayouts: @escaping () -> Void,
         onProjectProfiles: @escaping () -> Void) {
        self.preferences = preferences
        self.onInspectImage = onInspectImage
        self.onResizeWindow = onResizeWindow
        self.onSpacingTokens = onSpacingTokens
        self.onSavedLayouts = onSavedLayouts
        self.onProjectProfiles = onProjectProfiles
        model.reference.onChange = { [weak self] in self?.saveSession(); self?.refresh() }
        model.calibration.setRootPixels(preferences.rootPixels)
        model.rulerAppearance = preferences.rulerAppearance
        model.spacingScale = preferences.spacingScale
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
        // The single-row toolbar needs about 1082 points; narrower displays use a second row.
        model.controlsCompact = usable.width < 1120
        updateControlsWidth()
        controlsHeight?.constant = (model.controlsCompact ? 114 : 70) + (model.isAnnotating ? (model.controlsCompact ? 84 : 44) : 0)
        controlsTop?.constant = usable.minY + 32
        panel?.contentView?.layoutSubtreeIfNeeded()
        if let controls, let canvas { canvas.controlsRect = canvas.convert(controls.bounds, from: controls) }
    }

    /// The toolbar hugs its content, so its hit area and the rect other layout avoids match what is drawn.
    private func updateControlsWidth() {
        guard let width = controlsTargetWidth else { return }
        controlsWidth?.constant = width
    }

    private var controlsTargetWidth: CGFloat? {
        guard let controls, let canvas else { return nil }
        let available = max(240, canvas.usableRect.width - 32)
        let content = ceil(controls.intrinsicContentSize.width)
        return model.controlsCompact || content <= 0 ? available : min(available, max(240, content))
    }

    /// SwiftUI publishes a new ideal size one turn after the model changes, for example when a
    /// display change switches between the one-row and two-row toolbar. Lay out again only if it matters.
    private func controlsContentSizeChanged() {
        guard !controlsWidthCheckPending else { return }
        controlsWidthCheckPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.controlsWidthCheckPending = false
            guard let target = self.controlsTargetWidth, let current = self.controlsWidth?.constant,
                  abs(target - current) >= 1 else { return }
            self.refresh()
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
            onProjectProfiles: onProjectProfiles,
            onTool: { [weak self] tool in
                guard let self else { return }
                self.model.magnifierPresented = false; self.model.magnifier.stop()
                self.canvas?.cancelGesture(); self.model.aligningReference = false
                self.model.presentation.edit(tool); self.refresh()
            },
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
            onAnnotationStyle: { [weak self] style, spotlight, opacity in
                self?.editAnnotations { $0.apply(style: style, spotlight: spotlight, dimOpacity: opacity) }
            },
            onAnnotationDelete: { [weak self] in self?.editAnnotations { $0.deleteSelection() } },
            onAnnotationClear: { [weak self] in self?.editAnnotations { $0.clear() } },
            onUndo: { [weak self] in self?.undo() }, onRedo: { [weak self] in self?.redo() },
            onPin: { [weak self] in self?.pin() }, onHide: { [weak self] in self?.hide() }))
        controls.translatesAutoresizingMaskIntoConstraints = false
        // Reports the content's ideal size for updateControlsWidth; the explicit constraints still decide the frame.
        controls.sizingOptions = [.intrinsicContentSize]
        controls.onIntrinsicSizeChange = { [weak self] in self?.controlsContentSizeChanged() }
        root.addSubview(controls)
        controlsWidth = controls.widthAnchor.constraint(equalToConstant: 1000)
        controlsHeight = controls.heightAnchor.constraint(equalToConstant: 70)
        controlsTop = controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 40)
        controlsCenterX = controls.centerXAnchor.constraint(equalTo: root.centerXAnchor)
        NSLayoutConstraint.activate([
            controlsCenterX!,
            controlsTop!, controlsWidth!, controlsHeight!
        ])
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
        updateControlsWidth()
        controlsHeight?.constant = (model.controlsCompact ? 114 : 70) + (model.isAnnotating ? (model.controlsCompact ? 84 : 44) : 0)
        if let canvas, let root = panel?.contentView, !model.annotations.isDragging {
            let height = controlsHeight?.constant ?? 70, width = controlsWidth?.constant ?? 1000
            let preferred = CGRect(x: canvas.usableRect.midX - width / 2, y: canvas.usableRect.minY + 32, width: width, height: height)
            let frame = AnnotationGeometry.toolbarFrame(preferred: preferred, usable: canvas.usableRect,
                spotlight: model.annotations.document.spotlight)
            controlsTop?.constant = frame.minY
            controlsCenterX?.constant = frame.midX - root.bounds.midX
        }
        panel?.contentView?.layoutSubtreeIfNeeded()
        if let controls, let canvas { canvas.controlsRect = canvas.convert(controls.bounds, from: controls) }
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
    /// Prints the toolbar's hit area against its content width, without triggering layout.
    func designReportToolbar(_ name: String) {
        guard let controls, !controls.isHidden else { return }
        print("design-snapshot \(name): toolbar host \(controls.frame.width) pt, content \(controls.intrinsicContentSize.width) pt, compact \(model.controlsCompact)")
    }


    /// Renders this app's own overlay views over a synthetic backdrop for design review. Nothing on screen is captured.
    func designSnapshot(_ name: String, to directory: URL, configure: (EditorModel) -> Void) {
        configure(model)
        refresh()
        guard let root = panel?.contentView else { return }
        designReportToolbar(name)
        DesignSnapshots.write(root, name: name, to: directory, crop: CGSize(width: 1320, height: 760), backdrop: true)
        // The toolbar and hint bar are centred on the display, outside the top-left crop.
        DesignSnapshots.write(root, name: name + "-toolbar", to: directory,
            origin: CGPoint(x: root.bounds.midX - 560, y: 0), crop: CGSize(width: 1120, height: 240), backdrop: true)
        DesignSnapshots.write(root, name: name + "-hints", to: directory,
            origin: CGPoint(x: root.bounds.midX - 560, y: root.bounds.height - 260), crop: CGSize(width: 1120, height: 260), backdrop: true)
    }
}
#endif

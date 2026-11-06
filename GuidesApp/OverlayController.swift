import AppKit
import GuidesCore
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
    var calibration = Calibration()
    var unit: MeasurementUnit = .screenPoints
    var backingFactor: CGFloat = 1
    var controlsCompact = false
    var displayID: UInt32?
    var rulerAppearance: RulerAppearance = .solid
    var spacingScale: SpacingScale = .empty
    let reference = ReferenceOverlayModel()
    var aligningReference = false
    var canUndo: Bool { aligningReference ? reference.overlay?.canUndo == true : history.canUndo }
    var canRedo: Bool { aligningReference ? reference.overlay?.canRedo == true : history.canRedo }
    var grid = GridConfiguration()
    var gridGeometry: GridGeometry?
    var gridStatus = ""
    var spacingDistance: CGFloat? {
        if document.isAreaSelected, let rect = document.area?.rect {
            switch areaDimension {
            case .width: return rect.width
            case .height: return rect.height
            case .both: return nil
            }
        }
        return document.selectedGap?.distance
    }
    var spacingMatch: SpacingMatch? {
        spacingDistance.flatMap { spacingScale.match(screenDistance: $0, calibration: calibration) }
    }
    var spacingHint: String {
        if !calibration.isConfirmed { return "Set scale to compare spacing tokens." }
        if document.isAreaSelected && areaDimension == .both { return "Select Width or Height to compare tokens." }
        return "This measurement cannot be compared."
    }
    var copyText: String? {
        if document.isAreaSelected, let rect = document.area?.rect, rect.width > 0, rect.height > 0 {
            return MeasurementEngine.areaText(rect, dimension: areaDimension, unit: unit,
                calibration: calibration, backingFactor: backingFactor)
        }
        return document.selectedGap.flatMap { MeasurementEngine.text($0.distance, unit: unit,
            calibration: calibration, backingFactor: backingFactor) }
    }
    var canCopy: Bool { copyText != nil }
    var selectedText: String { copyText ?? "Select a measurement" }
    var contextText: String {
        if !unit.requiresCalibration { return "Manual · \(unit.rawValue)" }
        return "Manual · \(MeasurementText.number(calibration.pointsPerPixel * 100))% scale · \(MeasurementText.number(calibration.rootPixels))px/rem"
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

@MainActor
final class OverlayController {
    let model = EditorModel()
    private let preferences: GuidesPreferences
    private let onInspectImage: () -> Void
    private let onResizeWindow: () -> Void
    private let onSpacingTokens: () -> Void
    private var panel: OverlayPanel?
    private var canvas: OverlayCanvas?
    private var controls: NSHostingView<OverlayControls>?
    private var readout: NSHostingView<MeasurementReadout>?
    private var previousApplication: NSRunningApplication?
    private var sessions = DisplaySessions()
    private var referencePicker: NSOpenPanel?
    private var controlsWidth: NSLayoutConstraint?
    private var controlsHeight: NSLayoutConstraint?
    private var controlsTop: NSLayoutConstraint?

    init(preferences: GuidesPreferences, onInspectImage: @escaping () -> Void, onResizeWindow: @escaping () -> Void,
         onSpacingTokens: @escaping () -> Void) {
        self.preferences = preferences
        self.onInspectImage = onInspectImage
        self.onResizeWindow = onResizeWindow
        self.onSpacingTokens = onSpacingTokens
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

    func edit(_ tool: MeasurementTool) {
        cancelReferenceImport()
        canvas?.cancelGesture()
        saveSession()
        sessions.synchronize(NSScreen.screens.compactMap(\.guidesConfiguration))
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main, let configuration = screen.guidesConfiguration,
              let session = sessions.activate(configuration.id, rootPixels: preferences.rootPixels) else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
        }
        model.presentation.edit(tool)
        model.document = session.document
        model.history = session.history
        model.calibration = session.calibration
        model.unit = session.unit
        model.areaDimension = session.areaDimension
        model.grid = session.grid
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

    func toggleEditing() {
        if model.presentation.mode == .editing { pin() }
        else { edit(model.presentation.tool) }
    }

    func pin() {
        cancelReferenceImport()
        canvas?.cancelGesture()
        model.aligningReference = false
        model.presentation.pin()
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
        cancelReferenceImport()
        canvas?.cancelGesture()
        saveSession()
        let activeID = sessions.activeID
        let invalidated = sessions.synchronize(NSScreen.screens.compactMap(\.guidesConfiguration))
        if let activeID, invalidated.contains(activeID) {
            hide()
            model.document = MeasurementDocument(size: .zero)
            model.history = DocumentHistory()
            model.calibration = Calibration(rootPixels: preferences.rootPixels)
            model.unit = .screenPoints
            model.grid = GridConfiguration()
            model.reference.restore(nil)
            model.displayID = nil
        } else if let activeID, let screen = NSScreen.screens.first(where: { $0.guidesConfiguration?.id == activeID }) {
            configureLayout(screen)
        }
        refresh()
    }

    private func saveSession() {
        var session = DisplaySession(size: model.document.size, rootPixels: preferences.rootPixels)
        session.document = model.document
        session.history = model.history
        session.calibration = model.calibration
        session.unit = model.unit
        session.areaDimension = model.areaDimension
        session.grid = model.grid
        session.reference = model.reference.overlay
        sessions.save(session)
    }

    private func configureLayout(_ screen: NSScreen) {
        panel?.setFrame(screen.frame, display: true)
        let usable = DisplayGeometry(frame: screen.frame).localRect(fromGlobal: screen.visibleFrame)
        canvas?.usableRect = usable
        model.backingFactor = screen.guidesConfiguration?.backingFactor ?? 1
        model.controlsCompact = usable.width < 900
        controlsWidth?.constant = max(240, min(900, usable.width - 32))
        controlsHeight?.constant = model.controlsCompact ? 106 : 66
        controlsTop?.constant = usable.minY + 32
        panel?.contentView?.layoutSubtreeIfNeeded()
        if let controls, let canvas { canvas.controlsRect = canvas.convert(controls.bounds, from: controls) }
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
        let controls = NSHostingView(rootView: OverlayControls(model: model,
            onRulerAppearance: { [weak self] in self?.preferences.setRulerAppearance($0) },
            onInspectImage: onInspectImage, onResizeWindow: onResizeWindow, onSpacingTokens: onSpacingTokens,
            onTool: { [weak self] tool in self?.canvas?.cancelGesture(); self?.model.aligningReference = false; self?.model.presentation.edit(tool); self?.refresh() },
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
            onUndo: { [weak self] in self?.undo() }, onRedo: { [weak self] in self?.redo() },
            onPin: { [weak self] in self?.pin() }, onHide: { [weak self] in self?.hide() }))
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.sizingOptions = []
        root.addSubview(controls)
        controlsWidth = controls.widthAnchor.constraint(equalToConstant: 900)
        controlsHeight = controls.heightAnchor.constraint(equalToConstant: 66)
        controlsTop = controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 40)
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            controlsTop!, controlsWidth!, controlsHeight!
        ])
        let readout = NSHostingView(rootView: MeasurementReadout(model: model,
            onDimension: { [weak self] dimension in self?.model.areaDimension = dimension; self?.refresh() },
            onCopy: { [weak self] in self?.copySelection() },
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
        else if let document = model.history.undo(current: model.document) { model.document = document }
        refresh()
    }

    private func redo() {
        canvas?.cancelGesture()
        if model.aligningReference { model.reference.overlay?.redo() }
        else if let document = model.history.redo(current: model.document) { model.document = document }
        refresh()
    }

    private func copySelection() {
        guard let text = model.copyText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyVariable() {
        guard let text = model.spacingMatch?.copyReference else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
        canvas?.refreshReferenceImage()
        positionReadout()
        canvas?.updateAccessibility()
        canvas?.needsDisplay = true
    }

    private func positionReadout() {
        guard let canvas, let readout, let root = panel?.contentView else { return }
        guard model.presentation.mode == .editing, !model.aligningReference, model.canCopy else {
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
        let valueWidth = (model.selectedText as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 16, weight: .semibold)]).width
        let contextWidth = (model.contextText as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
        let hasTokens = !model.spacingScale.tokens.isEmpty
        let size = CGSize(width: min(460, max(hasTokens ? 420 : 300, max(valueWidth, contextWidth) + 140)),
            height: (area == nil ? 76 : 115) + (hasTokens ? 100 : 0))
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

import AppKit
import GuidesCore
import Observation
import SwiftUI

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
    private var panel: OverlayPanel?
    private var canvas: OverlayCanvas?
    private var controls: NSHostingView<OverlayControls>?
    private var previousApplication: NSRunningApplication?

    init(preferences: GuidesPreferences) {
        self.preferences = preferences
        model.calibration.setRootPixels(preferences.rootPixels)
        preferences.onRootChange = { [weak self] value in
            self?.model.calibration.setRootPixels(value)
            self?.refresh()
        }
    }

    func edit(_ tool: MeasurementTool) {
        canvas?.cancelGesture()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
        }
        model.presentation.edit(tool)
        if panel == nil { createPanel(screen: screen) }
        if model.document.size != screen.frame.size {
            model.document = MeasurementDocument(size: screen.frame.size)
            model.history = DocumentHistory()
            model.calibration = Calibration(rootPixels: preferences.rootPixels)
            model.unit = .screenPoints
        }
        panel?.setFrame(screen.frame, display: true)
        canvas?.usableRect = DisplayGeometry(frame: screen.frame).localRect(fromGlobal: screen.visibleFrame)
        model.backingFactor = screen.convertRectToBacking(CGRect(origin: screen.frame.origin, size: CGSize(width: 1, height: 1))).width
        panel?.editing = true
        panel?.ignoresMouseEvents = false
        refresh()
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeFirstResponder(canvas)
    }

    func pin() {
        canvas?.cancelGesture()
        model.presentation.pin()
        panel?.orderOut(nil)
        panel?.editing = false
        panel?.ignoresMouseEvents = true
        refresh()
        panel?.orderFrontRegardless()
        restoreFocusIfNeeded()
    }

    func hide() {
        canvas?.cancelGesture()
        model.presentation.hide()
        panel?.editing = false
        panel?.orderOut(nil)
        restoreFocusIfNeeded()
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
            onTool: { [weak self] tool in self?.canvas?.cancelGesture(); self?.model.presentation.edit(tool); self?.refresh() },
            onCopy: { [weak self] in self?.copySelection() },
            onUnit: { [weak self] unit in self?.model.unit = unit; self?.refresh() },
            onCalibration: { [weak self] calibration in
                self?.model.calibration = calibration
                self?.preferences.setRootPixels(calibration.rootPixels)
                self?.refresh()
            },
            onUndo: { [weak self] in self?.undo() }, onRedo: { [weak self] in self?.redo() },
            onPin: { [weak self] in self?.pin() }, onHide: { [weak self] in self?.hide() }))
        controls.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 62),
            controls.widthAnchor.constraint(equalToConstant: 780),
            controls.heightAnchor.constraint(equalToConstant: 104)
        ])
        panel.contentView = root
        self.panel = panel
        self.canvas = canvas
        self.controls = controls
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
        if let document = model.history.undo(current: model.document) { model.document = document }
        refresh()
    }

    private func redo() {
        canvas?.cancelGesture()
        if let document = model.history.redo(current: model.document) { model.document = document }
        refresh()
    }

    private func copySelection() {
        guard let text = model.copyText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func refresh() {
        controls?.isHidden = model.presentation.mode != .editing
        canvas?.needsDisplay = true
    }
}

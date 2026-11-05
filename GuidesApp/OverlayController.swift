import AppKit
import GuidesCore
import Observation
import SwiftUI

@MainActor
@Observable
final class EditorModel {
    var presentation = Presentation()
    var document = GuideDocument(size: .zero)
    var selectedText: String {
        document.selectedGap.map { MeasurementText.screenPoints($0.distance) } ?? "Select a distance"
    }
}

@MainActor
final class OverlayPanel: NSPanel {
    var editing = false
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { editing }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if editing, event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class OverlayController {
    let model = EditorModel()
    private var panel: OverlayPanel?
    private var canvas: OverlayCanvas?
    private var controls: NSHostingView<OverlayControls>?
    private var previousApplication: NSRunningApplication?

    func edit(_ tool: MeasurementTool) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
        }
        model.presentation.edit(tool)
        if panel == nil { createPanel(screen: screen) }
        if model.document.size != screen.frame.size {
            model.document = GuideDocument(size: screen.frame.size)
        }
        panel?.setFrame(screen.frame, display: true)
        canvas?.usableRect = DisplayGeometry(frame: screen.frame).localRect(fromGlobal: screen.visibleFrame)
        panel?.editing = true
        panel?.ignoresMouseEvents = false
        refresh()
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeFirstResponder(canvas)
    }

    func pin() {
        model.presentation.pin()
        panel?.orderOut(nil)
        panel?.editing = false
        panel?.ignoresMouseEvents = true
        refresh()
        panel?.orderFrontRegardless()
        restoreFocusIfNeeded()
    }

    func hide() {
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
        root.addSubview(canvas)
        let controls = NSHostingView(rootView: OverlayControls(model: model,
            onTool: { [weak self] tool in self?.model.presentation.edit(tool); self?.refresh() },
            onCopy: { [weak self] in self?.copySelection() },
            onPin: { [weak self] in self?.pin() }, onHide: { [weak self] in self?.hide() }))
        controls.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 62),
            controls.widthAnchor.constraint(equalToConstant: 740),
            controls.heightAnchor.constraint(equalToConstant: 60)
        ])
        panel.contentView = root
        self.panel = panel
        self.canvas = canvas
        self.controls = controls
    }

    private func copySelection() {
        guard model.document.selectedGap != nil else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.selectedText, forType: .string)
    }

    private func refresh() {
        controls?.isHidden = model.presentation.mode != .editing
        canvas?.needsDisplay = true
    }
}

private struct OverlayControls: View {
    var model: EditorModel
    var onTool: (MeasurementTool) -> Void
    var onCopy: () -> Void
    var onPin: () -> Void
    var onHide: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "ruler").foregroundStyle(.cyan)
            Picker("Tool", selection: Binding(get: { model.presentation.tool }, set: { onTool($0) })) {
                ForEach(MeasurementTool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width: 150)
            Text("Screen pt").font(.caption).foregroundStyle(.secondary)
            Text(model.selectedText).font(.system(.caption, design: .monospaced))
                .lineLimit(1).frame(minWidth: 110)
            Button("Copy", action: onCopy).disabled(model.document.selectedGap == nil)
            Spacer()
            Button("Pin", systemImage: "pin", action: onPin)
            Button("Hide", systemImage: "xmark", action: onHide)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.25)))
        .padding(2)
    }
}

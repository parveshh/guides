import AppKit
import GuidesCore
import Observation
import SwiftUI

@MainActor
@Observable
final class EditorModel {
    var presentation = Presentation()
    var status = "Pull a guide from a ruler"
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
        panel?.setFrame(screen.frame, display: true)
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
        panel.onEscape = { [weak canvas] in canvas?.onEscape?() }
        root.addSubview(canvas)
        let controls = NSHostingView(rootView: OverlayControls(model: model,
            onTool: { [weak self] tool in self?.model.presentation.edit(tool); self?.refresh() },
            onPin: { [weak self] in self?.pin() }, onHide: { [weak self] in self?.hide() }))
        controls.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 62),
            controls.widthAnchor.constraint(equalToConstant: 510),
            controls.heightAnchor.constraint(equalToConstant: 60)
        ])
        panel.contentView = root
        self.panel = panel
        self.canvas = canvas
        self.controls = controls
    }

    private func refresh() {
        controls?.isHidden = model.presentation.mode != .editing
        canvas?.needsDisplay = true
    }
}

private struct OverlayControls: View {
    var model: EditorModel
    var onTool: (MeasurementTool) -> Void
    var onPin: () -> Void
    var onHide: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "ruler").foregroundStyle(.cyan)
            Picker("Tool", selection: Binding(get: { model.presentation.tool }, set: { onTool($0) })) {
                ForEach(MeasurementTool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width: 150)
            Text("Screen pt").font(.caption).foregroundStyle(.secondary)
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

@MainActor
final class OverlayCanvas: NSView {
    var model: EditorModel!
    var onEscape: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard model.presentation.mode != .hidden else { return }
        let text = model.presentation.mode == .pinned ? "Guides pinned · Use Edit Guides to resume" : "Guides · Editing"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                        .foregroundColor: NSColor.white]
        let label = text as NSString
        let size = label.size(withAttributes: attributes)
        let rect = NSRect(x: 24, y: bounds.height - 70, width: size.width + 24, height: 30)
        NSColor.black.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        label.draw(at: NSPoint(x: rect.minX + 12, y: rect.minY + 7), withAttributes: attributes)
    }
}

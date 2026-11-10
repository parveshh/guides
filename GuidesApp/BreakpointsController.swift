import AppKit
import GuidesCore
import SwiftUI

@MainActor
final class BreakpointsController {
    private var window: NSWindow?

    func show(preferences: GuidesPreferences) {
        if let window, window.isVisible {
            NSApp.activate(); window.makeKeyAndOrderFront(nil)
            return
        }
        let window = BreakpointsWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Guides Breakpoints"
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: BreakpointsView(breakpoints: preferences.breakpoints,
            save: { [weak window] set in preferences.setBreakpoints(set); window?.close() },
            cancel: { [weak window] in window?.close() }))
        view.sizingOptions = []
        window.contentView = view
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}

/// The accessory app has no Edit menu to supply these responder commands.
private final class BreakpointsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" { performClose(nil); return true }
        if TextEditingCommands.handle(event, responder: firstResponder) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

private struct BreakpointsView: View {
    @State private var source: String
    @State private var error: String?
    let save: (BreakpointSet) -> Void
    let cancel: () -> Void

    init(breakpoints: BreakpointSet, save: @escaping (BreakpointSet) -> Void, cancel: @escaping () -> Void) {
        _source = State(initialValue: breakpoints.source)
        self.save = save; self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolHeader(symbol: "arrow.left.and.right", title: "Breakpoints",
                subtitle: "Mark your own breakpoint widths on the top ruler and offer them as window widths.")
            ToolCard("Widths") {
                Text("One breakpoint per line, for example: md: 768px").font(.callout)
                TextEditor(text: $source)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                    .accessibilityLabel("Breakpoint widths")
                    .frame(minHeight: 140)
                HStack {
                    Button("Use Example") { source = BreakpointSet.example; error = nil }
                        .help("Tailwind’s default breakpoints, written in px")
                    Button("Clear Draft") { source = ""; error = nil }
                    Spacer()
                    Text("Up to 16 breakpoints · px values only").font(.caption).foregroundStyle(.secondary)
                }
                Text("Enter rem breakpoints as px: media queries use the browser’s default font size, so 48rem is normally 768px.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            ToolNote("Markers are measured from the display’s left edge at the scale you set, and appear only after Set scale. They are your own values, not breakpoints read from a page, and Guides does not know where a browser’s viewport starts. Saved on this Mac.")
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Breakpoints", action: apply).keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }.toolWindow()
    }

    private func apply() {
        do { save(try BreakpointSet(source: source)) }
        catch { self.error = error.localizedDescription }
    }
}

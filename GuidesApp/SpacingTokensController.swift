import AppKit
import GuidesCore
import SwiftUI

@MainActor
final class SpacingTokensController {
    private var window: NSWindow?

    func show(preferences: GuidesPreferences) {
        if let window, window.isVisible {
            NSApp.activate(); window.makeKeyAndOrderFront(nil)
            return
        }
        let window = SpacingTokensWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 570),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Guides Spacing Tokens"
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: SpacingTokensView(scale: preferences.spacingScale,
            save: { [weak window] scale in preferences.setSpacingScale(scale); window?.close() },
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
private final class SpacingTokensWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command, key == "w" { performClose(nil); return true }
        if TextEditingCommands.handle(event, responder: firstResponder) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

private struct SpacingTokensView: View {
    @State private var source: String
    @State private var tolerance: String
    @State private var error: String?
    let save: (SpacingScale) -> Void
    let cancel: () -> Void

    init(scale: SpacingScale, save: @escaping (SpacingScale) -> Void, cancel: @escaping () -> Void) {
        _source = State(initialValue: scale.source)
        _tolerance = State(initialValue: scale.toleranceText)
        self.save = save; self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spacing tokens").font(.title2.bold())
            Text("Compare manual, calibrated measurements with your own spacing scale. These are suggestions, not inspected CSS properties.")
                .font(.callout).foregroundStyle(.secondary)
            Text("One token per line, for example: --space-2: 8px;").font(.callout)
            TextEditor(text: $source)
                .font(.system(.body, design: .monospaced))
                .border(.secondary.opacity(0.4))
                .accessibilityLabel("Spacing token declarations")
                .frame(minHeight: 140)
            HStack {
                Button("Use Example") { source = SpacingScale.example; error = nil }
                Button("Clear Draft") { source = ""; error = nil }
                Spacer()
                Text("Up to 64 tokens · px values only").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Match tolerance (design px)")
                TextField("Tolerance", text: $tolerance).textFieldStyle(.roundedBorder).frame(width: 80)
                    .accessibilityLabel("Match tolerance in design pixels")
            }
            Text("0 requires an exact match; maximum 100. Equal nearest matches are ambiguous. Copy Variable is available only for a unique match within tolerance. The scale is saved on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Scale", action: apply).keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }.padding(20)
    }

    private func apply() {
        do { save(try SpacingScale(source: source, tolerance: tolerance)) }
        catch { self.error = error.localizedDescription }
    }
}

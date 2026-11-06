import AppKit
import GuidesCore
import SwiftUI

@MainActor
final class SavedLayoutsController {
    private var window: NSWindow?
    private let store = SavedLayoutsStore(fileURL: URL.applicationSupportDirectory
        .appendingPathComponent("Guides", isDirectory: true).appendingPathComponent("layouts.json"))

    func show(overlay: OverlayController) {
        guard let target = overlay.prepareSavedLayouts() else { return }
        // Reopening binds a new window to the intended display, even if an older manager is open.
        window?.close()
        let window = SavedLayoutsWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 650),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Guides Saved Layouts"
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: SavedLayoutsView(store: store, target: target,
            capture: { try overlay.captureLayout(on: target) },
            load: { [weak window] content in try overlay.loadLayout(content, on: target); window?.close() },
            canUndoLoad: { overlay.canUndoLayoutLoad(on: target) },
            undoLoad: { [weak window] in try overlay.undoLayoutLoad(on: target); window?.close() },
            close: { [weak window] in window?.close() }))
        view.sizingOptions = []
        window.contentView = view
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private final class SavedLayoutsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" { performClose(nil); return true }
        if TextEditingCommands.handle(event, responder: firstResponder) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

private struct SavedLayoutsView: View {
    var store: SavedLayoutsStore
    let target: DisplayConfiguration
    let capture: () throws -> SavedLayoutContent
    let load: (SavedLayoutContent) throws -> Void
    let canUndoLoad: () -> Bool
    let undoLoad: () throws -> Void
    let close: () -> Void
    @State private var name = ""
    @State private var selectedID: UUID?
    @State private var rename = ""
    @State private var error: String?
    private var selected: SavedLayout? { store.layouts.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved layouts").font(.title2.bold())
            Text("This display: \(MeasurementText.number(target.size.width)) × \(MeasurementText.number(target.size.height)) screen pt · \(MeasurementText.number(target.backingFactor))× backing")
                .font(.callout)
            Text("Save guides, Area, grid and annotations on this Mac. Loading replaces this display’s setup and requires Set scale again. Reference images and preferences stay as they are. Nothing loads automatically at launch.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("New layout name", text: $name).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("New layout name")
                Button("Save Current") { perform { selectedID = try store.save(name: name, content: capture()); name = "" } }
                    .disabled(store.storageError != nil)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if store.layouts.isEmpty { Text("No saved layouts yet.").foregroundStyle(.secondary).padding() }
                    ForEach(store.layouts) { layout in
                        Button { selectedID = layout.id } label: {
                            HStack(alignment: .top) {
                                Image(systemName: selectedID == layout.id ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(layout.name).fontWeight(.semibold)
                                    Text(layout.content.summary).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedID == layout.id ? Color.accentColor.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Select layout \(layout.name)")
                            .accessibilityValue(layout.content.summary)
                            .accessibilityAddTraits(selectedID == layout.id ? [.isSelected] : [])
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).border(.secondary.opacity(0.25))
            HStack {
                TextField("Selected layout name", text: $rename).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Selected layout name")
                Button("Rename") { if let selectedID { perform { try store.rename(selectedID, to: rename) } } }
                Button("Delete") { if let selectedID { perform { try store.delete(selectedID); self.selectedID = nil } } }
            }.disabled(selected == nil || store.storageError != nil)
            HStack {
                Button("Undo Delete") { perform { selectedID = try store.undoDelete() } }.disabled(!store.canUndoDelete)
                Spacer()
                Button("Load Layout") { if let selected { perform { try load(selected.content) } } }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected?.content.isCompatible(with: target) != true || store.storageError != nil)
            }
            if let selected, !selected.content.isCompatible(with: target) {
                Text("Load requires the saved screen-point size and backing factor. Layouts are never scaled to fit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let storageError = store.storageError {
                HStack(alignment: .top) {
                    Text(storageError).font(.caption).foregroundStyle(.red)
                    Button("Retry") { store.reload(); error = nil; selectedID = nil }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Button("Undo Layout Load") { perform { try undoLoad() } }.disabled(!canUndoLoad())
                    .help("Replace the current setup with the setup before the latest load, including its calibration and tool history.")
                Spacer()
                Button("Close", action: close).keyboardShortcut(.cancelAction)
            }
        }.padding(20)
            .onChange(of: selectedID) { _, _ in rename = selected?.name ?? ""; error = nil }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

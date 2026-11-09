import AppKit
import GuidesCore
import SwiftUI

@MainActor
final class ProjectProfilesController {
    private var window: NSWindow?
    private let store = ProjectProfilesStore(fileURL: URL.applicationSupportDirectory
        .appendingPathComponent("Guides", isDirectory: true).appendingPathComponent("profiles.json"))

    func show(preferences: GuidesPreferences) {
        if let window, window.isVisible {
            NSApp.activate(); window.makeKeyAndOrderFront(nil)
            return
        }
        let window = ProjectProfilesWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Guides Project Profiles"
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: ProjectProfilesView(store: store, preferences: preferences,
            close: { [weak window] in window?.close() }))
        view.sizingOptions = []
        window.contentView = view
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}

private final class ProjectProfilesWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" { performClose(nil); return true }
        if TextEditingCommands.handle(event, responder: firstResponder) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

private struct ProjectProfilesView: View {
    var store: ProjectProfilesStore
    var preferences: GuidesPreferences
    let close: () -> Void
    @State private var name = ""
    @State private var selectedID: UUID?
    @State private var rename = ""
    @State private var error: String?
    private var selected: ProjectProfile? { store.profiles.first { $0.id == selectedID } }
    private var current: ProjectProfileContent? { try? ProjectProfileContent(preferences: preferences) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ToolHeader(symbol: "folder", title: "Project profiles",
                subtitle: "Save the rem base and spacing tokens for a project, then apply them when you switch projects.")
            ToolCard("Current settings") {
                Text(current?.summary ?? "unavailable").font(.callout.monospacedDigit())
                HStack {
                    TextField("New profile name", text: $name).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("New profile name")
                    Button("Save Current") {
                        perform {
                            selectedID = try store.save(name: name, content: ProjectProfileContent(preferences: preferences))
                            name = ""
                        }
                    }.disabled(store.storageError != nil)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if store.profiles.isEmpty {
                        ToolEmptyState(symbol: "folder.badge.plus", title: "No project profiles yet",
                            message: "Name the current settings above, then choose Save Current.")
                    }
                    ForEach(store.profiles) { profile in
                        let summary = profile.content.summary + (profile.content == current ? " · matches current settings" : "")
                        Button { selectedID = profile.id } label: {
                            ToolListRow(title: profile.name, detail: summary, selected: selectedID == profile.id)
                        }.buttonStyle(.plain).accessibilityLabel("Select profile \(profile.name)")
                            .accessibilityValue(summary)
                            .accessibilityAddTraits(selectedID == profile.id ? [.isSelected] : [])
                    }
                }.padding(6)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                TextField("Selected profile name", text: $rename).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Selected profile name")
                Button("Rename") { if let selectedID { perform { try store.rename(selectedID, to: rename) } } }
                Button("Delete") { if let selectedID { perform { try store.delete(selectedID); self.selectedID = nil } } }
                Button("Apply Profile") { if let selectedID { perform { try store.apply(selectedID, to: preferences) } } }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected?.content == current)
            }.disabled(selected == nil || store.storageError != nil)
            if let storageError = store.storageError {
                HStack(alignment: .top) {
                    Text(storageError).font(.caption).foregroundStyle(.red)
                    Button("Retry") { store.reload(); error = nil; selectedID = nil }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            ToolNote("Applying replaces both current settings. Measurements, calibration and saved layouts stay as they are. Profiles stay on this Mac and nothing applies automatically.")
            Divider()
            HStack {
                Button("Undo Delete") { perform { selectedID = try store.undoDelete() } }.disabled(!store.canUndoDelete)
                Button("Undo Apply") { perform { try store.undoApply(to: preferences) } }.disabled(!store.canUndoApply)
                    .help("Restore the rem base and spacing tokens from before the latest apply, replacing any edits made to them since.")
                Spacer()
                Button("Close", action: close).keyboardShortcut(.cancelAction)
            }
        }.toolWindow()
            .onChange(of: selectedID) { _, _ in rename = selected?.name ?? ""; error = nil }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

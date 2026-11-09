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
        let window = ProjectProfilesWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Project profiles").font(.title2.bold())
            Text("Current settings: \(current?.summary ?? "unavailable")").font(.callout)
            Text("Save the rem base and spacing tokens for a project on this Mac, then apply them when you switch projects. Applying replaces both current settings. Measurements, calibration and saved layouts stay as they are. Nothing applies automatically.")
                .font(.callout).foregroundStyle(.secondary)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if store.profiles.isEmpty { Text("No project profiles yet.").foregroundStyle(.secondary).padding() }
                    ForEach(store.profiles) { profile in
                        let summary = profile.content.summary + (profile.content == current ? " · matches current settings" : "")
                        Button { selectedID = profile.id } label: {
                            HStack(alignment: .top) {
                                Image(systemName: selectedID == profile.id ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.name).fontWeight(.semibold)
                                    Text(summary).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedID == profile.id ? Color.accentColor.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Select profile \(profile.name)")
                            .accessibilityValue(summary)
                            .accessibilityAddTraits(selectedID == profile.id ? [.isSelected] : [])
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).border(.secondary.opacity(0.25))
            HStack {
                TextField("Selected profile name", text: $rename).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Selected profile name")
                Button("Rename") { if let selectedID { perform { try store.rename(selectedID, to: rename) } } }
                Button("Delete") { if let selectedID { perform { try store.delete(selectedID); self.selectedID = nil } } }
            }.disabled(selected == nil || store.storageError != nil)
            HStack {
                Button("Undo Delete") { perform { selectedID = try store.undoDelete() } }.disabled(!store.canUndoDelete)
                Spacer()
                Button("Apply Profile") { if let selectedID { perform { try store.apply(selectedID, to: preferences) } } }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil || selected?.content == current)
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
                Button("Undo Apply") { perform { try store.undoApply(to: preferences) } }.disabled(!store.canUndoApply)
                    .help("Restore the rem base and spacing tokens from before the latest apply, replacing any edits made to them since.")
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

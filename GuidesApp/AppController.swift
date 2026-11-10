import AppKit
import GuidesCore
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let editGuides = Self("editGuides", initial: .init(.g, modifiers: [.control, .option]))
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let preferences: GuidesPreferences = {
        PreferenceMigration.importSandboxSettings()
        return GuidesPreferences()
    }()
    private lazy var overlay = OverlayController(preferences: preferences, onInspectImage: { [weak self] in self?.inspectImage() },
        onResizeWindow: { [weak self] in self?.resizeWindow() },
        onSpacingTokens: { [weak self] in self?.editSpacingTokens() },
        onSavedLayouts: { [weak self] in self?.showSavedLayouts() },
        onProjectProfiles: { [weak self] in self?.showProjectProfiles() },
        onBreakpoints: { [weak self] in self?.editBreakpoints() })
    private let imageInspector = ImageInspectorController()
    private let windowResizer = WindowResizeController()
    private let spacingTokens = SpacingTokensController()
    private let savedLayouts = SavedLayoutsController()
    private let projectProfiles = ProjectProfilesController()
    private let breakpoints = BreakpointsController()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        windowResizer.startTracking()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Guides")
        statusItem.button?.toolTip = "Guides — desktop measurements"
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: "Measure"))
        menu.addItem(item("Edit Guides", #selector(editGuides), symbol: "ruler"))
        menu.addItem(item("Measure Area", #selector(measureArea), symbol: "rectangle.dashed"))
        menu.addItem(item("Measure Corner Radius", #selector(measureRadius), symbol: "app.dashed"))
        menu.addItem(item("Annotate", #selector(annotate), symbol: "pencil.line"))
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Tools"))
        menu.addItem(item("Inspect Image…", #selector(inspectImage), symbol: "photo"))
        menu.addItem(item("Resize Window…", #selector(resizeWindow), symbol: "macwindow"))
        menu.addItem(item("Spacing Tokens…", #selector(editSpacingTokens), symbol: "list.bullet.rectangle"))
        menu.addItem(item("Breakpoints…", #selector(editBreakpoints), symbol: "arrow.left.and.right"))
        menu.addItem(item("Saved Layouts…", #selector(showSavedLayouts), symbol: "square.stack"))
        menu.addItem(item("Project Profiles…", #selector(showProjectProfiles), symbol: "folder"))
        menu.addItem(.separator())
        menu.addItem(item("Hide Measurements", #selector(hideMeasurements), symbol: "eye.slash"))
        let clearItem = item("Clear Measurements", #selector(clearMeasurements), symbol: "trash")
        clearItem.isEnabled = true
        menu.addItem(clearItem)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), symbol: "gearshape"))
        menu.addItem(item("Quit Guides", #selector(quit)))
        menu.autoenablesItems = false
        statusItem.menu = menu
        KeyboardShortcuts.onKeyUp(for: .editGuides) { [weak self] in self?.overlay.toggleEditing() }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged),
            name: NSWorkspace.didWakeNotification, object: nil)
        if ProcessInfo.processInfo.arguments.contains("--show-overlay") { editGuides() }
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--design-snapshots"), arguments.indices.contains(index + 1) {
            DesignSnapshots.run(overlay: overlay, directory: URL(fileURLWithPath: arguments[index + 1]), windows: [
                ("6-settings", { [weak self] in self?.showSettings() }),
                ("7-spacing-tokens", { [weak self] in self?.editSpacingTokens() }),
                ("8-project-profiles", { [weak self] in self?.showProjectProfiles() }),
                ("12-breakpoints", { [weak self] in self?.editBreakpoints() }),
                ("9-saved-layouts", { [weak self] in self?.showSavedLayouts() }),
                ("10-resize-window", { [weak self] in self?.resizeWindow() }),
                ("11-inspect-image", { [weak self] in self?.inspectImage() })])
        }
#endif
    }

    private func item(_ title: String, _ action: Selector, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        editGuides()
        return true
    }

    @objc private func editGuides() { overlay.edit(.guides) }
    @objc private func annotate() { overlay.edit(.annotate) }
    @objc private func measureArea() { overlay.edit(.area) }
    @objc private func measureRadius() { overlay.measureRadius() }
    @objc private func inspectImage() {
        overlay.hide()
        imageInspector.show()
    }
    @objc private func resizeWindow() {
        overlay.hide()
        windowResizer.show(breakpoints: preferences.breakpoints)
    }
    @objc private func editSpacingTokens() {
        overlay.hide()
        // One editor at a time owns the spacing scale, so a stale draft cannot overwrite an applied profile.
        projectProfiles.close()
        spacingTokens.show(preferences: preferences)
    }
    @objc private func editBreakpoints() {
        overlay.hide()
        // As with spacing tokens, a stale breakpoint draft must not overwrite an applied profile.
        projectProfiles.close()
        breakpoints.show(preferences: preferences)
    }
    @objc private func showProjectProfiles() {
        overlay.hide()
        spacingTokens.close()
        breakpoints.close()
        projectProfiles.show(preferences: preferences)
    }
    @objc private func hideMeasurements() { overlay.hide() }
    @objc private func showSavedLayouts() { savedLayouts.show(overlay: overlay) }
    @objc private func clearMeasurements() { overlay.clear() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func screensChanged() { overlay.screenParametersChanged() }
    @objc private func willSleep() { overlay.hide() }

    @objc private func showSettings() {
        overlay.hide()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 500),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Guides Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    var preferences: GuidesPreferences
    @State private var rootText = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Edit / Pin Guides", name: .editGuides)
                Text("Press once to edit measurements, and again to pin them and work in other apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Rulers") {
                Picker("Background", selection: Binding(get: { preferences.rulerAppearance }, set: { preferences.setRulerAppearance($0) })) {
                    ForEach(RulerAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text("Transparent removes the ruler background; numbers keep their own dark chips so they stay readable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Units") {
                LabeledContent("Root font size (px)") {
                    HStack {
                        TextField("Root font size (px)", text: $rootText).labelsHidden().frame(width: 90).onSubmit { applyRoot() }
                        Button("Apply", action: applyRoot)
                    }
                }
                Text("Used for rem conversion.").font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            Section {
                Text("Measurements and calibration start fresh when Guides quits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tint(OverlayStyle.accent)
        .frame(width: 460, height: 500)
        .onAppear { rootText = String(Double(preferences.rootPixels)) }
        .onChange(of: preferences.rootPixels) { _, value in rootText = String(Double(value)) }
    }

    private func applyRoot() {
        guard let value = Double(rootText), preferences.setRootPixels(CGFloat(value)) else {
            error = "Enter a positive, finite root font size."
            return
        }
        error = nil
    }
}

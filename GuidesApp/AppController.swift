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
        onProjectProfiles: { [weak self] in self?.showProjectProfiles() })
    private let imageInspector = ImageInspectorController()
    private let windowResizer = WindowResizeController()
    private let spacingTokens = SpacingTokensController()
    private let savedLayouts = SavedLayoutsController()
    private let projectProfiles = ProjectProfilesController()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        windowResizer.startTracking()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Guides")
        statusItem.button?.toolTip = "Guides — desktop measurements"
        let menu = NSMenu()
        menu.addItem(item("Edit Guides", #selector(editGuides)))
        menu.addItem(item("Measure Area", #selector(measureArea)))
        menu.addItem(item("Measure Corner Radius", #selector(measureRadius)))
        menu.addItem(item("Annotate", #selector(annotate)))
        menu.addItem(item("Inspect Image…", #selector(inspectImage)))
        menu.addItem(item("Resize Window…", #selector(resizeWindow)))
        menu.addItem(item("Spacing Tokens…", #selector(editSpacingTokens)))
        menu.addItem(item("Saved Layouts…", #selector(showSavedLayouts)))
        menu.addItem(item("Project Profiles…", #selector(showProjectProfiles)))
        menu.addItem(.separator())
        menu.addItem(item("Hide Measurements", #selector(hideMeasurements)))
        let clearItem = item("Clear Measurements", #selector(clearMeasurements))
        clearItem.isEnabled = true
        menu.addItem(clearItem)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings)))
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
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
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
        windowResizer.show()
    }
    @objc private func editSpacingTokens() {
        overlay.hide()
        // One editor at a time owns the spacing scale, so a stale draft cannot overwrite an applied profile.
        projectProfiles.close()
        spacingTokens.show(preferences: preferences)
    }
    @objc private func showProjectProfiles() {
        overlay.hide()
        spacingTokens.close()
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
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
            KeyboardShortcuts.Recorder("Edit / Pin Guides:", name: .editGuides)
            Picker("Ruler background:", selection: Binding(get: { preferences.rulerAppearance }, set: { preferences.setRulerAppearance($0) })) {
                ForEach(RulerAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Text("Transparent keeps the numbers and ticks visible without a background.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Root font size (px):", text: $rootText).onSubmit { applyRoot() }
            HStack {
                Text("Used for rem conversion.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Apply", action: applyRoot)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Text("Measurements and calibration start fresh when Guides quits.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 420)
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

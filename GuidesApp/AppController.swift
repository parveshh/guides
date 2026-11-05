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
    private let preferences = GuidesPreferences()
    private lazy var overlay = OverlayController(preferences: preferences)
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Guides")
        statusItem.button?.toolTip = "Guides — desktop measurements"
        let menu = NSMenu()
        menu.addItem(item("Edit Guides", #selector(editGuides)))
        menu.addItem(item("Measure Area", #selector(measureArea)))
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
        KeyboardShortcuts.onKeyUp(for: .editGuides) { [weak self] in self?.editGuides() }
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
    @objc private func measureArea() { overlay.edit(.area) }
    @objc private func hideMeasurements() { overlay.hide() }
    @objc private func clearMeasurements() { overlay.clear() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func screensChanged() { overlay.screenParametersChanged() }
    @objc private func willSleep() { overlay.hide() }

    @objc private func showSettings() {
        overlay.hide()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
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
            KeyboardShortcuts.Recorder("Edit Guides:", name: .editGuides)
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

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
    private let overlay = OverlayController()
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

    @objc private func showSettings() {
        overlay.hide()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Guides Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Edit Guides:", name: .editGuides)
            Text("Measure across your desktop. Pin to work underneath.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 380)
    }
}

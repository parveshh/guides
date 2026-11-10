import AppKit
@preconcurrency import ApplicationServices
import GuidesCore
import Observation
import SwiftUI

struct ResizeApplication: Identifiable {
    let id: Int32
    let name: String
}

@MainActor @Observable
final class WindowResizeControls {
    var applications: [ResizeApplication] = []
    var selectedProcess: Int32?
    var hasAccess = false
    var breakpointWidths: [WindowSizePreset] = []
}

@MainActor
final class WindowResizeController: NSObject, NSWindowDelegate {
    private let model = WindowResizeModel(service: WindowResizeService())
    private let controls = WindowResizeControls()
    private var window: NSWindow?
    private var lastApplication: NSRunningApplication?

    func startTracking() {
        remember(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationActivated),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc private func applicationActivated(_ notification: Notification) {
        remember(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
    }

    private func remember(_ application: NSRunningApplication?) {
        guard let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular else { return }
        lastApplication = application
    }

    func show(breakpoints: BreakpointSet) {
        controls.breakpointWidths = WindowSizePreset.widths(for: breakpoints)
        guard !model.isBusy else { window?.makeKeyAndOrderFront(nil); return }
        remember(NSWorkspace.shared.frontmostApplication)
        refreshApplications()
        if let lastApplication, controls.applications.contains(where: { $0.id == lastApplication.processIdentifier }) {
            controls.selectedProcess = lastApplication.processIdentifier
        }
        controls.hasAccess = AXIsProcessTrusted()
        model.clear()
        if controls.hasAccess { capture() }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Guides Window Resize"
            window.isReleasedWhenClosed = false
            window.delegate = self
            let view = NSHostingView(rootView: WindowResizeView(model: model, controls: controls,
                refresh: { [weak self] in self?.refreshApplications() },
                capture: { [weak self] in self?.capture() },
                requestAccess: { [weak self] in self?.requestAccess() },
                checkAccess: { [weak self] in self?.checkAccess() }))
            view.sizingOptions = []
            window.contentView = view
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { model.clear() }

    private func refreshApplications() {
        controls.applications = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
            .map { ResizeApplication(id: $0.processIdentifier, name: $0.localizedName ?? "Application") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if !controls.applications.contains(where: { $0.id == controls.selectedProcess }) {
            controls.selectedProcess = controls.applications.first?.id
            model.clear()
        }
    }

    private func capture() {
        controls.hasAccess = AXIsProcessTrusted()
        guard controls.hasAccess,
              let application = controls.applications.first(where: { $0.id == controls.selectedProcess }) else { return }
        model.capture(processID: application.id, applicationName: application.name)
    }

    private func requestAccess() {
        // Called only from the explicit permission button, never during launch or measurement.
        controls.hasAccess = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    private func checkAccess() {
        controls.hasAccess = AXIsProcessTrusted()
        if !controls.hasAccess { model.clear() }
        else if model.target == nil { capture() }
    }
}

private struct WindowResizeView: View {
    @Bindable var model: WindowResizeModel
    @Bindable var controls: WindowResizeControls
    let refresh: () -> Void
    let capture: () -> Void
    let requestAccess: () -> Void
    let checkAccess: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ToolHeader(symbol: "macwindow", title: "Resize a window",
                    subtitle: "Set the whole window size in macOS screen points, including browser toolbars and borders.")
                if !controls.hasAccess {
                    ToolCard("Accessibility access is optional") {
                        Text("Window resizing needs permission to control other apps. Guides and image inspection work without it. Enable Guides in System Settings → Privacy & Security → Accessibility, then check access.")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Request Accessibility Access", action: requestAccess).buttonStyle(.borderedProminent)
                            Button("Check Access", action: checkAccess)
                        }
                    }
                }
                ToolCard("Window") {
                    HStack {
                        Picker("App", selection: Binding(get: { controls.selectedProcess }, set: { controls.selectedProcess = $0; model.clear() })) {
                            Text("Choose an app").tag(nil as Int32?)
                            ForEach(controls.applications) { app in Text(app.name).tag(Optional(app.id)) }
                        }
                        Button("Refresh Apps", action: refresh)
                    }.disabled(model.isBusy)
                    Button("Use App’s Front Window", action: capture)
                        .disabled(!controls.hasAccess || model.isBusy || controls.selectedProcess == nil)
                    if let target = model.target {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(target.applicationName) · \(target.title)").font(.headline).lineLimit(2).help(target.title)
                            Text(model.frameIsKnown ? "Last read: \(WindowSizeRequest.text(target.frame.size))" : "Actual size unavailable")
                                .font(.body.monospacedDigit())
                        }
                    } else {
                        Text("Choose a window before resizing. Switching apps does not retarget an already selected window.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ToolCard("Size") {
                    HStack(alignment: .bottom, spacing: 12) {
                        dimension("Width", text: $model.width)
                        Text("×").padding(.bottom, 5)
                        dimension("Height", text: $model.height)
                        Menu("Presets") {
                            Section("Device classes") { presets(WindowSizePreset.devices) }
                            Section("Displays") { presets(WindowSizePreset.displays) }
                            if !controls.breakpointWidths.isEmpty {
                                Section("Your breakpoints · width only") { presets(controls.breakpointWidths) }
                            }
                        }.frame(width: 110).padding(.bottom, 2)
                    }.disabled(model.isBusy)
                    Text("Presets fill in the fields; nothing changes until Resize Window. Device classes are common sizes, not named models. A breakpoint preset sets the width only, taking one CSS px as one screen point (browser zoom 100%).")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Resize Window") { model.resize() }.buttonStyle(.borderedProminent)
                            .disabled(!controls.hasAccess || model.target == nil || model.isBusy)
                        Button("Restore Previous Frame") { model.restore() }
                            .disabled(!controls.hasAccess || !model.canRestore || model.isBusy)
                        if model.isBusy { ProgressView().controlSize(.small) }
                    }
                    if let message = model.message { Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                }
                if controls.hasAccess {
                    HStack {
                        Label("Accessibility access enabled", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Check Access", action: checkAccess).controlSize(.small).disabled(model.isBusy)
                    }
                }
                ToolNote("This does not set the page’s CSS viewport or your monitor’s pixel resolution. Apps may enforce minimum sizes or limit windows to the display; Guides reads back the accepted size. For an exact website viewport, use your browser’s responsive design tools.")
            }.toolWindow()
        }
    }

    private func presets(_ items: [WindowSizePreset]) -> some View {
        ForEach(items) { preset in
            Button(preset.title) {
                model.width = String(preset.width)
                if let height = preset.height { model.height = String(height) }
            }
        }
    }

    private func dimension(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title + " (screen pt)").font(.caption)
            TextField(title, text: text).textFieldStyle(.roundedBorder).accessibilityLabel(title + " in screen points")
        }
    }
}

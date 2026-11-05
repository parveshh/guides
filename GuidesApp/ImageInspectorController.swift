import AppKit
import GuidesCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ImageInspectorController: NSObject, NSWindowDelegate {
    private let model = ImageInspectorModel()
    private var window: ImageInspectorWindow?

    func show() {
        if window == nil {
            let panel = ImageInspectorWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            panel.title = "Guides Image Inspector"
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 480, height: 590)
            panel.delegate = self
            panel.openImage = { [weak self] in self?.openImage() }
            panel.pasteImage = { [weak self] in self?.importPasteboard(.general) }
            let view = ImageDropHostingView(rootView: ImageInspectorView(model: model,
                open: { [weak self] in self?.openImage() },
                paste: { [weak self] in self?.importPasteboard(.general) }))
            view.importImage = { [weak self] in self?.importPasteboard($0) }
            view.setDropTarget = { [weak self] in self?.model.isDropTarget = $0 }
            view.sizingOptions = []
            panel.contentView = view
            panel.center()
            window = panel
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { model.clear() }

    private func openImage() {
        guard let window, window.attachedSheet == nil else { return }
        let picker = NSOpenPanel()
        picker.title = "Inspect an Image"
        picker.prompt = "Inspect"
        picker.allowedContentTypes = [.image]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        picker.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = picker.url { self?.model.load(.file(url)) }
        }
    }

    private func importPasteboard(_ pasteboard: NSPasteboard) {
        guard window?.attachedSheet == nil else { return }
        // Finder file copies preserve original metadata; image-only copies use their supplied representation.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            guard urls.count == 1 else { model.rejectImport("Choose one image at a time."); return }
            model.load(.file(urls[0]))
            return
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type) {
                model.load(.clipboard(data))
                return
            }
        }
        model.rejectImport("Copy an image or one image file, then choose Paste Image.")
    }
}

private final class ImageInspectorWindow: NSWindow {
    var openImage: (() -> Void)?
    var pasteImage: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if attachedSheet == nil, event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "o": openImage?(); return true
            case "v": pasteImage?(); return true
            case "w": performClose(nil); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class ImageDropHostingView: NSHostingView<ImageInspectorView> {
    var importImage: ((NSPasteboard) -> Void)?
    var setDropTarget: ((Bool) -> Void)?

    required init(rootView: ImageInspectorView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard window?.attachedSheet == nil,
              sender.draggingSourceOperationMask.contains(.copy) else { return [] }
        setDropTarget?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { setDropTarget?(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDropTarget?(false)
        guard window?.attachedSheet == nil else { return false }
        importImage?(sender.draggingPasteboard)
        return true
    }
}

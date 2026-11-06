import SwiftUI
import GuidesCore

struct ReferenceEditor: View {
    let reference: ReferenceOverlayModel
    let size: CGSize
    let onOpen: () -> Void
    let onApply: (ReferencePlacement) -> Void
    let onAlign: () -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void
    @State private var x = "0"
    @State private var y = "0"
    @State private var width = "0"
    @State private var opacity = 0.5
    @State private var visible = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reference image").font(.headline)
            Button(reference.overlay == nil ? "Open Image…" : "Replace Image…", action: onOpen)
            if reference.isLoading { ProgressView("Loading reference…") }
            if let overlay = reference.overlay {
                Text(overlay.image.metadata.name).lineLimit(1).truncationMode(.middle)
                Text("Source: \(overlay.image.metadata.dimensions) · \(overlay.image.metadata.imageCount > 1 ? "Primary image only · " : "")preview up to 4096 px")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show reference", isOn: $visible)
                Text("Position from display top-left (screen pt)").font(.caption)
                HStack {
                    TextField("X", text: $x).accessibilityLabel("Reference X in screen points")
                    TextField("Y", text: $y).accessibilityLabel("Reference Y in screen points")
                }
                TextField("Width (screen pt)", text: $width).accessibilityLabel("Reference width in screen points")
                Text("Aspect ratio stays fixed. Image sizing does not change measurement scale.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Fit to display") {
                    if let fitted = try? ReferencePlacement.fitted(sourceSize: overlay.sourceSize, displaySize: size) {
                        setFields(fitted)
                    }
                }
                HStack {
                    Text("Opacity \(Int((opacity * 100).rounded()))%")
                    Slider(value: $opacity, in: 0.1...1, step: 0.05).accessibilityLabel("Reference opacity")
                }
                Button("Apply & align on canvas") { apply(align: true) }
                Text("Drag the image or use arrows to align. Shift moves 10 pt; Option moves one backing pixel. Choose Guides or Area to measure again.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Remove Reference", role: .destructive, action: onRemove)
            } else {
                Text("Choose one local image to align over this display. It stays only until Guides quits. Pin & work passes clicks through.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = error ?? reference.error { Text(message).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                if reference.overlay != nil { Button("Apply") { apply(align: false) }.keyboardShortcut(.defaultAction) }
            }
        }
        .padding(20).frame(width: 380).textFieldStyle(.roundedBorder)
        .onAppear { if let placement = reference.overlay?.placement { setFields(placement) } }
    }

    private func setFields(_ placement: ReferencePlacement) {
        x = String(Double(placement.frame.minX)); y = String(Double(placement.frame.minY))
        width = String(Double(placement.frame.width)); opacity = Double(placement.opacity); visible = placement.isVisible
    }
    private func apply(align: Bool) {
        guard let overlay = reference.overlay else { return }
        do {
            guard let x = Double(x), let y = Double(y) else { throw ReferenceError.origin }
            guard let width = Double(width) else { throw ReferenceError.dimensions }
            let placement = try ReferencePlacement(sourceSize: overlay.sourceSize, width: width,
                origin: CGPoint(x: x, y: y), opacity: opacity, isVisible: align || visible, displaySize: size)
            onApply(placement)
            if align { onAlign() }
        } catch { self.error = error.localizedDescription }
    }
}

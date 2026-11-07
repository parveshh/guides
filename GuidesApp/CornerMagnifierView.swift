import SwiftUI
import GuidesCore

struct CornerMagnifierView: View {
    var model: EditorModel
    let onRadius: (CGFloat) -> Void
    let onNudge: (CGFloat, CGFloat) -> Void
    let onOpacity: (CGFloat) -> Void
    @State private var corner: MagnifierCorner = .topLeft
    @State private var zoom: CGFloat = 8
    @State private var hasAccess = CornerCaptureService.hasAccess
    private var request: CornerCaptureRequest? {
        guard let id = model.displayID, let area = model.document.area else { return nil }
        return CornerCaptureRequest(display: DisplayConfiguration(id: id, size: model.document.size, backingFactor: model.backingFactor),
                                    area: area, corner: corner, zoom: zoom)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Corner magnifier").font(.headline)
            Text("Live desktop detail, with Guides excluded. The pink curve is your fitted outline. Images stay in memory.")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack {
                Picker("Corner", selection: $corner) {
                    ForEach(MagnifierCorner.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().accessibilityLabel("Magnified corner")
                Text("Zoom").font(.caption)
                Picker("Zoom", selection: $zoom) {
                    Text("4×").tag(CGFloat(4)); Text("8×").tag(CGFloat(8)); Text("16×").tag(CGFloat(16))
                }.labelsHidden().frame(width: 80).accessibilityLabel("Magnifier zoom in screen points")
            }
            ZStack {
                Color.black
                if let image = model.magnifier.image, let captured = model.magnifier.imageRequest {
                    Image(decorative: image, scale: 1).resizable().interpolation(.none).frame(width: 256, height: 256)
                    if let area = model.document.area {
                        Canvas { context, _ in
                            let path = Path(roundedRect: captured.previewRect(for: area.rect),
                                            cornerRadius: captured.previewRadius(area.cornerRadius))
                            context.stroke(path, with: .color(.pink.opacity(model.radiusOutlineOpacity)), lineWidth: 1)
                        }.frame(width: 256, height: 256)
                    }
                } else {
                    Text(model.magnifier.isRunning ? "Capturing…" : "Preview stopped")
                        .font(.caption).foregroundStyle(.white)
                }
            }.frame(width: 256, height: 256).clipped().frame(maxWidth: .infinity)
                .accessibilityLabel("Live magnified desktop corner")
            if let area = model.document.area {
                HStack {
                    Text("R \(model.text(area.cornerRadius))").font(.system(.caption, design: .monospaced))
                    Spacer()
                    Button("−0.25") { onRadius(max(0, area.cornerRadius - 0.25)) }.accessibilityLabel("Decrease radius by a quarter screen point")
                    Button("+0.25") { onRadius(min(area.maximumRadius, area.cornerRadius + 0.25)) }.accessibilityLabel("Increase radius by a quarter screen point")
                }
                HStack {
                    Text("Move bounds ¼ pt").font(.caption)
                    Spacer()
                    Button("←") { onNudge(-0.25, 0) }.accessibilityLabel("Move bounds left a quarter point")
                    Button("→") { onNudge(0.25, 0) }.accessibilityLabel("Move bounds right a quarter point")
                    Button("↑") { onNudge(0, -0.25) }.accessibilityLabel("Move bounds up a quarter point")
                    Button("↓") { onNudge(0, 0.25) }.accessibilityLabel("Move bounds down a quarter point")
                }
            }
            HStack {
                Text("Border \(Int((model.radiusOutlineOpacity * 100).rounded()))%").font(.caption)
                Slider(value: Binding(get: { model.radiusOutlineOpacity }, set: { onOpacity($0) }), in: 0...1, step: 0.05).accessibilityLabel("Magnified border opacity")
            }
            if !hasAccess {
                Text("Screen Recording access is optional and only needed for the live preview.").font(.caption)
                HStack {
                    Button("Request Screen Recording…") { CornerCaptureService.requestAccess(); hasAccess = CornerCaptureService.hasAccess }
                    Button("Check Access") { hasAccess = CornerCaptureService.hasAccess }
                }
            }
            if let error = model.magnifier.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button(model.magnifier.isRunning ? "Stop Magnifier" : "Start Magnifier") {
                    if model.magnifier.isRunning { model.magnifier.stop() }
                    else if let request { model.magnifier.start(request) }
                }.disabled(!hasAccess || request == nil)
                Spacer()
                Button("Close") { model.magnifier.stop(); model.magnifierPresented = false }
            }
        }.padding(16).frame(width: 370)
            .onChange(of: request) { _, request in model.magnifier.update(request) }
            .onChange(of: model.document.area?.id) { _, _ in model.magnifier.stop(); model.magnifierPresented = false }
            .onDisappear { model.magnifier.stop() }
    }
}

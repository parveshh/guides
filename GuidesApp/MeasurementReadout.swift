import SwiftUI
import GuidesCore

struct MeasurementReadout: View {
    var model: EditorModel
    var onDimension: (AreaDimension) -> Void
    var onRadius: (CGFloat) -> Void
    var onNudgeArea: (CGFloat, CGFloat) -> Void
    var onOpacity: (CGFloat) -> Void
    var onCopy: () -> Void
    var onCopyVariable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.document.isAreaSelected {
                HStack(spacing: 0) {
                    HStack(spacing: 2) {
                        ForEach(AreaDimension.allCases, id: \.self) { dimension in
                            Button(dimension.rawValue) { onDimension(dimension) }
                                .buttonStyle(RailButtonStyle(selected: model.areaDimension == dimension))
                                .accessibilityAddTraits(model.areaDimension == dimension ? [.isSelected] : [])
                                .accessibilityLabel("Select \(dimension.rawValue.lowercased())")
                        }
                    }.modifier(RailSegments())
                    Spacer(minLength: 0)
                }
            }
            if model.document.isAreaSelected, model.areaDimension == .radius, let area = model.document.area {
                CornerRadiusEditor(area: area, apply: onRadius)
                HStack {
                    Text("Border \(Int((model.radiusOutlineOpacity * 100).rounded()))%").font(.system(size: 11)).foregroundStyle(.white)
                    Slider(value: Binding(get: { model.radiusOutlineOpacity }, set: { onOpacity($0) }), in: 0...1, step: 0.05)
                        .accessibilityLabel("Radius border opacity")
                    Button("Magnifier…") { model.magnifierPresented = true }
                        .buttonStyle(RailButtonStyle(filled: true))
                        .popover(isPresented: Binding(get: { model.magnifierPresented }, set: { model.magnifierPresented = $0 })) {
                            CornerMagnifierView(model: model, onRadius: onRadius, onNudge: onNudgeArea, onOpacity: onOpacity)
                        }
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.contextText).font(.system(size: 11)).foregroundStyle(OverlayStyle.secondaryText).lineLimit(1)
                    Text(model.selectedText).font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .lineLimit(1).truncationMode(.middle).help(model.selectedText)
                }
                Spacer(minLength: 0)
                Rectangle().fill(OverlayStyle.hairline).frame(width: 1, height: 30)
                Button("Copy", systemImage: "doc.on.doc", action: onCopy)
                    .buttonStyle(RailButtonStyle(filled: true)).fixedSize()
                    .help("Copy selected measurement (Command-C)")
            }
            if !model.spacingScale.tokens.isEmpty && !(model.document.isAreaSelected && model.areaDimension == .radius) {
                Divider().overlay(OverlayStyle.hairline)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Spacing suggestion").font(.system(size: 11)).foregroundStyle(OverlayStyle.secondaryText)
                        Spacer()
                        Button("Copy Variable", action: onCopyVariable)
                            .buttonStyle(RailButtonStyle(filled: true))
                            .disabled(model.spacingMatch?.copyReference == nil)
                            .help(model.spacingMatch?.copyReference ?? "Requires a unique calibrated match within tolerance")
                    }
                    if let match = model.spacingMatch {
                        Text(match.summary).font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle).help(match.summary)
                        Text(match.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1).help(match.detail)
                    } else {
                        Text(model.spacingHint).font(.system(size: 12)).lineLimit(2)
                    }
                }
            }
        }
        .padding(12)
        .modifier(OverlaySurface())
        .padding(8)
        .onChange(of: model.magnifierPresented) { _, shown in if !shown { model.magnifier.stop() } }
    }
}

private struct CornerRadiusEditor: View {
    let area: AreaMeasurement
    let apply: (CGFloat) -> Void
    @State private var draft = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fit the bounds, then adjust the curve to the visible corner.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TextField("Radius", text: $draft).textFieldStyle(.roundedBorder).frame(width: 65)
                    .accessibilityLabel("Corner radius in screen points").onSubmit(commit)
                Text("screen pt").font(.system(size: 11))
                Button("−") { apply(max(0, area.cornerRadius - 1)) }.accessibilityLabel("Decrease radius by one screen point")
                Button("+") { apply(min(area.maximumRadius, area.cornerRadius + 1)) }.accessibilityLabel("Increase radius by one screen point")
                Button("Apply", action: commit)
            }.buttonStyle(RailButtonStyle(filled: true))
            Text(error ?? "Circular fit · range 0–\(MeasurementText.number(area.maximumRadius)) screen pt")
                .font(.system(size: 11)).foregroundStyle(error == nil ? .white.opacity(0.7) : .orange)
                .lineLimit(2)
        }
        .onAppear(perform: reset)
        .onChange(of: area) { _, _ in reset() }
    }
    private func reset() { draft = MeasurementText.number(area.cornerRadius, decimals: 4); error = nil }
    private func commit() {
        guard let value = Double(draft), value.isFinite, value >= 0, value <= Double(area.maximumRadius) else {
            error = "Enter 0–\(MeasurementText.number(area.maximumRadius)) screen pt."; return
        }
        apply(CGFloat(value)); reset()
    }
}

import SwiftUI
import GuidesCore

struct MeasurementReadout: View {
    var model: EditorModel
    var onDimension: (AreaDimension) -> Void
    var onCopy: () -> Void
    var onCopyVariable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.document.isAreaSelected {
                HStack(spacing: 3) {
                    ForEach(AreaDimension.allCases, id: \.self) { dimension in
                        Button(dimension.rawValue) { onDimension(dimension) }
                            .buttonStyle(RailButtonStyle(selected: model.areaDimension == dimension))
                            .accessibilityAddTraits(model.areaDimension == dimension ? [.isSelected] : [])
                            .accessibilityLabel("Select \(dimension.rawValue.lowercased())")
                    }
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.contextText).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    Text(model.selectedText).font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle).help(model.selectedText)
                }
                Spacer(minLength: 0)
                Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 30)
                Button("Copy", systemImage: "doc.on.doc", action: onCopy)
                    .buttonStyle(RailButtonStyle(filled: true)).fixedSize()
                    .help("Copy selected measurement (Command-C)")
            }
            if !model.spacingScale.tokens.isEmpty {
                Divider().overlay(.white.opacity(0.15))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Spacing suggestion").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
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
    }
}

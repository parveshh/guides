import SwiftUI
import GuidesCore

struct GridEditor: View {
    let configuration: GridConfiguration
    let size: CGSize
    let calibration: Calibration
    let backingFactor: CGFloat
    let onApply: (GridConfiguration) -> Void
    let onCancel: () -> Void
    @State private var enabled: Bool
    @State private var spacing: String
    @State private var unit: MeasurementUnit
    @State private var originX: String
    @State private var originY: String
    @State private var opacity: Double
    @State private var error: String?

    init(configuration: GridConfiguration, size: CGSize, calibration: Calibration, backingFactor: CGFloat,
         onApply: @escaping (GridConfiguration) -> Void, onCancel: @escaping () -> Void) {
        self.configuration = configuration; self.size = size; self.calibration = calibration
        self.backingFactor = backingFactor; self.onApply = onApply; self.onCancel = onCancel
        _enabled = State(initialValue: configuration.isEnabled)
        _spacing = State(initialValue: String(Double(configuration.spacing)))
        _unit = State(initialValue: configuration.unit)
        _originX = State(initialValue: String(Double(configuration.origin.x)))
        _originY = State(initialValue: String(Double(configuration.origin.y)))
        _opacity = State(initialValue: Double(configuration.opacity))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spacing grid").font(.headline)
            Toggle("Show grid", isOn: $enabled)
            HStack {
                TextField("Spacing", text: $spacing).accessibilityLabel("Grid spacing")
                Picker("Unit", selection: $unit) {
                    ForEach(MeasurementUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().accessibilityLabel("Grid spacing unit")
            }
            if unit.requiresCalibration {
                Text(calibration.isConfirmed
                    ? "Uses the current \(MeasurementText.number(calibration.pointsPerPixel * 100))% scale and \(MeasurementText.number(calibration.rootPixels))px/rem base."
                    : "Set scale in the toolbar before applying a Design px or rem grid.")
                    .font(.caption).foregroundStyle(calibration.isConfirmed ? Color.secondary : Color.orange)
            }
            Text("Origin from display top-left (screen pt)").font(.caption)
            HStack {
                TextField("X", text: $originX).accessibilityLabel("Grid origin X in screen points")
                TextField("Y", text: $originY).accessibilityLabel("Grid origin Y in screen points")
                Button("Reset") { originX = "0"; originY = "0" }.help("Reset origin to the display's top-left corner")
            }
            HStack {
                Text("Opacity \(Int((opacity * 100).rounded()))%").frame(width: 92, alignment: .leading)
                Slider(value: $opacity, in: 0.1...0.8, step: 0.05).accessibilityLabel("Grid opacity")
            }
            Text("Square cells; guides and areas do not snap. Pin & work passes clicks through. Grid settings stay on this display until Guides quits.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply", action: apply).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 380).textFieldStyle(.roundedBorder)
    }

    private func apply() {
        do {
            guard let spacing = Double(spacing) else { throw GridError.spacing }
            guard let x = Double(originX), let y = Double(originY) else { throw GridError.origin }
            let updated = try GridConfiguration(isEnabled: enabled, spacing: CGFloat(spacing), unit: unit,
                origin: CGPoint(x: x, y: y), opacity: CGFloat(opacity))
            // An off grid may be configured before calibration, but origin is always display-local.
            guard x <= size.width, y <= size.height else { throw GridError.origin }
            if enabled { _ = try GridGeometry(configuration: updated, size: size, calibration: calibration, backingFactor: backingFactor) }
            onApply(updated)
        } catch { self.error = error.localizedDescription }
    }
}

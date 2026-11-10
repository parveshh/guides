import SwiftUI
import GuidesCore

struct OverlayContextControls: View {
    var model: EditorModel
    var onUnit: (MeasurementUnit) -> Void
    var onCalibration: (Calibration) -> Void
    var onGrid: (GridConfiguration) -> Void
    var onReferenceOpen: () -> Void
    var onReferenceApply: (ReferencePlacement) -> Void
    var onReferenceAlign: () -> Void
    var onReferenceRemove: () -> Void
    var onAnnotationTool: (AnnotationTool) -> Void
    var onAnnotationColor: (AnnotationColor) -> Void
    var onAnnotationOptions: () -> Void
    @State private var calibrationPresented = false
    @State private var gridPresented = false
    @State private var referencePresented = false
    @State private var pendingUnit: MeasurementUnit?

    var body: some View {
        Group {
            if model.isAnnotating {
                AnnotationControls(model: model, onTool: onAnnotationTool, onColor: onAnnotationColor, onOptions: onAnnotationOptions)
            } else {
                measurementControls
            }
        }
        .fixedSize()
        .padding(.horizontal, 12).padding(.vertical, 8)
        .buttonStyle(RailButtonStyle())
        .modifier(OverlaySurface())
        .padding(8)
        .onChange(of: model.displayID) { _, _ in dismissPopovers() }
        .onChange(of: model.presentation.tool) { _, _ in dismissPopovers() }
        .onChange(of: model.presentation.mode) { _, mode in if mode != .editing { dismissPopovers() } }
        .onChange(of: calibrationPresented) { _, visible in if !visible { pendingUnit = nil } }
    }

    private var measurementControls: some View {
        HStack(spacing: 12) {
            Text("Units").font(.system(size: 11)).foregroundStyle(OverlayStyle.secondaryText)
            Menu {
                ForEach(MeasurementUnit.allCases, id: \.self) { unit in
                    Button(unit.rawValue) { requestUnit(unit) }
                }
            } label: {
                Text(model.unit.rawValue).font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("Unit").accessibilityValue(model.unit.rawValue)
            .help("Unit shown on measurements and copied values")
            Button(model.calibration.isConfirmed ? "Scale \(MeasurementText.number(model.calibration.pointsPerPixel * 100))%" : "Set scale…") {
                gridPresented = false; referencePresented = false; pendingUnit = nil; calibrationPresented = true
            }
            .buttonStyle(RailButtonStyle(filled: true)).lineLimit(1).frame(maxWidth: 150)
            .help("Set the view scale explicitly for design px and rem")
            .popover(isPresented: $calibrationPresented) {
                CalibrationEditor(calibration: model.calibration, gapDistance: model.document.selectedGap?.distance,
                    area: model.document.isAreaSelected ? model.document.area?.rect : nil,
                    onApply: { calibration in
                        onCalibration(calibration)
                        if let pendingUnit { onUnit(pendingUnit) }
                        calibrationPresented = false
                    }, onCancel: { calibrationPresented = false })
            }
            RailDivider()
            Button("Grid", systemImage: "grid") {
                calibrationPresented = false; referencePresented = false; gridPresented = true
            }
            .buttonStyle(RailButtonStyle(selected: model.grid.isEnabled, selectionTint: true))
            .fixedSize()
            .accessibilityLabel("Grid settings").accessibilityValue(model.grid.isEnabled ? "Shown" : "Hidden")
            .help("Configure grid spacing, origin and opacity")
            .popover(isPresented: $gridPresented) {
                GridEditor(configuration: model.grid, size: model.document.size, calibration: model.calibration,
                    backingFactor: model.backingFactor,
                    onApply: { onGrid($0); gridPresented = false }, onCancel: { gridPresented = false })
            }
            Button("Reference", systemImage: "photo.on.rectangle") {
                calibrationPresented = false; gridPresented = false; referencePresented = true
            }
            .buttonStyle(RailButtonStyle(selected: model.aligningReference, selectionTint: true))
            .fixedSize()
            .accessibilityLabel("Reference image").help("Open and align a local reference image")
            .popover(isPresented: $referencePresented) {
                ReferenceEditor(reference: model.reference, size: model.document.size,
                    onOpen: { referencePresented = false; onReferenceOpen() },
                    onApply: { onReferenceApply($0); referencePresented = false }, onAlign: onReferenceAlign,
                    onRemove: { onReferenceRemove(); referencePresented = false }, onCancel: { referencePresented = false })
                    .id(model.reference.overlay?.id)
            }
        }
    }

    private func dismissPopovers() {
        calibrationPresented = false; gridPresented = false; referencePresented = false; pendingUnit = nil
    }
    private func requestUnit(_ unit: MeasurementUnit) {
        if unit.requiresCalibration, !model.calibration.isConfirmed {
            referencePresented = false; gridPresented = false; pendingUnit = unit; calibrationPresented = true
        } else { onUnit(unit) }
    }
}
private struct CalibrationEditor: View {
    var calibration: Calibration
    var gapDistance: CGFloat?
    var area: CGRect?
    var onApply: (Calibration) -> Void
    var onCancel: () -> Void
    @State private var method = 0
    @State private var percent = "100"
    @State private var knownPixels = ""
    @State private var rootPixels = "16"
    @State private var reference: AreaDimension = .width
    @State private var error: String?

    private var referenceDistance: CGFloat? {
        if let gapDistance { return gapDistance }
        if let area { return reference == .height ? area.height : area.width }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Measurement scale").font(.headline)
            Text("Set the scale for the view you are measuring. Update it when the app or zoom changes.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Method", selection: $method) {
                Text("View scale").tag(0)
                Text("Known size").tag(1)
            }.pickerStyle(.segmented)
            if method == 0 {
                TextField("View scale (%)", text: $percent)
                Text("100% means 1 screen point per design pixel.").font(.caption).foregroundStyle(.secondary)
            } else {
                if area != nil {
                    Picker("Reference", selection: $reference) {
                        Text("Area width").tag(AreaDimension.width)
                        Text("Area height").tag(AreaDimension.height)
                    }
                }
                if let distance = referenceDistance {
                    Text("Selected: \(MeasurementText.screenPoints(distance))").font(.caption)
                } else {
                    Text("Select a guide distance or an area first.").font(.caption).foregroundStyle(.orange)
                }
                TextField("Known size (px)", text: $knownPixels)
            }
            TextField("Root font size (px)", text: $rootPixels)
            Text("The rem base is shared with Settings and saved locally.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply", action: apply).keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20).frame(width: 340)
        .onAppear {
            percent = String(Double(calibration.pointsPerPixel * 100))
            rootPixels = String(Double(calibration.rootPixels))
        }
        .onSubmit { apply() }
    }

    private func apply() {
        var updated = calibration
        guard let root = Double(rootPixels), updated.setRootPixels(CGFloat(root)) else {
            error = "Enter a positive, finite root font size."; return
        }
        if method == 0 {
            guard let value = Double(percent), updated.setScale(percent: CGFloat(value)) else {
                error = "Enter a positive, finite scale percentage."; return
            }
        } else {
            guard let distance = referenceDistance, let value = Double(knownPixels),
                  updated.setKnownDistance(screenPoints: distance, designPixels: CGFloat(value)) else {
                error = "Select a nonzero measurement and enter its positive, finite pixel size."; return
            }
        }
        onApply(updated)
    }
}

import SwiftUI
import GuidesCore

struct OverlayControls: View {
    var model: EditorModel
    var onRulerAppearance: (RulerAppearance) -> Void
    var onInspectImage: () -> Void
    var onResizeWindow: () -> Void
    var onSpacingTokens: () -> Void
    var onTool: (MeasurementTool) -> Void
    var onUnit: (MeasurementUnit) -> Void
    var onCalibration: (Calibration) -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onPin: () -> Void
    var onHide: () -> Void
    @State private var calibrationPresented = false
    @State private var pendingUnit: MeasurementUnit?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                toolControls.fixedSize(horizontal: true, vertical: false)
                if !model.controlsCompact { actionControls }
            }
            if model.controlsCompact { HStack { Spacer(); actionControls } }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .buttonStyle(RailButtonStyle())
        .modifier(OverlaySurface())
        .padding(8)
        .onChange(of: model.displayID) { _, _ in calibrationPresented = false }
        .onChange(of: model.presentation.mode) { _, mode in
            if mode != .editing { calibrationPresented = false }
        }
        .onChange(of: calibrationPresented) { _, visible in if !visible { pendingUnit = nil } }
    }

    private var toolControls: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Inspect Image…", systemImage: "photo", action: onInspectImage)
                Button("Resize Window…", systemImage: "macwindow", action: onResizeWindow)
                Button("Spacing Tokens…", systemImage: "list.bullet", action: onSpacingTokens)
                Divider()
                Picker("Ruler background", selection: Binding(get: { model.rulerAppearance }, set: { onRulerAppearance($0) })) {
                    ForEach(RulerAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Image(systemName: "ruler").font(.system(size: 15)).foregroundStyle(.white)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Ruler background: \(model.rulerAppearance.rawValue)")
            .accessibilityLabel("Tools and ruler appearance")
            .accessibilityValue(model.rulerAppearance.rawValue)
            divider
            HStack(spacing: 0) {
                ForEach(MeasurementTool.allCases, id: \.self) { tool in
                    Button(tool.rawValue) { onTool(tool) }
                        .buttonStyle(RailButtonStyle(selected: model.presentation.tool == tool))
                        .fixedSize()
                        .accessibilityAddTraits(model.presentation.tool == tool ? [.isSelected] : [])
                }
            }.background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            divider
            Menu {
                ForEach(MeasurementUnit.allCases, id: \.self) { unit in
                    Button(unit.rawValue) { requestUnit(unit) }
                }
            } label: {
                Text(model.unit.rawValue).font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton).frame(width: 105, height: 30).padding(.horizontal, 5)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Unit").accessibilityValue(model.unit.rawValue)
            Button(model.calibration.isConfirmed ? "Scale \(MeasurementText.number(model.calibration.pointsPerPixel * 100))%" : "Set scale…") {
                pendingUnit = nil
                calibrationPresented = true
            }
            .buttonStyle(RailButtonStyle(filled: true)).lineLimit(1).frame(width: 120)
            .popover(isPresented: $calibrationPresented) {
                CalibrationEditor(calibration: model.calibration,
                    gapDistance: model.document.selectedGap?.distance,
                    area: model.document.isAreaSelected ? model.document.area?.rect : nil,
                    onApply: { calibration in
                        onCalibration(calibration)
                        if let pendingUnit { onUnit(pendingUnit) }
                        calibrationPresented = false
                    }, onCancel: { calibrationPresented = false })
            }
        }
    }

    private var actionControls: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.history.canUndo).help("Undo (⌘Z)").accessibilityLabel("Undo")
            Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.history.canRedo).help("Redo (⇧⌘Z)").accessibilityLabel("Redo")
            divider
            Button("Pin & work", systemImage: "pin", action: onPin)
                .fixedSize().help("Keep measurements visible and interact with other apps. Use the activation shortcut to edit again.")
            Button("Hide", systemImage: "eye.slash", action: onHide)
                .fixedSize().help("Hide measurements and return to other apps (Escape).")
        }
    }

    private var divider: some View { Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 24) }

    private func requestUnit(_ unit: MeasurementUnit) {
        if unit.requiresCalibration, !model.calibration.isConfirmed {
            pendingUnit = unit
            calibrationPresented = true
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

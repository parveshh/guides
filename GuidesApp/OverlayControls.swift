import SwiftUI
import GuidesCore

struct OverlayControls: View {
    var model: EditorModel
    var onRulerAppearance: (RulerAppearance) -> Void
    var onInspectImage: () -> Void
    var onResizeWindow: () -> Void
    var onSpacingTokens: () -> Void
    var onSavedLayouts: () -> Void
    var onTool: (OverlayTool) -> Void
    var onUnit: (MeasurementUnit) -> Void
    var onCalibration: (Calibration) -> Void
    var onGrid: (GridConfiguration) -> Void
    var onReferenceOpen: () -> Void
    var onReferenceApply: (ReferencePlacement) -> Void
    var onReferenceAlign: () -> Void
    var onReferenceRemove: () -> Void
    var onAnnotationTool: (AnnotationTool) -> Void
    var onAnnotationColor: (AnnotationColor) -> Void
    var onAnnotationStyle: (AnnotationStyle, Bool, CGFloat) -> Void
    var onAnnotationDelete: () -> Void
    var onAnnotationClear: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onPin: () -> Void
    var onHide: () -> Void
    @State private var calibrationPresented = false
    @State private var gridPresented = false
    @State private var referencePresented = false
    @State private var pendingUnit: MeasurementUnit?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                toolControls.fixedSize(horizontal: true, vertical: false)
                if !model.controlsCompact { actionControls }
            }
            if model.controlsCompact { HStack { Spacer(); actionControls } }
            if model.isAnnotating {
                AnnotationControls(model: model, onTool: onAnnotationTool, onColor: onAnnotationColor, onStyle: onAnnotationStyle,
                    onDelete: onAnnotationDelete, onClear: onAnnotationClear)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .buttonStyle(RailButtonStyle())
        .modifier(OverlaySurface())
        .padding(8)
        .onChange(of: model.displayID) { _, _ in calibrationPresented = false; gridPresented = false; referencePresented = false }
        .onChange(of: model.presentation.mode) { _, mode in
            if mode != .editing { calibrationPresented = false; gridPresented = false; referencePresented = false }
        }
        .onChange(of: calibrationPresented) { _, visible in if !visible { pendingUnit = nil } }
    }

    private var toolControls: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Inspect Image…", systemImage: "photo", action: onInspectImage)
                Button("Resize Window…", systemImage: "macwindow", action: onResizeWindow)
                Button("Spacing Tokens…", systemImage: "list.bullet", action: onSpacingTokens)
                Button("Saved Layouts…", systemImage: "square.stack", action: onSavedLayouts)
                Divider()
                Button(model.grid.isEnabled ? "Hide Grid" : "Show Grid", systemImage: "grid") {
                    var grid = model.grid
                    grid.isEnabled.toggle()
                    onGrid(grid)
                }
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
                ForEach(OverlayTool.allCases, id: \.self) { tool in
                    Button(tool.rawValue) { calibrationPresented = false; gridPresented = false; referencePresented = false; onTool(tool) }
                        .buttonStyle(RailButtonStyle(selected: (model.presentation.tool == tool && !model.aligningReference)))
                        .fixedSize()
                        .accessibilityAddTraits((model.presentation.tool == tool && !model.aligningReference) ? [.isSelected] : [])
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
                gridPresented = false
                referencePresented = false
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
            Button {
                calibrationPresented = false
                referencePresented = false
                gridPresented = true
            } label: { Image(systemName: "grid") }
                .buttonStyle(RailButtonStyle(selected: model.grid.isEnabled))
                .accessibilityLabel("Grid settings").accessibilityValue(model.grid.isEnabled ? "Shown" : "Hidden")
                .help("Configure grid spacing, origin and opacity")
                .popover(isPresented: $gridPresented) {
                    GridEditor(configuration: model.grid, size: model.document.size, calibration: model.calibration,
                        backingFactor: model.backingFactor,
                        onApply: { grid in onGrid(grid); gridPresented = false },
                        onCancel: { gridPresented = false })
                }
            Button {
                calibrationPresented = false; gridPresented = false
                referencePresented = true
            } label: { Image(systemName: "photo.on.rectangle") }
                .buttonStyle(RailButtonStyle(selected: model.aligningReference))
                .accessibilityLabel("Reference image")
                .help("Open and align a local reference image")
                .popover(isPresented: $referencePresented) {
                    ReferenceEditor(reference: model.reference, size: model.document.size,
                        onOpen: { referencePresented = false; onReferenceOpen() },
                        onApply: { placement in onReferenceApply(placement); referencePresented = false },
                        onAlign: onReferenceAlign,
                        onRemove: { onReferenceRemove(); referencePresented = false },
                        onCancel: { referencePresented = false })
                        .id(model.reference.overlay?.id)
                }
            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo).help(model.aligningReference ? "Undo reference placement (⌘Z)" : (model.isAnnotating ? "Undo annotation (⌘Z)" : "Undo measurement (⌘Z)")).accessibilityLabel("Undo")
            Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo).help(model.aligningReference ? "Redo reference placement (⇧⌘Z)" : (model.isAnnotating ? "Redo annotation (⇧⌘Z)" : "Redo measurement (⇧⌘Z)")).accessibilityLabel("Redo")
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
            referencePresented = false; gridPresented = false
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

import SwiftUI
import GuidesCore

struct AnnotationControls: View {
    var model: EditorModel
    var onTool: (AnnotationTool) -> Void
    var onColor: (AnnotationColor) -> Void
    var onOptions: () -> Void
    @State private var colorPresented = false

    private var color: AnnotationColor { model.annotations.document.selected?.style.color ?? model.annotations.style.color }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    Button(tool.rawValue, systemImage: tool.symbol) { onTool(tool) }
                        .buttonStyle(RailButtonStyle(selected: model.annotations.tool == tool, selectionTint: true))
                        .fixedSize().accessibilityLabel("Annotation \(tool.rawValue)")
                        .accessibilityAddTraits(model.annotations.tool == tool ? [.isSelected] : [])
                }
            }
            RailDivider()
            Button {
                colorPresented = true
            } label: {
                HStack(spacing: 6) {
                    AnnotationSwatch(color: color)
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }.padding(.horizontal, 4).frame(height: 30)
            }
            .buttonStyle(.plain).fixedSize()
            .accessibilityLabel("Annotation colour").accessibilityValue(color.rawValue)
            .help("Colour the selection and new annotations")
            .popover(isPresented: $colorPresented) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Colour").font(.headline).padding(.bottom, 6)
                    ForEach(AnnotationColor.allCases, id: \.self) { value in
                        Button {
                            colorPresented = false; onColor(value)
                        } label: {
                            HStack(spacing: 10) {
                                AnnotationSwatch(color: value)
                                Text(value.rawValue)
                                Spacer()
                                if value == color { Image(systemName: "checkmark") }
                            }.padding(6).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel(value.rawValue)
                        .accessibilityAddTraits(value == color ? [.isSelected] : [])
                    }
                }.padding(16).frame(width: 180).environment(\.colorScheme, .dark)
            }
            RailDivider()
            Button("Style", systemImage: "slider.horizontal.3", action: onOptions)
                .fixedSize().help("Outline, stroke and spotlight for the selection or new shapes")
                .accessibilityLabel("Annotation style and spotlight")
        }
        .onChange(of: model.displayID) { _, _ in colorPresented = false }
        .onChange(of: model.annotations.document.selectedID) { _, _ in colorPresented = false }
        .onChange(of: model.presentation.mode) { _, mode in if mode != .editing { colorPresented = false } }
    }
}

struct AnnotationSwatch: View {
    var color: AnnotationColor
    var body: some View {
        Group {
            if color == .transparent {
                VStack(spacing: 0) {
                    HStack(spacing: 0) { Color.white; Color.gray }
                    HStack(spacing: 0) { Color.gray; Color.white }
                }
            } else { Color(nsColor: color.nsColor) }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.5), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

private extension AnnotationTool {
    var symbol: String {
        switch self { case .select: "cursorarrow"; case .arrow: "arrow.up.right"; case .line: "line.diagonal"; case .rectangle: "rectangle" }
    }
}

/// A draft: Cancel never changes the selected annotation or the defaults.
struct AnnotationOptions: View {
    let session: AnnotationSession
    let onApply: (AnnotationStyle, Bool, CGFloat) -> Void
    let onCancel: () -> Void
    var onDelete: (() -> Void)? = nil
    @State private var color: AnnotationColor
    @State private var stroke: AnnotationStroke
    @State private var spotlight: Bool
    @State private var opacity: Double

    init(session: AnnotationSession, onApply: @escaping (AnnotationStyle, Bool, CGFloat) -> Void,
         onCancel: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.session = session; self.onApply = onApply; self.onCancel = onCancel; self.onDelete = onDelete
        let style = session.document.selected?.style ?? session.style
        _color = State(initialValue: style.color)
        _stroke = State(initialValue: style.stroke)
        _spotlight = State(initialValue: session.document.selected?.kind == .rectangle
            ? session.document.spotlightID == session.document.selectedID : session.newRectanglesSpotlight)
        _opacity = State(initialValue: Double(session.document.dimOpacity))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(session.document.selected?.kind.rawValue ?? "New annotations").font(.system(size: 16, weight: .semibold))
            Text(session.document.selected == nil ? "Style for new shapes" : "Style for the selection and new shapes")
                .font(.caption).foregroundStyle(OverlayStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text("Outline").frame(width: 56, alignment: .leading)
                AnnotationSwatch(color: color)
                Picker("Colour", selection: $color) {
                    ForEach(AnnotationColor.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().accessibilityLabel("Annotation colour")
            }
            Picker("Stroke", selection: $stroke) {
                ForEach(AnnotationStroke.allCases, id: \.self) { Text("\($0.rawValue) screen pt").tag($0) }
            }
            Divider()
            Toggle(session.document.selected?.kind == .rectangle ? "Spotlight" : "Spotlight new rectangles", isOn: $spotlight)
                .toggleStyle(.switch)
            Text("Dim outside the rectangle").font(.caption).foregroundStyle(OverlayStyle.secondaryText)
            HStack {
                Text("Outside dimming").font(.caption)
                Spacer()
                Text("\(Int((opacity * 100).rounded()))%").font(.caption).monospacedDigit()
            }
            Slider(value: $opacity, in: 0...0.8, step: 0.05).accessibilityLabel("Spotlight outside dimming")
            Text("One rectangle is the spotlight. Pin & work passes clicks through inside and outside it.")
                .font(.caption).foregroundStyle(OverlayStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let selected = session.document.selected, let onDelete {
                Divider()
                Button("Delete \(selected.kind.rawValue.lowercased())", systemImage: "trash", action: onDelete)
                    .buttonStyle(.plain).accessibilityLabel("Delete selected annotation")
            }
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") { onApply(AnnotationStyle(color: color, stroke: stroke), spotlight, CGFloat(opacity)) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13))
        .padding(20).frame(width: 320)
        .foregroundStyle(.white)
        .background(OverlayStyle.surface)
        .environment(\.colorScheme, .dark)
    }
}

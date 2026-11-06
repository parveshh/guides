import SwiftUI
import GuidesCore

struct AnnotationControls: View {
    var model: EditorModel
    let onTool: (AnnotationTool) -> Void
    let onColor: (AnnotationColor) -> Void
    let onStyle: (AnnotationStyle, Bool, CGFloat) -> Void
    let onDelete: () -> Void
    let onClear: () -> Void
    @State private var optionsPresented = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    Button(tool.rawValue) { onTool(tool) }
                        .buttonStyle(RailButtonStyle(selected: model.annotations.tool == tool))
                        .accessibilityLabel("Annotation \(tool.rawValue)")
                }
                if !model.controlsCompact { colorControls }
                Spacer(minLength: 4)
                optionsButton
                if !model.controlsCompact { deleteControls }
            }
            if model.controlsCompact {
                HStack(spacing: 8) {
                    colorControls
                    Spacer(minLength: 4)
                    deleteControls
                }
            }
        }
        .onChange(of: model.displayID) { _, _ in optionsPresented = false }
        .onChange(of: model.annotations.document.selectedID) { _, _ in optionsPresented = false }
        .onChange(of: model.presentation.mode) { _, mode in if mode != .editing { optionsPresented = false } }
    }

    private var colorControls: some View {
        HStack(spacing: 4) {
            Text("Colour").font(.caption).foregroundStyle(.secondary)
            ForEach(AnnotationColor.allCases, id: \.self) { color in
                let selected = (model.annotations.document.selected?.style.color ?? model.annotations.style.color) == color
                Button {
                    optionsPresented = false
                    onColor(color)
                } label: {
                    colorSwatch(color)
                        .overlay {
                            if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.black) }
                        }
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Annotation colour: \(color.rawValue)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .help("\(color.rawValue): colour the selection and new annotations")
            }
        }.fixedSize()
    }

    private func colorSwatch(_ color: AnnotationColor) -> some View {
        VStack(spacing: 0) {
            if color == .transparent {
                HStack(spacing: 0) { Color.white; Color.gray }
                HStack(spacing: 0) { Color.gray; Color.white }
            } else {
                Color(nsColor: color.nsColor)
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
    }

    private var optionsButton: some View {
        Button("Style & spotlight…") { optionsPresented = true }
            .popover(isPresented: $optionsPresented) {
                AnnotationOptions(session: model.annotations, onApply: { style, spotlight, opacity in
                    onStyle(style, spotlight, opacity); optionsPresented = false
                }, onCancel: { optionsPresented = false })
            }
    }

    private var deleteControls: some View {
        HStack(spacing: 8) {
            Button("Delete", action: onDelete).disabled(model.annotations.document.selected == nil)
                .accessibilityLabel("Delete selected annotation")
            Button("Clear", action: onClear).disabled(model.annotations.document.shapes.isEmpty)
                .accessibilityLabel("Clear annotations").help("Clear annotations and spotlight; retain measurements")
        }
    }
}

private struct AnnotationOptions: View {
    let session: AnnotationSession
    let onApply: (AnnotationStyle, Bool, CGFloat) -> Void
    let onCancel: () -> Void
    @State private var color: AnnotationColor = .pink
    @State private var stroke: AnnotationStroke = .regular
    @State private var spotlight = true
    @State private var opacity = 0.55

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Annotation style").font(.headline)
            Text(session.document.selected == nil ? "Style for new shapes" : "Style for the selection and new shapes")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Colour", selection: $color) {
                ForEach(AnnotationColor.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Stroke", selection: $stroke) {
                ForEach(AnnotationStroke.allCases, id: \.self) { Text("\($0.rawValue) screen pt").tag($0) }
            }
            Toggle(session.document.selected?.kind == .rectangle ? "Spotlight selected rectangle" : "Spotlight new rectangles", isOn: $spotlight)
            Text("Outside dimming: \(Int((opacity * 100).rounded()))%")
            Slider(value: $opacity, in: 0...0.8, step: 0.05).accessibilityLabel("Spotlight outside dimming")
            Text("One rectangle is the spotlight. Pin & work passes clicks through inside and outside it.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") { onApply(AnnotationStyle(color: color, stroke: stroke), spotlight, opacity) }
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 340)
        .onAppear {
            let style = session.document.selected?.style ?? session.style
            color = style.color; stroke = style.stroke
            spotlight = session.document.selected?.kind == .rectangle
                ? session.document.spotlightID == session.document.selectedID : session.newRectanglesSpotlight
            opacity = Double(session.document.dimOpacity)
        }
    }
}

import SwiftUI
import GuidesCore

/// The stable session bar. Active-tool settings live in a smaller, separate strip.
struct OverlayControls: View {
    var model: EditorModel
    var onRulerAppearance: (RulerAppearance) -> Void
    var onInspectImage: () -> Void
    var onResizeWindow: () -> Void
    var onSpacingTokens: () -> Void
    var onSavedLayouts: () -> Void
    var onProjectProfiles: () -> Void
    var onBreakpoints: () -> Void
    var onTool: (OverlayTool) -> Void
    var onGrid: (GridConfiguration) -> Void
    var onAnnotationClear: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onPin: () -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Guides").font(.system(size: 15, weight: .semibold)).padding(.horizontal, 6)
                RailDivider()
                HStack(spacing: 2) {
                    ForEach(OverlayTool.allCases, id: \.self) { tool in
                        Button(tool.rawValue, systemImage: tool.symbol) { onTool(tool) }
                            .buttonStyle(RailButtonStyle(selected: model.presentation.tool == tool && !model.aligningReference))
                            .fixedSize().help(tool.summary)
                            .accessibilityAddTraits(model.presentation.tool == tool && !model.aligningReference ? [.isSelected] : [])
                    }
                }.modifier(RailSegments())
                if !model.controlsCompact { sessionActions }
            }
            if model.controlsCompact { sessionActions }
        }
        .fixedSize()
        .padding(.horizontal, 14).padding(.vertical, 10)
        .buttonStyle(RailButtonStyle())
        .modifier(OverlaySurface())
        .padding(8)
    }

    private var sessionActions: some View {
        HStack(spacing: 8) {
            RailDivider()
            Menu {
                Section("Local tools") {
                    Button("Inspect Image…", systemImage: "photo", action: onInspectImage)
                    Button("Resize Window…", systemImage: "macwindow", action: onResizeWindow)
                    Button("Spacing Tokens…", systemImage: "list.bullet.rectangle", action: onSpacingTokens)
                    Button("Breakpoints…", systemImage: "arrow.left.and.right", action: onBreakpoints)
                    Button("Saved Layouts…", systemImage: "square.stack", action: onSavedLayouts)
                    Button("Project Profiles…", systemImage: "folder", action: onProjectProfiles)
                }
                Section("Canvas") {
                    Button(model.grid.isEnabled ? "Hide Grid" : "Show Grid", systemImage: "grid") {
                        var grid = model.grid; grid.isEnabled.toggle(); onGrid(grid)
                    }
                    Picker("Ruler background", selection: Binding(get: { model.rulerAppearance }, set: { onRulerAppearance($0) })) {
                        ForEach(RulerAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    if model.isAnnotating, !model.annotations.document.shapes.isEmpty {
                        Button("Clear Annotations", systemImage: "trash", action: onAnnotationClear)
                    }
                }
            } label: {
                Label("Tools", systemImage: "square.3.layers.3d")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            }
            .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 6)
            .help("Local tools, grid visibility and ruler background")
            .accessibilityLabel("Tools and ruler appearance").accessibilityValue(model.rulerAppearance.rawValue)
            RailDivider()
            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo).help("Undo (⌘Z)").accessibilityLabel("Undo")
            Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo).help("Redo (⇧⌘Z)").accessibilityLabel("Redo")
            RailDivider()
            Button(action: onPin) {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "pin")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pin & work").font(.system(size: 13, weight: .semibold))
                        Text("Click through to your app").font(.system(size: 10)).foregroundStyle(OverlayStyle.secondaryText)
                    }
                }
            }
            .fixedSize().help("Keep marks visible and use other apps. Use the activation shortcut to edit again.")
            .accessibilityLabel("Pin & work").accessibilityHint("Keep marks visible and pass clicks through to your app")
            RailDivider()
            Button("Hide", systemImage: "eye.slash", action: onHide)
                .fixedSize().help("Hide the overlay and return to other apps (Escape)")
        }
    }
}

struct RailDivider: View {
    var body: some View { Rectangle().fill(OverlayStyle.hairline).frame(width: 1, height: 22) }
}

private extension OverlayTool {
    var symbol: String {
        switch self { case .guides: "ruler"; case .area: "rectangle.dashed"; case .annotate: "pencil.line" }
    }
    var summary: String {
        switch self {
        case .guides: "Pull guides from the rulers and read the gaps between them"
        case .area: "Drag a rectangle to read width, height and corner radius"
        case .annotate: "Draw arrows, lines and a spotlight rectangle"
        }
    }
}

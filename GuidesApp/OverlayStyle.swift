import AppKit
import SwiftUI

/// Shared visual tokens for the overlay: one charcoal surface, one pink accent, one label style.
@MainActor
enum OverlayStyle {
    static let surface = Color(red: 0.12, green: 0.12, blue: 0.135)
    static let accent = Color(red: 1, green: 0.08, blue: 0.53)
    static let secondaryText = Color.white.opacity(0.64)
    static let hairline = Color.white.opacity(0.12)
    static let controlFill = Color.white.opacity(0.09)
    static let controlRadius: CGFloat = 7
    static let panelRadius: CGFloat = 14

    static let guide = NSColor(srgbRed: 1, green: 0.08, blue: 0.53, alpha: 1)
    /// Opaque enough to stay readable over any desktop content without sampling the screen.
    static let chip = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.115, alpha: 0.96)
    /// Breakpoint markers are reference marks, not guides, so they do not use the guide pink.
    /// Dark enough for white 10-point text (about 5:1) and to stand out on the light solid ruler.
    static let breakpoint = NSColor(srgbRed: 0, green: 0.42, blue: 0.78, alpha: 1)
    static let chipBorder = NSColor(white: 1, alpha: 0.22)
    static let halo = NSColor(white: 0, alpha: 0.45)
    static let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    static let rulerFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
}

struct RailButtonStyle: ButtonStyle {
    var selected = false
    var filled = false
    var selectionTint = false

    func makeBody(configuration: Configuration) -> some View {
        RailButtonBody(configuration: configuration, selected: selected, filled: filled, selectionTint: selectionTint)
    }
}

private struct RailButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    let filled: Bool
    let selectionTint: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    private var fill: Color {
        if selected { return OverlayStyle.accent.opacity(selectionTint ? 0.28 : (configuration.isPressed ? 0.8 : 1)) }
        if configuration.isPressed { return .white.opacity(0.2) }
        if hovering && enabled { return .white.opacity(0.14) }
        return filled ? OverlayStyle.controlFill : .clear
    }

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: selected ? .semibold : .medium))
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.35))
            .padding(.horizontal, 10).frame(height: 30)
            .background(fill, in: RoundedRectangle(cornerRadius: OverlayStyle.controlRadius))
            .contentShape(RoundedRectangle(cornerRadius: OverlayStyle.controlRadius))
            .onHover { hovering = $0 }
    }
}

struct OverlaySurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .background(OverlayStyle.surface, in: RoundedRectangle(cornerRadius: OverlayStyle.panelRadius))
            .overlay(RoundedRectangle(cornerRadius: OverlayStyle.panelRadius).stroke(OverlayStyle.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 5)
            .environment(\.colorScheme, .dark)
    }
}

/// Groups mutually exclusive choices, such as tools or area dimensions, on one recessed track.
struct RailSegments: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(2).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: OverlayStyle.controlRadius + 2))
    }
}

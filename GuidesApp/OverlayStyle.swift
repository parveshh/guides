import AppKit
import SwiftUI

enum OverlayStyle {
    static let surface = Color(red: 0.16, green: 0.16, blue: 0.17)
    static let accent = Color(red: 1, green: 0.08, blue: 0.53)
    static let guide = NSColor(srgbRed: 1, green: 0.08, blue: 0.53, alpha: 1)
}

struct RailButtonStyle: ButtonStyle {
    var selected = false
    var filled = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.35))
            .padding(.horizontal, 10).frame(height: 30)
            .background(selected ? OverlayStyle.accent : Color.white.opacity(configuration.isPressed ? 0.18 : (filled ? 0.08 : 0)),
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct OverlaySurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .background(OverlayStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 7, x: 0, y: 3)
            .environment(\.colorScheme, .dark)
    }
}

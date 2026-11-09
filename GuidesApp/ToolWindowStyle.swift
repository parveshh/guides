import SwiftUI

/// Shared layout pieces for the separate tool windows, so each opens with the same structure:
/// what the tool is, the controls grouped by task, then the caveats.
struct ToolHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(OverlayStyle.accent, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ToolCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityLabel(title).accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Scope and privacy caveats: always present, visually quieter than the controls.
struct ToolNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle").accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }.font(.caption).foregroundStyle(.secondary)
    }
}

struct ToolEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.tertiary).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(28)
    }
}

/// A selectable row for saved items, shared by layouts and profiles.
struct ToolListRow: View {
    let title: String
    let detail: String
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? AnyShapeStyle(OverlayStyle.accent) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? OverlayStyle.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

extension View {
    /// Tool windows share the overlay's accent for primary actions and selection.
    func toolWindow() -> some View { padding(20).tint(OverlayStyle.accent) }
}

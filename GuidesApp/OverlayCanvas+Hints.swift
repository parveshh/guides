import AppKit
import GuidesCore

extension OverlayCanvas {
    /// One step of the bottom hint bar: optional key caps followed by what they do.
    struct Hint {
        var keys: [String] = []
        var text: String
        /// Essential hints survive on narrow displays: the mode, how to reach other apps, and Escape.
        var essential = false
    }

    var hints: [Hint] {
        let shortcut = model.activationShortcut
        if model.presentation.mode == .pinned {
            return [Hint(text: "Pinned · \(model.contextText)", essential: true),
                    shortcut.isEmpty ? Hint(text: "Activation shortcut to edit", essential: true)
                        : Hint(keys: [shortcut], text: "Edit", essential: true)]
        }
        let pin = shortcut.isEmpty ? Hint(text: "Pin & work to use other apps", essential: true)
            : Hint(keys: [shortcut], text: "Pin to use other apps", essential: true)
        if model.aligningReference {
            return [Hint(text: "Aligning reference", essential: true), Hint(keys: ["Drag"], text: "Move"),
                    Hint(keys: ["Arrows"], text: "Nudge"), Hint(keys: ["⌘Z"], text: "Undo"),
                    Hint(keys: ["Esc"], text: "Back to measuring", essential: true)]
        }
        if model.isAnnotating {
            let drawing = model.annotations.tool != .select
            return [Hint(text: "Editing · Annotate · \(model.annotations.tool.rawValue)", essential: true),
                    Hint(keys: ["Drag"], text: drawing ? "Draw" : "Move or resize"),
                    Hint(keys: ["[", "]"], text: "Select"), Hint(keys: ["Arrows"], text: "Nudge"), Hint(keys: ["⌫"], text: "Delete"),
                    pin, Hint(keys: ["Esc"], text: "Cancel or hide", essential: true)]
        }
        if model.presentation.tool == .area {
            return [Hint(text: "Editing · Area", essential: true), Hint(keys: ["Drag"], text: "Draw, move or resize"),
                    Hint(keys: ["Arrows"], text: "Nudge"), Hint(keys: ["⌫"], text: "Delete"),
                    pin, Hint(keys: ["Esc"], text: "Cancel or hide", essential: true)]
        }
        return [Hint(text: "Editing · Guides", essential: true), Hint(keys: ["Drag"], text: "From a ruler"),
                Hint(keys: ["H", "V"], text: "Add at pointer"), Hint(keys: ["⇧", "Click"], text: "Pair two guides"),
                Hint(keys: ["Arrows"], text: "Nudge"), Hint(keys: ["⌫"], text: "Delete"),
                pin, Hint(keys: ["Esc"], text: "Hide", essential: true)]
    }

    /// Draws the hints as one bar. The first hint names the mode; on narrow displays the
    /// nonessential hints are dropped from the end, then the mode name truncates.
    func drawHints() {
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: NSColor.white]
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5, weight: .regular), .foregroundColor: NSColor(white: 1, alpha: 0.78)]
        let key: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10.5, weight: .semibold), .foregroundColor: NSColor.white]
        let height: CGFloat = 32, padding: CGFloat = 14, gap: CGFloat = 16, capGap: CGFloat = 4
        func capWidth(_ text: String) -> CGFloat { max(20, ceil((text as NSString).size(withAttributes: key).width) + 10) }
        func width(_ hint: Hint, first: Bool) -> CGFloat {
            let caps = hint.keys.reduce(0) { $0 + capWidth($1) + capGap }
            return caps + (hint.keys.isEmpty ? 0 : 2) + ceil((hint.text as NSString).size(withAttributes: first ? title : body).width)
        }
        var items = hints
        guard !items.isEmpty else { return }
        func total() -> CGFloat {
            items.enumerated().reduce(padding * 2 + gap * CGFloat(items.count - 1)) { $0 + width($1.element, first: $1.offset == 0) }
        }
        let available = max(0, usableRect.width - 16)
        while total() > available, let index = items.lastIndex(where: { !$0.essential }) { items.remove(at: index) }
        // If the essentials still do not fit, the mode name gives up the difference.
        let overflow = max(0, total() - available)
        let barWidth = min(total(), available)
        let bar = CGRect(x: usableRect.midX - barWidth / 2, y: usableRect.maxY - height - 14, width: barWidth, height: height)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let background = NSBezierPath(roundedRect: bar.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        OverlayStyle.chip.setFill(); background.fill()
        OverlayStyle.chipBorder.setStroke(); background.lineWidth = 1; background.stroke()
        background.addClip()
        var x = bar.minX + padding
        for (index, hint) in items.enumerated() {
            for cap in hint.keys {
                let rect = CGRect(x: x, y: bar.midY - 9, width: capWidth(cap), height: 18)
                NSColor(white: 1, alpha: 0.16).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
                let size = (cap as NSString).size(withAttributes: key)
                (cap as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: key)
                x += rect.width + capGap
            }
            if !hint.keys.isEmpty { x += 2 }
            var attributes = index == 0 ? title : body
            let size = (hint.text as NSString).size(withAttributes: attributes)
            let textWidth = max(0, ceil(size.width) - (index == 0 ? overflow : 0))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            attributes[.paragraphStyle] = paragraph
            (hint.text as NSString).draw(in: CGRect(x: x, y: bar.midY - size.height / 2, width: textWidth, height: size.height), withAttributes: attributes)
            x += textWidth + gap
            if index == 0, items.count > 1 {
                NSColor(white: 1, alpha: 0.18).setFill()
                CGRect(x: x - gap / 2 - 0.5, y: bar.midY - 8, width: 1, height: 16).fill()
            }
        }
    }
}

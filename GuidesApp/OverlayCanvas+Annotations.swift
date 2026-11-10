import AppKit
import GuidesCore

extension OverlayCanvas {
    func drawSpotlight() {
        guard let opening = model.annotations.document.spotlight else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        let mask = NSBezierPath(rect: bounds)
        mask.append(NSBezierPath(rect: opening))
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(model.annotations.document.dimOpacity).setFill()
        mask.fill()
    }

    func drawAnnotations() {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        for shape in model.annotations.document.shapes {
            let path = NSBezierPath()
            if shape.kind == .rectangle { path.append(NSBezierPath(rect: shape.bounds)) }
            else {
                path.move(to: shape.start); path.line(to: shape.end)
                if shape.kind == .arrow {
                    for wing in AnnotationGeometry.arrowWings(shape) { path.move(to: wing); path.line(to: shape.end) }
                }
            }
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            let width = CGFloat(shape.style.stroke.rawValue)
            if shape.style.color != .transparent {
                NSColor.black.withAlphaComponent(0.8).setStroke(); path.lineWidth = width + 2; path.stroke()
                shape.style.color.nsColor.setStroke(); path.lineWidth = width; path.stroke()
            }
            if model.presentation.mode == .editing, model.isAnnotating, model.annotations.document.selectedID == shape.id {
                let handles = shape.kind == .rectangle ? AreaHandle.allCases.map { $0.point(on: shape.bounds) } : [shape.start, shape.end]
                for point in handles {
                    let handle = NSBezierPath(ovalIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                    NSColor.white.setFill(); handle.fill()
                    OverlayStyle.guide.setStroke(); handle.lineWidth = 1; handle.stroke()
                }
            }
        }
    }
}

extension AnnotationColor {
    @MainActor var nsColor: NSColor {
        switch self {
        case .pink: OverlayStyle.guide
        case .yellow: NSColor.systemYellow
        case .cyan: NSColor.cyan
        case .white: NSColor.white
        case .orange: NSColor.systemOrange
        case .transparent: NSColor.clear
        }
    }
}

import Foundation
import CoreGraphics

/// Rounds pointer-placed geometry to whole backing pixels, so a guide or Area edge sits on a
/// pixel boundary instead of between two pixels. This is arithmetic on the overlay's own
/// coordinates; it reads nothing from the screen and does not detect edges.
public enum PixelSnapping {
    /// The nearest position, in screen points, that lies on a backing-pixel boundary.
    /// Nonfinite values and invalid backing factors are returned unchanged.
    public static func snap(_ value: CGFloat, backingFactor: CGFloat) -> CGFloat {
        guard value.isFinite, backingFactor.isFinite, backingFactor > 0 else { return value }
        let snapped = (value * backingFactor).rounded() / backingFactor
        return snapped.isFinite ? snapped : value
    }

    public static func snap(_ point: CGPoint, backingFactor: CGFloat) -> CGPoint {
        CGPoint(x: snap(point.x, backingFactor: backingFactor), y: snap(point.y, backingFactor: backingFactor))
    }

    /// Moves `rect` by the given distance and puts its top-left corner exactly on the nearest
    /// pixel boundary, keeping its size. The display edge wins over snapping.
    public static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat, within size: CGSize, backingFactor: CGFloat) -> CGRect {
        CGRect(x: min(max(snap(rect.minX + dx, backingFactor: backingFactor), 0), max(0, size.width - rect.width)),
               y: min(max(snap(rect.minY + dy, backingFactor: backingFactor), 0), max(0, size.height - rect.height)),
               width: rect.width, height: rect.height)
    }
}

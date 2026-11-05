import Foundation
import CoreGraphics

/// All inputs and outputs use display-local points with a top-left origin.
public enum MeasurementReadoutLayout {
    public static func gapAnchor(_ gap: GuideGap, usable: CGRect, toolbar: CGRect) -> CGPoint {
        gap.axis == .vertical
            ? CGPoint(x: gap.midpoint, y: max(usable.minY + 180, toolbar.maxY + 56))
            : CGPoint(x: usable.minX + 88, y: gap.midpoint)
    }

    public static func frame(size: CGSize, anchor: CGPoint, beside: Bool,
                             usable: CGRect, toolbar: CGRect, area: CGRect? = nil) -> CGRect {
        let inset = usable.insetBy(dx: 8, dy: 8)
        let width = min(size.width, max(0, inset.width))
        let height = min(size.height, max(0, inset.height))
        func clamped(_ origin: CGPoint) -> CGRect {
            CGRect(x: min(max(origin.x, inset.minX), inset.maxX - width),
                   y: min(max(origin.y, inset.minY), inset.maxY - height), width: width, height: height)
        }
        let below = CGPoint(x: anchor.x - width / 2, y: (area?.maxY ?? anchor.y) + 18)
        let above = CGPoint(x: anchor.x - width / 2, y: (area?.minY ?? anchor.y) - height - 18)
        let right = CGPoint(x: (area?.maxX ?? anchor.x) + 18, y: anchor.y - height / 2)
        let left = CGPoint(x: (area?.minX ?? anchor.x) - width - 18, y: anchor.y - height / 2)
        let belowToolbar = CGPoint(x: anchor.x - width / 2, y: toolbar.maxY + 16)
        let candidates = ((beside ? [right, left, below, above] : [below, above, right, left]) + [belowToolbar]).map(clamped)
        let exclusion = toolbar.insetBy(dx: -8, dy: -8)
        if let area, let clear = candidates.first(where: { !$0.intersects(exclusion) && !$0.intersects(area.insetBy(dx: -8, dy: -8)) }) {
            return clear
        }
        return candidates.first(where: { !$0.intersects(exclusion) }) ?? candidates[0]
    }
}

import Foundation
import CoreGraphics

/// All inputs and outputs use display-local points with a top-left origin.
public enum MeasurementReadoutLayout {
    /// Shared by drawing, hit testing and obstacle avoidance, including at display edges.
    public static func labelFrame(size: CGSize, centered point: CGPoint, usable: CGRect) -> CGRect {
        let width = min(max(0, size.width), max(0, usable.width))
        let height = min(max(0, size.height), max(0, usable.height))
        return CGRect(x: min(max(point.x - width / 2, usable.minX), usable.maxX - width),
            y: min(max(point.y - height / 2, usable.minY), usable.maxY - height), width: width, height: height)
    }

    public static func gapAnchor(_ gap: GuideGap, usable: CGRect, toolbar: CGRect, orthogonalPosition: CGFloat? = nil,
                                 labelSize: CGSize = CGSize(width: 24, height: 24)) -> CGPoint {
        let supplied = orthogonalPosition.flatMap { $0.isFinite ? $0 : nil }
        let value = supplied ?? (gap.axis == .vertical ? max(usable.minY + 180, toolbar.maxY + 56) : usable.minX + 88)
        let lower = gap.axis == .vertical ? usable.minY : usable.minX
        let upper = gap.axis == .vertical ? usable.maxY : usable.maxX
        let extent = gap.axis == .vertical ? labelSize.height : labelSize.width
        let inset = min(extent.isFinite ? max(0, extent / 2) : 12, max(0, (upper - lower) / 2))
        let position = min(max(value, lower + inset), upper - inset)
        func point(_ position: CGFloat) -> CGPoint {
            gap.axis == .vertical ? CGPoint(x: gap.midpoint, y: position) : CGPoint(x: position, y: gap.midpoint)
        }
        let exclusion = toolbar.insetBy(dx: -8, dy: -8)
        func blocked(_ position: CGFloat) -> Bool {
            !toolbar.isEmpty && labelFrame(size: labelSize, centered: point(position), usable: usable).intersects(exclusion)
        }
        if blocked(position) {
            let before = (gap.axis == .vertical ? exclusion.minY : exclusion.minX) - inset
            let after = (gap.axis == .vertical ? exclusion.maxY : exclusion.maxX) + inset
            let candidates = [before, after].filter { $0 >= lower + inset && $0 <= upper - inset && !blocked($0) }
            if let nearest = candidates.min(by: { abs($0 - position) < abs($1 - position) }) { return point(nearest) }
        }
        return point(position)
    }

    /// Directional accessibility steps skip an obstructing toolbar instead of snapping back forever.
    public static func nudgedGapAnchor(_ gap: GuideGap, anchor: CGPoint, by delta: CGFloat,
                                       usable: CGRect, toolbar: CGRect, labelSize: CGSize) -> CGPoint {
        guard delta.isFinite, delta != 0 else { return anchor }
        let current = gap.axis == .vertical ? anchor.y : anchor.x
        func adjusted(_ value: CGFloat) -> CGPoint {
            gapAnchor(gap, usable: usable, toolbar: toolbar, orthogonalPosition: value, labelSize: labelSize)
        }
        func progresses(_ candidate: CGPoint) -> Bool {
            let coordinate = gap.axis == .vertical ? candidate.y : candidate.x
            let clear = toolbar.isEmpty || !labelFrame(size: labelSize, centered: candidate, usable: usable)
                .intersects(toolbar.insetBy(dx: -8, dy: -8))
            return (coordinate - current) * delta > 0 && clear
        }
        let next = adjusted(current + delta)
        if progresses(next) { return next }
        guard !toolbar.isEmpty else { return anchor }
        let exclusion = toolbar.insetBy(dx: -8, dy: -8)
        let extent = (gap.axis == .vertical ? labelSize.height : labelSize.width) / 2
        let edge = delta < 0 ? (gap.axis == .vertical ? exclusion.minY : exclusion.minX) - extent
                            : (gap.axis == .vertical ? exclusion.maxY : exclusion.maxX) + extent
        let across = adjusted(edge)
        return progresses(across) ? across : anchor
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

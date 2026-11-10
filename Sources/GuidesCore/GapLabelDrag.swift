import Foundation

/// A label drag changes only the coordinate parallel to its two boundary guides.
public struct GapLabelDrag: Sendable {
    public let gap: GuideGap
    public let anchor: CGPoint
    public let start: CGPoint

    public init(gap: GuideGap, anchor: CGPoint, start: CGPoint) {
        self.gap = gap; self.anchor = anchor; self.start = start
    }

    public func position(at point: CGPoint) -> CGFloat {
        gap.axis == .vertical ? anchor.y + point.y - start.y : anchor.x + point.x - start.x
    }
}

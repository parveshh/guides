import Foundation
import CoreGraphics

public struct AreaMeasurement: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var rect: CGRect
    public init(id: UUID = UUID(), rect: CGRect) { self.id = id; self.rect = rect }
}

public enum AreaDimension: String, CaseIterable, Sendable { case width = "Width", height = "Height", both = "Both" }
public enum AreaHandle: CaseIterable, Equatable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    public func point(on rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

public enum AreaGeometry {
    public static func hitHandle(at point: CGPoint, rect: CGRect, radius: CGFloat = 7) -> AreaHandle? {
        func squaredDistance(_ handle: AreaHandle) -> CGFloat {
            let target = handle.point(on: rect)
            return pow(target.x - point.x, 2) + pow(target.y - point.y, 2)
        }
        guard let nearest = AreaHandle.allCases.min(by: { squaredDistance($0) < squaredDistance($1) }),
              squaredDistance(nearest) <= radius * radius else { return nil }
        return nearest
    }

    public static func rectangle(from start: CGPoint, to end: CGPoint, within size: CGSize) -> CGRect {
        let a = DisplayGeometry.clamp(start, to: size)
        let b = DisplayGeometry.clamp(end, to: size)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    public static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat, within size: CGSize) -> CGRect {
        CGRect(x: min(max(rect.minX + dx, 0), max(0, size.width - rect.width)),
               y: min(max(rect.minY + dy, 0), max(0, size.height - rect.height)),
               width: rect.width, height: rect.height)
    }

    public static func resized(_ rect: CGRect, handle: AreaHandle, to point: CGPoint, within size: CGSize) -> CGRect {
        let point = DisplayGeometry.clamp(point, to: size)
        var x1 = rect.minX, x2 = rect.maxX, y1 = rect.minY, y2 = rect.maxY
        if [.topLeft, .left, .bottomLeft].contains(handle) { x1 = point.x }
        if [.topRight, .right, .bottomRight].contains(handle) { x2 = point.x }
        if [.topLeft, .top, .topRight].contains(handle) { y1 = point.y }
        if [.bottomLeft, .bottom, .bottomRight].contains(handle) { y2 = point.y }
        return rectangle(from: CGPoint(x: x1, y: y1), to: CGPoint(x: x2, y: y2), within: size)
    }
}

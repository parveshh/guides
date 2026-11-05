import Foundation
import CoreGraphics

public struct DisplayGeometry: Equatable, Sendable {
    public var frame: CGRect
    public init(frame: CGRect) { self.frame = frame }

    public func localPoint(fromGlobal point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }

    public func globalPoint(fromLocal point: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + point.x, y: frame.maxY - point.y)
    }

    public func localRect(fromGlobal rect: CGRect) -> CGRect {
        CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }

    public static func clamp(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
    }
}

public enum GuideAxis: String, CaseIterable, Sendable {
    case horizontal, vertical
    public func position(of point: CGPoint) -> CGFloat { self == .horizontal ? point.y : point.x }
    public func limit(in size: CGSize) -> CGFloat { self == .horizontal ? size.height : size.width }
}

public struct Guide: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let axis: GuideAxis
    public var position: CGFloat
    public init(id: UUID = UUID(), axis: GuideAxis, position: CGFloat) {
        self.id = id; self.axis = axis; self.position = position
    }
}

public struct GuideGap: Equatable, Sendable {
    public let first: Guide
    public let second: Guide
    public var axis: GuideAxis { first.axis }
    public var distance: CGFloat { abs(second.position - first.position) }
    public var midpoint: CGFloat { (first.position + second.position) / 2 }
    public var ids: [UUID] { [first.id, second.id] }
}

public struct GuideDocument: Equatable, Sendable {
    public let size: CGSize
    public private(set) var guides: [Guide] = []
    public private(set) var selection: [UUID] = []
    public init(size: CGSize) { self.size = size }

    @discardableResult
    public mutating func add(axis: GuideAxis, position: CGFloat) -> UUID? {
        guard position.isFinite else { return nil }
        let guide = Guide(axis: axis, position: min(max(position, 0), axis.limit(in: size)))
        guides.append(guide)
        selection = [guide.id]
        return guide.id
    }

    public mutating func move(id: UUID, to position: CGFloat) {
        guard position.isFinite, let index = guides.firstIndex(where: { $0.id == id }) else { return }
        guides[index].position = min(max(position, 0), guides[index].axis.limit(in: size))
    }

    public mutating func select(_ ids: [UUID]) {
        selection = ids.filter { id in guides.contains(where: { $0.id == id }) }
    }

    public var adjacentGaps: [GuideGap] {
        GuideAxis.allCases.flatMap { axis in
            let ordered = guides.filter { $0.axis == axis }.sorted {
                $0.position == $1.position ? $0.id.uuidString < $1.id.uuidString : $0.position < $1.position
            }
            return zip(ordered, ordered.dropFirst()).map { GuideGap(first: $0, second: $1) }
        }
    }

    public var selectedGap: GuideGap? {
        guard selection.count == 2,
              let first = guides.first(where: { $0.id == selection[0] }),
              let second = guides.first(where: { $0.id == selection[1] }),
              first.id != second.id, first.axis == second.axis else { return nil }
        return GuideGap(first: first, second: second)
    }
}

public enum MeasurementText {
    public static func number(_ value: CGFloat, decimals: Int = 2) -> String {
        guard value.isFinite else { return "—" }
        var result = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), decimals, value)
        while result.contains("."), result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result == "-0" ? "0" : result
    }
    public static func screenPoints(_ value: CGFloat) -> String { "\(number(value)) screen pt" }
}

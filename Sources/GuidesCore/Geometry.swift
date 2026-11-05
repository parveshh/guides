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

public struct MeasurementDocument: Equatable, Sendable {
    public let size: CGSize
    public private(set) var guides: [Guide] = []
    public private(set) var selection: [UUID] = []
    public private(set) var area: AreaMeasurement?
    public private(set) var isAreaSelected = false
    public init(size: CGSize) { self.size = size }

    @discardableResult
    public mutating func add(axis: GuideAxis, position: CGFloat) -> UUID? {
        guard position.isFinite else { return nil }
        let guide = Guide(axis: axis, position: min(max(position, 0), axis.limit(in: size)))
        guides.append(guide)
        selection = [guide.id]
        isAreaSelected = false
        return guide.id
    }

    public mutating func move(id: UUID, to position: CGFloat) {
        guard position.isFinite, let index = guides.firstIndex(where: { $0.id == id }) else { return }
        guides[index].position = min(max(position, 0), guides[index].axis.limit(in: size))
    }

    public mutating func select(_ ids: [UUID]) {
        selection = ids.filter { id in guides.contains(where: { $0.id == id }) }
        isAreaSelected = false
    }

    public mutating func selectGuide(_ id: UUID, extending: Bool) {
        guard let guide = guides.first(where: { $0.id == id }) else { return }
        isAreaSelected = false
        guard extending else { selection = [id]; return }
        if selection.contains(id) { selection.removeAll { $0 == id }; return }
        if let anchor = selection.first, let other = guides.first(where: { $0.id == anchor }), other.axis == guide.axis {
            selection = [anchor, id]
        } else { selection = [id] }
    }

    public mutating func deleteSelection() {
        if isAreaSelected { area = nil; isAreaSelected = false }
        guides.removeAll { selection.contains($0.id) }
        selection = []
    }

    public mutating func clear() { guides = []; selection = []; area = nil; isAreaSelected = false }

    public mutating func setArea(_ rect: CGRect, id: UUID? = nil) {
        guard [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite) else { return }
        let bounded = AreaGeometry.rectangle(from: CGPoint(x: rect.minX, y: rect.minY),
            to: CGPoint(x: rect.maxX, y: rect.maxY), within: size)
        area = AreaMeasurement(id: id ?? area?.id ?? UUID(), rect: bounded)
        isAreaSelected = true
        selection = []
    }

    public mutating func selectArea() {
        guard area != nil else { return }
        selection = []
        isAreaSelected = true
    }

    public mutating func nudge(dx: CGFloat, dy: CGFloat) {
        guard dx.isFinite, dy.isFinite else { return }
        if isAreaSelected, let area {
            setArea(AreaGeometry.moved(area.rect, dx: dx, dy: dy, within: size))
            return
        }
        for axis in GuideAxis.allCases {
            let indices = guides.indices.filter { guides[$0].axis == axis && selection.contains(guides[$0].id) }
            guard !indices.isEmpty else { continue }
            let lower = -(indices.map { guides[$0].position }.min() ?? 0)
            let upper = axis.limit(in: size) - (indices.map { guides[$0].position }.max() ?? 0)
            let delta = min(max(axis == .horizontal ? dy : dx, lower), upper)
            for index in indices { guides[index].position += delta }
        }
    }

    public func hasSameContent(as other: MeasurementDocument) -> Bool {
        guides == other.guides && area == other.area && size == other.size
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

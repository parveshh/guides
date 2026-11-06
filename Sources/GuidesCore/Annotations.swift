import Foundation

public enum AnnotationKind: String, CaseIterable, Sendable { case arrow = "Arrow", line = "Line", rectangle = "Rectangle" }
public enum AnnotationTool: String, CaseIterable, Sendable {
    case select = "Select", arrow = "Arrow", line = "Line", rectangle = "Rectangle"
    public var kind: AnnotationKind? { AnnotationKind(rawValue: rawValue) }
}
public enum AnnotationColor: String, CaseIterable, Sendable { case pink = "Pink", yellow = "Yellow", cyan = "Cyan", white = "White", orange = "Orange" }
public enum AnnotationStroke: Int, CaseIterable, Sendable { case thin = 2, regular = 4, thick = 6 }
public struct AnnotationStyle: Equatable, Sendable {
    public var color: AnnotationColor = .pink
    public var stroke: AnnotationStroke = .regular
    public init(color: AnnotationColor = .pink, stroke: AnnotationStroke = .regular) { self.color = color; self.stroke = stroke }
}
public struct Annotation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: AnnotationKind
    public var start: CGPoint
    public var end: CGPoint
    public var style: AnnotationStyle
    public var bounds: CGRect { CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)) }
    public var isValid: Bool {
        kind == .rectangle ? bounds.width >= 1 && bounds.height >= 1 : hypot(end.x - start.x, end.y - start.y) >= 1
    }
    public init(id: UUID = UUID(), kind: AnnotationKind, start: CGPoint, end: CGPoint, style: AnnotationStyle = AnnotationStyle()) {
        self.id = id; self.kind = kind; self.start = start; self.end = end; self.style = style
    }
}

public enum AnnotationHandle: Equatable, Sendable { case start, end, rectangle(AreaHandle) }
public enum AnnotationGeometry {
    /// Prefer an unobscured toolbar without moving it under the pointer during a drag.
    public static func toolbarFrame(preferred: CGRect, usable: CGRect, spotlight: CGRect?) -> CGRect {
        guard let spotlight, preferred.intersects(spotlight) else { return preferred }
        let candidates = [
            CGRect(x: preferred.minX, y: usable.maxY - preferred.height - 16, width: preferred.width, height: preferred.height),
            CGRect(x: usable.minX + 16, y: preferred.minY, width: preferred.width, height: preferred.height),
            CGRect(x: usable.maxX - preferred.width - 16, y: preferred.minY, width: preferred.width, height: preferred.height)
        ]
        return candidates.first { usable.contains($0) && !$0.intersects(spotlight) } ?? preferred
    }

    public static func arrowWings(_ shape: Annotation) -> [CGPoint] {
        let dx = shape.end.x - shape.start.x, dy = shape.end.y - shape.start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return [] }
        let head = min(length * 0.45, max(12, CGFloat(shape.style.stroke.rawValue) * 3))
        let ux = dx / length, uy = dy / length
        return [-1.0, 1.0].map { sign in
            CGPoint(x: shape.end.x - head * ux + sign * head * 0.5 * uy,
                    y: shape.end.y - head * uy - sign * head * 0.5 * ux)
        }
    }
    public static func distance(_ point: CGPoint, from a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y, squared = dx * dx + dy * dy
        let t = squared > 0 ? min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / squared)) : 0
        return hypot(point.x - a.x - t * dx, point.y - a.y - t * dy)
    }
    public static func hits(_ shape: Annotation, at point: CGPoint) -> Bool {
        let tolerance = max(6, CGFloat(shape.style.stroke.rawValue) / 2 + 3)
        if shape.kind == .rectangle { return shape.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        if distance(point, from: shape.start, to: shape.end) <= tolerance { return true }
        return shape.kind == .arrow && arrowWings(shape).contains { distance(point, from: $0, to: shape.end) <= tolerance }
    }
    public static func handle(on shape: Annotation, at point: CGPoint) -> AnnotationHandle? {
        if shape.kind == .rectangle { return AreaGeometry.hitHandle(at: point, rect: shape.bounds).map(AnnotationHandle.rectangle) }
        let a = hypot(point.x - shape.start.x, point.y - shape.start.y)
        let b = hypot(point.x - shape.end.x, point.y - shape.end.y)
        guard min(a, b) <= 8 else { return nil }
        return a < b ? .start : .end
    }
    public static func moved(_ shape: Annotation, dx: CGFloat, dy: CGFloat, within size: CGSize) -> Annotation {
        let moved = AreaGeometry.moved(shape.bounds, dx: dx, dy: dy, within: size)
        let offset = CGPoint(x: moved.minX - shape.bounds.minX, y: moved.minY - shape.bounds.minY)
        var result = shape
        result.start.x += offset.x; result.start.y += offset.y
        result.end.x += offset.x; result.end.y += offset.y
        return result
    }
    public static func resized(_ shape: Annotation, handle: AnnotationHandle, to point: CGPoint, within size: CGSize) -> Annotation {
        var result = shape
        let point = DisplayGeometry.clamp(point, to: size)
        switch handle {
        case .start: result.start = point
        case .end: result.end = point
        case .rectangle(let handle):
            let rect = AreaGeometry.resized(shape.bounds, handle: handle, to: point, within: size)
            result.start = rect.origin; result.end = CGPoint(x: rect.maxX, y: rect.maxY)
        }
        return result
    }
}

public struct AnnotationDocument: Equatable, Sendable {
    public let size: CGSize
    public fileprivate(set) var shapes: [Annotation] = []
    public fileprivate(set) var selectedID: UUID?
    public fileprivate(set) var spotlightID: UUID?
    public fileprivate(set) var dimOpacity: CGFloat = 0.55
    public var selected: Annotation? { shapes.first { $0.id == selectedID } }
    public var spotlight: CGRect? { shapes.first { $0.id == spotlightID && $0.kind == .rectangle && $0.isValid }?.bounds }
    public init(size: CGSize) { self.size = size }
    fileprivate func hasSameContent(as other: Self) -> Bool { shapes == other.shapes && spotlightID == other.spotlightID && dimOpacity == other.dimOpacity }
}

/// Owns annotation gestures and their history. Window/input code supplies only local points.
public struct AnnotationSession: Sendable {
    public private(set) var document: AnnotationDocument
    public private(set) var tool: AnnotationTool = .rectangle
    public private(set) var style = AnnotationStyle()
    public private(set) var newRectanglesSpotlight = true
    private var past: [AnnotationDocument] = []
    private var future: [AnnotationDocument] = []
    private enum Drag: Sendable { case create(UUID, CGPoint), move(Annotation, CGPoint), resize(Annotation, AnnotationHandle) }
    private var gesture: (before: AnnotationDocument, drag: Drag)?
    public var isDragging: Bool { gesture != nil }
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public init(size: CGSize) { document = AnnotationDocument(size: size) }

    public mutating func setTool(_ value: AnnotationTool) {
        cancel(); tool = value
        if value.kind != nil { document.selectedID = nil }
    }
    public mutating func select(_ id: UUID?) {
        cancel(); document.selectedID = document.shapes.first { $0.id == id }?.id; tool = .select
    }
    public mutating func begin(at point: CGPoint) {
        cancel()
        guard point.x.isFinite, point.y.isFinite, document.size.width > 0, document.size.height > 0 else { return }
        let point = DisplayGeometry.clamp(point, to: document.size)
        let before = document
        if let kind = tool.kind {
            let shape = Annotation(kind: kind, start: point, end: point, style: style)
            document.shapes.append(shape); document.selectedID = shape.id
            if kind == .rectangle && newRectanglesSpotlight { document.spotlightID = shape.id }
            gesture = (before, .create(shape.id, point))
        } else if let selected = document.selected, let handle = AnnotationGeometry.handle(on: selected, at: point) {
            gesture = (before, .resize(selected, handle))
        } else if let shape = document.shapes.reversed().first(where: { AnnotationGeometry.hits($0, at: point) }) {
            document.selectedID = shape.id; gesture = (before, .move(shape, point))
        } else { document.selectedID = nil }
    }
    public mutating func drag(to point: CGPoint) {
        guard let gesture, point.x.isFinite, point.y.isFinite else { return }
        let point = DisplayGeometry.clamp(point, to: document.size)
        let updated: Annotation
        switch gesture.drag {
        case .create(let id, let start):
            guard let current = document.shapes.first(where: { $0.id == id }) else { return }
            updated = Annotation(id: id, kind: current.kind, start: start, end: point, style: current.style)
        case .move(let original, let start):
            updated = AnnotationGeometry.moved(original, dx: point.x - start.x, dy: point.y - start.y, within: document.size)
        case .resize(let original, let handle):
            updated = AnnotationGeometry.resized(original, handle: handle, to: point, within: document.size)
        }
        if let index = document.shapes.firstIndex(where: { $0.id == updated.id }) { document.shapes[index] = updated }
    }
    public mutating func end() {
        guard let gesture else { return }
        self.gesture = nil
        guard document.selected?.isValid == true else { document = gesture.before; return }
        record(gesture.before)
        tool = .select
    }
    @discardableResult public mutating func cancel() -> Bool {
        guard let gesture else { return false }
        document = gesture.before; self.gesture = nil; return true
    }
    public mutating func cycle(backwards: Bool) {
        cancel(); guard !document.shapes.isEmpty else { return }
        let index = document.shapes.firstIndex { $0.id == document.selectedID }
        let next = index.map { ($0 + (backwards ? -1 : 1) + document.shapes.count) % document.shapes.count }
            ?? (backwards ? document.shapes.count - 1 : 0)
        document.selectedID = document.shapes[next].id; tool = .select
    }
    public mutating func nudge(dx: CGFloat, dy: CGFloat) {
        cancel(); guard dx.isFinite, dy.isFinite, let selected = document.selected,
            let index = document.shapes.firstIndex(where: { $0.id == selected.id }) else { return }
        let before = document
        document.shapes[index] = AnnotationGeometry.moved(selected, dx: dx, dy: dy, within: document.size)
        record(before)
    }
    public mutating func setColor(_ color: AnnotationColor) {
        cancel()
        let before = document
        style.color = color
        if let index = document.shapes.firstIndex(where: { $0.id == document.selectedID }) {
            document.shapes[index].style.color = color
        }
        record(before)
    }
    public mutating func apply(style: AnnotationStyle, spotlight: Bool, dimOpacity: CGFloat) {
        cancel(); guard dimOpacity.isFinite, (0...0.8).contains(dimOpacity) else { return }
        let before = document
        self.style = style
        if let selected = document.selected, let index = document.shapes.firstIndex(where: { $0.id == selected.id }) {
            document.shapes[index].style = style
            if selected.kind == .rectangle {
                if spotlight { document.spotlightID = selected.id }
                else if document.spotlightID == selected.id { document.spotlightID = nil }
            } else { newRectanglesSpotlight = spotlight }
        } else { newRectanglesSpotlight = spotlight }
        document.dimOpacity = dimOpacity
        record(before)
    }
    public mutating func deleteSelection() {
        cancel(); let before = document
        document.shapes.removeAll { $0.id == document.selectedID }
        if document.spotlightID == document.selectedID { document.spotlightID = nil }
        document.selectedID = nil; record(before)
    }
    public mutating func clear() {
        cancel(); let before = document
        document.shapes = []; document.selectedID = nil; document.spotlightID = nil; record(before)
    }
    private mutating func record(_ before: AnnotationDocument) {
        guard !before.hasSameContent(as: document) else { return }
        past.append(before); if past.count > 100 { past.removeFirst() }; future = []
    }
    public mutating func undo() {
        cancel(); guard let value = past.popLast() else { return }
        future.append(document); document = value; tool = .select
    }
    public mutating func redo() {
        cancel(); guard let value = future.popLast() else { return }
        past.append(document); document = value; tool = .select
    }
}

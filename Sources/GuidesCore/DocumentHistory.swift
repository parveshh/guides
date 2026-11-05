public struct DocumentHistory: Sendable {
    private var past: [MeasurementDocument] = []
    private var future: [MeasurementDocument] = []
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public init() {}

    public mutating func record(before: MeasurementDocument, after: MeasurementDocument) {
        guard !before.hasSameContent(as: after) else { return }
        past.append(before)
        if past.count > 100 { past.removeFirst() }
        future.removeAll()
    }

    public mutating func undo(current: MeasurementDocument) -> MeasurementDocument? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    public mutating func redo(current: MeasurementDocument) -> MeasurementDocument? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }
}

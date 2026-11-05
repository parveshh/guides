public struct DocumentHistory: Sendable {
    private var past: [GuideDocument] = []
    private var future: [GuideDocument] = []
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public init() {}

    public mutating func record(before: GuideDocument, after: GuideDocument) {
        guard !before.hasSameContent(as: after) else { return }
        past.append(before)
        if past.count > 100 { past.removeFirst() }
        future.removeAll()
    }

    public mutating func undo(current: GuideDocument) -> GuideDocument? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    public mutating func redo(current: GuideDocument) -> GuideDocument? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }
}

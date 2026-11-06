public enum OverlayMode: String, Sendable {
    case hidden, editing, pinned
}

public enum OverlayTool: String, CaseIterable, Sendable {
    case guides = "Guides"
    case area = "Area"
    case annotate = "Annotate"
}

public struct Presentation: Equatable, Sendable {
    public private(set) var mode: OverlayMode = .hidden
    public private(set) var tool: OverlayTool = .guides

    public init() {}

    public mutating func edit(_ tool: OverlayTool) {
        self.tool = tool
        mode = .editing
    }

    public mutating func pin() {
        guard mode == .editing else { return }
        mode = .pinned
    }

    public mutating func hide() { mode = .hidden }
}

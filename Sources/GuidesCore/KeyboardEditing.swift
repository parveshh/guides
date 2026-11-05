public enum NudgeStep: Equatable, Sendable { case point, tenPoints, backingPixel }

public enum EditingKeyAction: Equatable, Sendable {
    case add(GuideAxis)
    case delete
    case nudge(horizontal: Int, vertical: Int, step: NudgeStep)
}

public enum KeyboardEditing {
    public static func action(keyCode: UInt16, characters: String?, command: Bool = false,
                              control: Bool = false, option: Bool = false, shift: Bool = false) -> EditingKeyAction? {
        guard !command, !control else { return nil }
        if !option {
            if characters?.lowercased() == "h" { return .add(.horizontal) }
            if characters?.lowercased() == "v" { return .add(.vertical) }
        }
        if !option, !shift, keyCode == 51 || keyCode == 117 { return .delete }
        let step: NudgeStep = option ? .backingPixel : (shift ? .tenPoints : .point)
        switch keyCode {
        case 123: return .nudge(horizontal: -1, vertical: 0, step: step)
        case 124: return .nudge(horizontal: 1, vertical: 0, step: step)
        case 125: return .nudge(horizontal: 0, vertical: 1, step: step)
        case 126: return .nudge(horizontal: 0, vertical: -1, step: step)
        default: return nil
        }
    }
}

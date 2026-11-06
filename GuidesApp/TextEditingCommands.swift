import AppKit

/// Accessory windows have no Edit menu to supply standard text commands.
enum TextEditingCommands {
    @MainActor static func handle(_ event: NSEvent, responder: NSResponder?) -> Bool {
        guard let editor = responder as? NSTextView else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command {
            switch key {
            case "a": editor.selectAll(nil); return true
            case "c": editor.copy(nil); return true
            case "v": editor.pasteAsPlainText(nil); return true
            case "x": editor.cut(nil); return true
            case "z": editor.undoManager?.undo(); return true
            default: break
            }
        }
        if modifiers == [.command, .shift], key == "z" { editor.undoManager?.redo(); return true }
        return false
    }
}

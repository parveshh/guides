import Testing
@testable import GuidesCore

@Test func commandAndControlNeverFallThroughToEditing() {
    for code: UInt16 in [4, 9, 51, 117, 123, 124, 125, 126] {
        for character in ["h", "v", ""] {
            #expect(KeyboardEditing.action(keyCode: code, characters: character, command: true) == nil)
            #expect(KeyboardEditing.action(keyCode: code, characters: character, control: true) == nil)
        }
    }
}

@Test func guideKeysAndDeleteRespectModifiers() {
    #expect(KeyboardEditing.action(keyCode: 4, characters: "h") == .add(.horizontal))
    #expect(KeyboardEditing.action(keyCode: 9, characters: "V", shift: true) == .add(.vertical))
    #expect(KeyboardEditing.action(keyCode: 9, characters: "v", option: true) == nil)
    #expect(KeyboardEditing.action(keyCode: 51, characters: nil) == .delete)
    #expect(KeyboardEditing.action(keyCode: 51, characters: nil, option: true) == nil)
}

@Test func arrowStepsAreExplicit() {
    #expect(KeyboardEditing.action(keyCode: 124, characters: nil) == .nudge(horizontal: 1, vertical: 0, step: .point))
    #expect(KeyboardEditing.action(keyCode: 125, characters: nil, shift: true) == .nudge(horizontal: 0, vertical: 1, step: .tenPoints))
    #expect(KeyboardEditing.action(keyCode: 123, characters: nil, option: true, shift: true) == .nudge(horizontal: -1, vertical: 0, step: .backingPixel))
}

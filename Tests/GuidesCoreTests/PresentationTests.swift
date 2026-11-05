import Testing
@testable import GuidesCore

@Test func presentationLifecycle() {
    var state = Presentation()
    #expect(state.mode == .hidden)
    state.pin()
    #expect(state.mode == .hidden)
    state.edit(.area)
    #expect(state.mode == .editing)
    #expect(state.tool == .area)
    state.pin()
    #expect(state.mode == .pinned)
    state.edit(.guides)
    #expect(state.mode == .editing)
    #expect(state.tool == .guides)
    state.hide()
    #expect(state.mode == .hidden)
}

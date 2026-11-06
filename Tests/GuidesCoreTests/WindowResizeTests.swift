import Foundation
import Testing
@testable import GuidesCore

@Test func windowDimensionsRequireBoundedWholeScreenPoints() throws {
    #expect(try WindowSizeRequest(width: " 2560 ", height: "1440").size == CGSize(width: 2560, height: 1440))
    for invalid in ["", "0", "-1", "1.5", "nan", "inf", "1e3", "16385", "999999999999999999999999", "１２８０"] {
        #expect(throws: WindowResizeError.invalidSize) { try WindowSizeRequest(width: invalid, height: "900") }
        #expect(throws: WindowResizeError.invalidSize) { try WindowSizeRequest(width: "1440", height: invalid) }
    }
    #expect(try WindowSizeRequest(width: "1", height: "16384").size.height == 16384)
}

@Test func windowSizeMatchingDoesNotConfuseRetinaPixelsOrClamping() {
    let requested = CGSize(width: 2560, height: 1440)
    #expect(WindowSizeRequest.matches(requested, requested))
    #expect(!WindowSizeRequest.matches(CGSize(width: 1280, height: 720), requested))
    #expect(!WindowSizeRequest.matches(CGSize(width: 2560, height: 1400), requested))
    #expect(WindowSizeRequest.text(requested) == "2560 × 1440 screen pt")
}

private actor TestWindowResizer: WindowResizing {
    let target = ResizeTarget(id: UUID(), applicationName: "Browser", title: "Test page",
        frame: CGRect(x: -1400, y: -200, width: 1000, height: 700))
    var resizeCalls: [UUID] = []
    var restoreCalls: [UUID] = []
    var captureError: WindowResizeError?
    var resizeResult = WindowResizeResult(frame: CGRect(x: -1400, y: -200, width: 1920, height: 1080),
        canRestore: true, message: "App constrained the requested size.")
    var suspendCapture = false
    private var pending: CheckedContinuation<ResizeTarget, any Error>?
    private var started: CheckedContinuation<Void, Never>?

    func configure(error: WindowResizeError? = nil, suspend: Bool = false, unreadable: Bool = false) {
        captureError = error; suspendCapture = suspend
        if unreadable { resizeResult = WindowResizeResult(frame: nil, canRestore: true, message: "Actual size unavailable") }
    }
    func capture(processID: Int32, applicationName: String) async throws -> ResizeTarget {
        if let captureError { throw captureError }
        if suspendCapture {
            return try await withCheckedThrowingContinuation {
                pending = $0; started?.resume(); started = nil
            }
        }
        return target
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() { pending?.resume(returning: target); pending = nil }
    func resize(targetID: UUID, request: WindowSizeRequest) -> WindowResizeResult {
        resizeCalls.append(targetID)
        return resizeResult
    }
    func restore(targetID: UUID) -> WindowResizeResult {
        restoreCalls.append(targetID)
        return WindowResizeResult(frame: target.frame, canRestore: false, message: "Restored")
    }
}

@MainActor @Test func invalidWindowSizeNeverInvokesTheService() async {
    let service = TestWindowResizer()
    let model = WindowResizeModel(service: service)
    await model.capture(processID: 123, applicationName: "Browser")?.value
    model.width = "0"
    #expect(model.resize() == nil)
    #expect(await service.resizeCalls.isEmpty)
    #expect(model.message == WindowResizeError.invalidSize.localizedDescription)
}

@MainActor @Test func clampedWindowSizeIsShownAndRestoreKeepsTheExactTarget() async {
    let service = TestWindowResizer()
    let model = WindowResizeModel(service: service)
    await model.capture(processID: 123, applicationName: "Browser")?.value
    let id = model.target?.id
    await model.resize()?.value
    #expect(model.target?.frame.size == CGSize(width: 1920, height: 1080))
    #expect(model.width == "2560" && model.height == "1440")
    #expect(model.canRestore && model.frameIsKnown)
    #expect(model.message == "App constrained the requested size.")
    await model.restore()?.value
    #expect(await service.resizeCalls == [id!])
    #expect(await service.restoreCalls == [id!])
    #expect(model.target?.frame == CGRect(x: -1400, y: -200, width: 1000, height: 700))
    #expect(!model.canRestore)
}

@MainActor @Test func unconfirmedResizeRetainsRecoveryWithoutClaimingAnActualSize() async {
    let service = TestWindowResizer()
    await service.configure(unreadable: true)
    let model = WindowResizeModel(service: service)
    await model.capture(processID: 123, applicationName: "Browser")?.value
    await model.resize()?.value
    #expect(!model.frameIsKnown && model.canRestore)
}

@MainActor @Test func deniedOrMissingWindowCannotBeResized() async {
    for error in [WindowResizeError.permissionRequired, .noWindow, .unsupported, .staleTarget] {
        let service = TestWindowResizer()
        await service.configure(error: error)
        let model = WindowResizeModel(service: service)
        await model.capture(processID: 123, applicationName: "Browser")?.value
        #expect(model.target == nil && !model.isBusy && !model.canRestore)
        #expect(model.message == error.localizedDescription)
        #expect(model.resize() == nil)
        #expect(await service.resizeCalls.isEmpty)
    }
}

@MainActor @Test func closedWindowToolRejectsLateResultsAndDuplicateOperations() async {
    let service = TestWindowResizer()
    await service.configure(suspend: true)
    let model = WindowResizeModel(service: service)
    let task = model.capture(processID: 123, applicationName: "Browser")
    await service.waitUntilStarted()
    #expect(model.capture(processID: 456, applicationName: "Different app") == nil)
    #expect(model.resize() == nil && model.restore() == nil)
    model.clear()
    await service.finish()
    await task?.value
    #expect(model.target == nil && !model.isBusy && !model.canRestore && model.message == nil)
}

import Foundation
import ImageIO
import Testing
@testable import GuidesCore

private let display = CGSize(width: 1000, height: 800)
private let source = CGSize(width: 1200, height: 600)

@Test func referenceFitsWithoutUpscalingAndPreservesSourceAspect() throws {
    let large = try ReferencePlacement.fitted(sourceSize: source, displaySize: display)
    #expect(large.frame == CGRect(x: 100, y: 200, width: 800, height: 400))
    #expect(large.opacity == 0.5 && large.isVisible)
    let small = try ReferencePlacement.fitted(sourceSize: CGSize(width: 100, height: 200), displaySize: display)
    #expect(small.frame == CGRect(x: 450, y: 300, width: 100, height: 200))
    let explicit = try ReferencePlacement(sourceSize: source, width: 600, origin: CGPoint(x: -50, y: 70), displaySize: display)
    #expect(explicit.frame == CGRect(x: -50, y: 70, width: 600, height: 300))
}

@Test func referenceRejectsInvalidGeometryAndKeepsPartialImagesReachable() throws {
    for width: CGFloat in [0, .nan, .infinity, 32769] {
        #expect(throws: ReferenceError.self) { try ReferencePlacement(sourceSize: source, width: width, origin: .zero, displaySize: display) }
    }
    for origin in [CGPoint(x: -600, y: 0), CGPoint(x: 1000, y: 0), CGPoint(x: 0, y: -300), CGPoint(x: CGFloat.nan, y: 0)] {
        #expect(throws: ReferenceError.self) { try ReferencePlacement(sourceSize: source, width: 600, origin: origin, displaySize: display) }
    }
    for opacity: CGFloat in [0, 0.09, 1.01, .nan] {
        #expect(throws: ReferenceError.self) { try ReferencePlacement(sourceSize: source, width: 600, origin: .zero, opacity: opacity, displaySize: display) }
    }
    #expect(throws: ReferenceError.self) { try ReferencePlacement(sourceSize: .zero, width: 600, origin: .zero, displaySize: display) }
    #expect(throws: ReferenceError.self) { try ReferencePlacement(sourceSize: CGSize(width: 1, height: 100), width: 600, origin: .zero, displaySize: display) }
    let placement = try ReferencePlacement.fitted(sourceSize: source, displaySize: display)
    let moved = placement.moved(dx: -1e20, dy: 1e20, displaySize: display)
    #expect(moved.frame.origin == CGPoint(x: -799, y: 799))
    #expect(moved.frame.size == placement.frame.size)
    #expect(placement.moved(dx: .nan, dy: 0, displaySize: display) == placement)
}

private func referenceImage(_ name: String = "fixture.png") throws -> InspectedImage {
    let context = try #require(CGContext(data: nil, width: 120, height: 60, bitsPerComponent: 8, bytesPerRow: 480,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let cgImage = try #require(context.makeImage())
    return InspectedImage(metadata: ImageMetadata(name: name, isClipboardData: false, encodedWidth: 120,
        encodedHeight: 60, orientation: 1, typeIdentifier: "public.png", byteCount: 100,
        hasAlpha: true, imageCount: 1, primaryImageIndex: 0), preview: cgImage)
}

@Test func referenceHistoryGroupsADragAndNeverTouchesMeasurementHistory() throws {
    var overlay = try ReferenceOverlay(image: referenceImage(), displaySize: display)
    let original = overlay.placement
    overlay.setPlacement(original.moved(dx: 10, dy: 5, displaySize: display), recording: false)
    overlay.setPlacement(original.moved(dx: 30, dy: 15, displaySize: display), recording: false)
    #expect(!overlay.canUndo)
    overlay.record(before: original, after: overlay.placement)
    let moved = overlay.placement
    overlay.undo(); #expect(overlay.placement == original && !overlay.canUndo && overlay.canRedo)
    overlay.redo(); #expect(overlay.placement == moved)
    overlay.undo()
    overlay.setPlacement(original.moved(dx: 1, dy: 0, displaySize: display))
    #expect(!overlay.canRedo)
    let beforeCancelled = overlay.placement
    overlay.setPlacement(original, recording: false)
    overlay.setPlacement(beforeCancelled, recording: false)
    overlay.undo(); #expect(overlay.placement == original)
}

@Test func referenceSessionsRetainTheirOwnImageAndInvalidateWithTheDisplay() throws {
    var sessions = DisplaySessions()
    let a = DisplayConfiguration(id: 1, size: display, backingFactor: 2)
    let b = DisplayConfiguration(id: 2, size: display, backingFactor: 1)
    sessions.synchronize([a, b])
    let first = sessions.activate(1, rootPixels: 16)
    var session = try #require(first)
    session.reference = try ReferenceOverlay(image: referenceImage(), displaySize: display)
    session.document.add(axis: .horizontal, position: 30)
    session.calibration.setScale(percent: 200)
    sessions.save(session)
    #expect(sessions.activate(2, rootPixels: 16)?.reference == nil)
    let restored = sessions.activate(1, rootPixels: 20)
    #expect(restored?.reference?.id == session.reference?.id)
    #expect(restored?.reference?.placement == session.reference?.placement)
    #expect(restored?.document == session.document)
    sessions.synchronize([b]); sessions.synchronize([a, b])
    #expect(sessions.activate(1, rootPixels: 16)?.reference == nil)
    #expect(DisplaySession(size: display, rootPixels: 16).reference == nil)
}

private actor ReferenceTestLoader: ImageInspecting {
    private var pending: [String: CheckedContinuation<InspectedImage, any Error>] = [:]
    func inspect(_ input: ImageInspectionInput) async throws -> InspectedImage {
        guard case .file(let url) = input else { throw ImageInspectionError.invalidImage }
        return try await withCheckedThrowingContinuation { pending[url.lastPathComponent] = $0 }
    }
    func wait(_ name: String) async { while pending[name] == nil { await Task.yield() } }
    func finish(_ name: String, result: Result<InspectedImage, any Error>) { pending.removeValue(forKey: name)?.resume(with: result) }
}

@MainActor @Test func referenceImportsRetainSuccessOnFailureAndIgnoreStaleResults() async throws {
    let loader = ReferenceTestLoader()
    let model = ReferenceOverlayModel(loader: loader)
    let original = try ReferenceOverlay(image: referenceImage(), displaySize: display)
    model.restore(original)
    let invalid = model.load(URL(fileURLWithPath: "/invalid"), displaySize: display)
    await loader.wait("invalid")
    await loader.finish("invalid", result: .failure(ImageInspectionError.invalidImage))
    await invalid.value
    #expect(model.overlay?.id == original.id && model.error != nil && !model.isLoading)
    let old = model.load(URL(fileURLWithPath: "/old"), displaySize: display)
    await loader.wait("old")
    let new = model.load(URL(fileURLWithPath: "/new"), displaySize: display)
    await loader.wait("new")
    await loader.finish("new", result: .success(try referenceImage("new.png")))
    await new.value
    await loader.finish("old", result: .success(try referenceImage("old.png")))
    await old.value
    #expect(model.overlay?.image.metadata.name == "new.png" && model.error == nil)
    let late = model.load(URL(fileURLWithPath: "/late"), displaySize: display)
    await loader.wait("late")
    model.restore(nil)
    await loader.finish("late", result: .success(try referenceImage("late.png")))
    await late.value
    #expect(model.overlay == nil && !model.isLoading && model.error == nil)
}

@MainActor @Test func cancellingReferenceLoadKeepsTheCurrentDisplayImage() async throws {
    let loader = ReferenceTestLoader()
    let model = ReferenceOverlayModel(loader: loader)
    let original = try ReferenceOverlay(image: referenceImage(), displaySize: display)
    model.restore(original)
    let task = model.load(URL(fileURLWithPath: "/cancelled"), displaySize: display)
    await loader.wait("cancelled")
    model.cancelImport()
    await loader.finish("cancelled", result: .success(try referenceImage("cancelled.png")))
    await task.value
    #expect(model.overlay?.id == original.id && !model.isLoading)
}

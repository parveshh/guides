import CoreGraphics
import Testing
@testable import GuidesCore

@Test func cornerCropMapsCircularArcToPreviewAndClampsDisplayEdges() throws {
    let display = DisplayConfiguration(id: 1, size: CGSize(width: 800, height: 600), backingFactor: 2)
    let area = AreaMeasurement(rect: CGRect(x: 100, y: 80, width: 200, height: 100), cornerRadius: 32)
    for corner in MagnifierCorner.allCases {
        for zoom: CGFloat in [4, 8, 16] {
            let request = try #require(CornerCaptureRequest(display: display, area: area, corner: corner, zoom: zoom))
            #expect(request.sourceRect.width == 256 / zoom)
            #expect(request.outputPixels == Int(512 / zoom))
            let inset = 32 * (1 - 1 / sqrt(CGFloat(2)))
            let right = corner == .topRight || corner == .bottomRight
            let bottom = corner == .bottomLeft || corner == .bottomRight
            #expect(abs(request.sourceRect.midX - (right ? 300 - inset : 100 + inset)) < 0.00001)
            #expect(abs(request.sourceRect.midY - (bottom ? 180 - inset : 80 + inset)) < 0.00001)
            let preview = request.previewRect(for: area.rect)
            #expect(abs(preview.minX - (100 - request.sourceRect.minX) * zoom) < 0.00001)
            #expect(request.previewRadius(32) == 32 * zoom)
        }
    }
    let full = AreaMeasurement(rect: CGRect(origin: .zero, size: display.size))
    for corner in MagnifierCorner.allCases {
        let request = try #require(CornerCaptureRequest(display: display, area: full, corner: corner, zoom: 8))
        #expect(CGRect(origin: .zero, size: display.size).contains(request.sourceRect))
    }
    let tiny = DisplayConfiguration(id: 2, size: CGSize(width: 10, height: 20), backingFactor: 1)
    let request = try #require(CornerCaptureRequest(display: tiny, area: AreaMeasurement(rect: CGRect(x: 0, y: 0, width: 10, height: 20)), corner: .bottomRight, zoom: 4))
    #expect(request.sourceRect == CGRect(x: 0, y: 10, width: 10, height: 10))
    #expect(request.outputPixels == 10)
    #expect(CornerCaptureRequest(display: display, area: area, corner: .topLeft, zoom: 0) == nil)
    #expect(CornerCaptureRequest(display: display, area: AreaMeasurement(rect: CGRect(x: -1, y: 0, width: 20, height: 20)), corner: .topLeft, zoom: 8) == nil)
}

@MainActor private final class PendingCapture: CornerCapturing {
    var calls: [(CornerCaptureRequest, CheckedContinuation<CGImage, any Error>)] = []
    var resets = 0
    func capture(_ request: CornerCaptureRequest) async throws -> CGImage {
        try await withCheckedThrowingContinuation { calls.append((request, $0)) }
    }
    func reset() { resets += 1 }
    func succeed() { calls.removeFirst().1.resume(returning: Self.image()) }
    func fail() { calls.removeFirst().1.resume(throwing: Failure.unavailable) }
    enum Failure: Error { case unavailable }
    static func image() -> CGImage {
        CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
}

@MainActor private func waitFor(_ predicate: () -> Bool) async throws {
    for _ in 0..<100 {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Capture state did not settle within one second")
}

@Test @MainActor func magnifierDiscardsLateFramesAndRequiresExplicitRestart() async throws {
    let source = PendingCapture()
    let controlled = CornerMagnifier(source: source)
    let display = DisplayConfiguration(id: 1, size: CGSize(width: 800, height: 600), backingFactor: 2)
    let area = AreaMeasurement(rect: CGRect(x: 100, y: 100, width: 200, height: 100), cornerRadius: 24)
    let request = try #require(CornerCaptureRequest(display: display, area: area, corner: .topLeft, zoom: 8))
    controlled.update(request)
    #expect(!controlled.isRunning && source.calls.isEmpty)
    controlled.start(request)
    try await waitFor { source.calls.count == 1 }
    controlled.stop()
    source.succeed()
    await Task.yield()
    #expect(!controlled.isRunning && controlled.image == nil && controlled.imageRequest == nil)
    controlled.start(request)
    try await waitFor { source.calls.count == 1 }
    source.succeed()
    try await waitFor { controlled.image != nil }
    #expect(controlled.imageRequest == request)
    controlled.update(nil)
    #expect(!controlled.isRunning && controlled.image == nil && source.resets >= 3)
}

@Test @MainActor func magnifierIgnoresSupersededResultsAndErrorsButStopsOnCurrentError() async throws {
    let source = PendingCapture()
    let controlled = CornerMagnifier(source: source)
    let display = DisplayConfiguration(id: 1, size: CGSize(width: 800, height: 600), backingFactor: 1)
    let area = AreaMeasurement(rect: CGRect(x: 100, y: 100, width: 200, height: 100), cornerRadius: 24)
    let first = try #require(CornerCaptureRequest(display: display, area: area, corner: .topLeft, zoom: 8))
    let second = try #require(CornerCaptureRequest(display: display, area: area, corner: .bottomRight, zoom: 16))
    controlled.start(first)
    try await waitFor { source.calls.count == 1 }
    controlled.update(second); source.succeed()
    try await waitFor { source.calls.count == 1 }
    #expect(controlled.image == nil && source.calls.first?.0 == second)
    controlled.update(first); source.fail()
    try await waitFor { source.calls.count == 1 }
    #expect(controlled.isRunning && controlled.error == nil && source.calls.first?.0 == first)
    source.fail()
    try await waitFor { !controlled.isRunning }
    #expect(controlled.error != nil && controlled.image == nil)
    controlled.start(second)
    try await waitFor { source.calls.count == 1 }
    controlled.stop(); source.fail()
    await Task.yield()
    #expect(controlled.error == nil && !controlled.isRunning)
}

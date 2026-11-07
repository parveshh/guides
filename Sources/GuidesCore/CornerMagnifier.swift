import Foundation
import CoreGraphics
import Observation

public enum MagnifierCorner: String, CaseIterable, Sendable {
    case topLeft = "Top left", topRight = "Top right", bottomLeft = "Bottom left", bottomRight = "Bottom right"
}

public struct CornerCaptureRequest: Equatable, Sendable {
    public let display: DisplayConfiguration
    public let sourceRect: CGRect
    public init?(display: DisplayConfiguration, area: AreaMeasurement, corner: MagnifierCorner, zoom: CGFloat) {
        guard [4, 8, 16].contains(zoom), display.size.width.isFinite, display.size.height.isFinite,
              display.size.width > 0, display.size.height > 0,
              display.backingFactor.isFinite, display.backingFactor > 0,
              [area.rect.minX, area.rect.minY, area.rect.width, area.rect.height, area.cornerRadius].allSatisfy(\.isFinite),
              area.rect.width > 0, area.rect.height > 0,
              area.rect.minX >= 0, area.rect.minY >= 0,
              area.rect.maxX <= display.size.width, area.rect.maxY <= display.size.height,
              area.cornerRadius >= 0, area.cornerRadius <= area.maximumRadius else { return nil }
        let edge = min(256 / zoom, min(display.size.width, display.size.height))
        // Centre on the diagonal midpoint of the circular arc, not its invisible bounding corner.
        let inset = area.cornerRadius * (1 - 1 / sqrt(2))
        let right = corner == .topRight || corner == .bottomRight
        let bottom = corner == .bottomLeft || corner == .bottomRight
        let x = right ? area.rect.maxX - inset : area.rect.minX + inset
        let y = bottom ? area.rect.maxY - inset : area.rect.minY + inset
        self.display = display
        sourceRect = CGRect(x: min(max(0, x - edge / 2), display.size.width - edge),
                            y: min(max(0, y - edge / 2), display.size.height - edge), width: edge, height: edge)
    }
    public var outputPixels: Int { Int(min(512, max(1, (sourceRect.width * display.backingFactor).rounded(.up)))) }
    public func previewRect(for area: CGRect) -> CGRect {
        let scale = 256 / sourceRect.width
        return CGRect(x: (area.minX - sourceRect.minX) * scale, y: (area.minY - sourceRect.minY) * scale,
                      width: area.width * scale, height: area.height * scale)
    }
    public func previewRadius(_ radius: CGFloat) -> CGFloat { radius * 256 / sourceRect.width }
}

@MainActor public protocol CornerCapturing {
    func capture(_ request: CornerCaptureRequest) async throws -> CGImage
    func reset()
}

@MainActor @Observable
public final class CornerMagnifier {
    public private(set) var image: CGImage?
    public private(set) var imageRequest: CornerCaptureRequest?
    public private(set) var isRunning = false
    public private(set) var error: String?
    private var request: CornerCaptureRequest?
    private var generation = UUID()
    private var revision = UUID()
    private var task: Task<Void, Never>?
    private let source: any CornerCapturing

    public init(source: any CornerCapturing) { self.source = source }
    public func update(_ request: CornerCaptureRequest?) {
        guard self.request != request else { return }
        self.request = request; revision = UUID(); image = nil; imageRequest = nil
        if request == nil { stop() }
    }
    public func start(_ request: CornerCaptureRequest) {
        stop(); update(request); error = nil; isRunning = true
        let generation = self.generation
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRunning, self.generation == generation, let request = self.request else { return }
                let revision = self.revision
                do {
                    let image = try await self.source.capture(request)
                    guard !Task.isCancelled, self.generation == generation, self.isRunning else { return }
                    if self.revision == revision { self.image = image; self.imageRequest = request }
                } catch {
                    guard !Task.isCancelled, self.generation == generation, self.isRunning else { return }
                    if self.revision == revision {
                        self.stop(); self.error = error.localizedDescription; return
                    }
                }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
    }
    public func stop() {
        generation = UUID(); revision = UUID(); task?.cancel(); task = nil
        isRunning = false; image = nil; imageRequest = nil; request = nil; error = nil
        source.reset()
    }
}

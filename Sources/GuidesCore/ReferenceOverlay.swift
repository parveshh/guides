import Foundation
import Observation

public enum ReferenceError: Error, LocalizedError {
    case dimensions, origin, opacity
    public var errorDescription: String? {
        switch self {
        case .dimensions: "Enter a width that keeps both image dimensions between 1 and 32768 screen points."
        case .origin: "Keep at least one screen point of the reference inside this display."
        case .opacity: "Choose opacity from 10% to 100%."
        }
    }
}

/// Manual screen-point placement, independent of image DPI, backing scale and measurement calibration.
public struct ReferencePlacement: Equatable, Sendable {
    public let frame: CGRect
    public let opacity: CGFloat
    public let isVisible: Bool

    public init(sourceSize: CGSize, width: CGFloat, origin: CGPoint, opacity: CGFloat = 0.5,
                isVisible: Bool = true, displaySize: CGSize) throws {
        guard sourceSize.width.isFinite, sourceSize.height.isFinite, sourceSize.width > 0, sourceSize.height > 0,
              width.isFinite, (1...32768).contains(width) else { throw ReferenceError.dimensions }
        let height = width * (sourceSize.height / sourceSize.width)
        guard height.isFinite, (1...32768).contains(height) else { throw ReferenceError.dimensions }
        guard displaySize.width.isFinite, displaySize.height.isFinite, displaySize.width >= 1, displaySize.height >= 1,
              origin.x.isFinite, origin.y.isFinite,
              (1 - width...displaySize.width - 1).contains(origin.x),
              (1 - height...displaySize.height - 1).contains(origin.y) else { throw ReferenceError.origin }
        guard opacity.isFinite, (0.1...1).contains(opacity) else { throw ReferenceError.opacity }
        frame = CGRect(origin: origin, size: CGSize(width: width, height: height))
        self.opacity = opacity; self.isVisible = isVisible
    }

    public static func fitted(sourceSize: CGSize, displaySize: CGSize) throws -> ReferencePlacement {
        let scale = min(1, min(displaySize.width * 0.8 / sourceSize.width, displaySize.height * 0.8 / sourceSize.height))
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return try ReferencePlacement(sourceSize: sourceSize, width: size.width,
            origin: CGPoint(x: (displaySize.width - size.width) / 2, y: (displaySize.height - size.height) / 2),
            displaySize: displaySize)
    }

    public func moved(dx: CGFloat, dy: CGFloat, displaySize: CGSize) -> ReferencePlacement {
        guard dx.isFinite, dy.isFinite else { return self }
        let origin = CGPoint(x: min(displaySize.width - 1, max(1 - frame.width, frame.minX + dx)),
                             y: min(displaySize.height - 1, max(1 - frame.height, frame.minY + dy)))
        return (try? ReferencePlacement(sourceSize: frame.size, width: frame.width, origin: origin,
            opacity: opacity, isVisible: isVisible, displaySize: displaySize)) ?? self
    }
}

public struct ReferenceOverlay: Sendable {
    public let id = UUID()
    public let image: InspectedImage
    public private(set) var placement: ReferencePlacement
    private var past: [ReferencePlacement] = []
    private var future: [ReferencePlacement] = []
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var sourceSize: CGSize { CGSize(width: image.metadata.width, height: image.metadata.height) }

    public init(image: InspectedImage, displaySize: CGSize) throws {
        self.image = image
        placement = try .fitted(sourceSize: CGSize(width: image.metadata.width, height: image.metadata.height), displaySize: displaySize)
    }
    public mutating func setPlacement(_ value: ReferencePlacement, recording: Bool = true) {
        if recording { record(before: placement, after: value) }
        placement = value
    }
    public mutating func record(before: ReferencePlacement, after: ReferencePlacement) {
        guard before != after else { return }
        past.append(before)
        if past.count > 100 { past.removeFirst() }
        future.removeAll()
    }
    public mutating func undo() {
        guard let value = past.popLast() else { return }
        future.append(placement); placement = value
    }
    public mutating func redo() {
        guard let value = future.popLast() else { return }
        past.append(placement); placement = value
    }
}

/// Loading can finish after hide, display switching, removal or a newer import. Only the current request publishes.
@MainActor @Observable
public final class ReferenceOverlayModel {
    public var overlay: ReferenceOverlay?
    public private(set) var isLoading = false
    public private(set) var error: String?
    public var onChange: (() -> Void)?
    private let loader: any ImageInspecting
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    public init(loader: any ImageInspecting = ImageInspectionLoader(maximumPreviewPixels: 4096)) { self.loader = loader }

    @discardableResult
    public func load(_ url: URL, displaySize: CGSize) -> Task<Void, Never> {
        cancelImport()
        let id = UUID(); requestID = id
        isLoading = true; error = nil; onChange?()
        let operation = Task { [weak self, loader] in
            do {
                let image = try await loader.inspect(.file(url))
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.overlay = try ReferenceOverlay(image: image, displaySize: displaySize)
                self.isLoading = false; self.onChange?()
            } catch {
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.error = error.localizedDescription; self.isLoading = false; self.onChange?()
            }
        }
        task = operation
        return operation
    }
    public func cancelImport() {
        task?.cancel(); task = nil; requestID = UUID(); isLoading = false
    }
    public func restore(_ value: ReferenceOverlay?) {
        cancelImport(); overlay = value; error = nil; onChange?()
    }
}

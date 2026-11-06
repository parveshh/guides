import Foundation
import Observation

public struct WindowSizeRequest: Equatable, Sendable {
    public let size: CGSize
    public init(width: String, height: String) throws {
        func dimension(_ text: String) throws -> CGFloat {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(trimmed), (1...16_384).contains(value) else {
                throw WindowResizeError.invalidSize
            }
            return CGFloat(value)
        }
        size = try CGSize(width: dimension(width), height: dimension(height))
    }

    public static func matches(_ actual: CGSize, _ requested: CGSize) -> Bool {
        abs(actual.width - requested.width) < 0.5 && abs(actual.height - requested.height) < 0.5
    }

    public static func text(_ size: CGSize) -> String {
        "\(MeasurementText.number(size.width)) × \(MeasurementText.number(size.height)) screen pt"
    }
}

public enum WindowResizeError: Error, LocalizedError, Equatable {
    case invalidSize, permissionRequired, noWindow, unsupported, staleTarget, noRestore
    case system(Int32)
    public var errorDescription: String? {
        switch self {
        case .invalidSize: "Enter whole-number dimensions from 1 to 16384 screen points."
        case .permissionRequired: "Enable Guides in System Settings → Privacy & Security → Accessibility, then check access."
        case .noWindow: "No front window is available. Open a normal window in the selected app, then use its front window."
        case .unsupported: "This window cannot be resized. Exit full screen or minimised mode and choose a normal resizable window."
        case .staleTarget: "The selected window is no longer available. Choose its front window again."
        case .noRestore: "There is no previous frame to restore for this window."
        case .system(let code): "The app did not complete the window request (\(code)). Check the window and try again."
        }
    }
}

public struct ResizeTarget: Sendable, Equatable {
    public let id: UUID
    public let applicationName: String
    public let title: String
    public var frame: CGRect
    public init(id: UUID, applicationName: String, title: String, frame: CGRect) {
        self.id = id; self.applicationName = applicationName; self.title = title; self.frame = frame
    }
}

public struct WindowResizeResult: Sendable {
    /// Nil means a write was attempted but its final frame could not be read.
    public let frame: CGRect?
    public let canRestore: Bool
    public let message: String
    public init(frame: CGRect?, canRestore: Bool, message: String) {
        self.frame = frame; self.canRestore = canRestore; self.message = message
    }
}

public protocol WindowResizing: Sendable {
    func capture(processID: Int32, applicationName: String) async throws -> ResizeTarget
    func resize(targetID: UUID, request: WindowSizeRequest) async throws -> WindowResizeResult
    func restore(targetID: UUID) async throws -> WindowResizeResult
}

@MainActor @Observable
public final class WindowResizeModel {
    public var width = "2560"
    public var height = "1440"
    public private(set) var target: ResizeTarget?
    public private(set) var isBusy = false
    public private(set) var canRestore = false
    public private(set) var frameIsKnown = false
    public private(set) var message: String?
    private let service: any WindowResizing
    private var operation: Task<Void, Never>?
    private var generation = UUID()

    public init(service: any WindowResizing) { self.service = service }

    @discardableResult
    public func capture(processID: Int32, applicationName: String) -> Task<Void, Never>? {
        guard !isBusy else { return nil }
        target = nil; canRestore = false; frameIsKnown = false
        return run { [service] in
            let target = try await service.capture(processID: processID, applicationName: applicationName)
            return (target, nil)
        }
    }

    @discardableResult
    public func resize() -> Task<Void, Never>? {
        guard !isBusy, let target else { return nil }
        do {
            let request = try WindowSizeRequest(width: width, height: height)
            return run { [service] in (target, try await service.resize(targetID: target.id, request: request)) }
        } catch { message = error.localizedDescription; return nil }
    }

    @discardableResult
    public func restore() -> Task<Void, Never>? {
        guard !isBusy, canRestore, let target else { return nil }
        return run { [service] in (target, try await service.restore(targetID: target.id)) }
    }

    public func clear() {
        generation = UUID(); operation?.cancel(); operation = nil
        target = nil; isBusy = false; canRestore = false; frameIsKnown = false; message = nil
    }

    private func run(_ action: @escaping @Sendable () async throws -> (ResizeTarget, WindowResizeResult?)) -> Task<Void, Never> {
        let id = UUID(); generation = id
        isBusy = true; message = nil
        let task = Task { [weak self] in
            do {
                let (target, result) = try await action()
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.target = target
                if let result {
                    if let frame = result.frame { self.target?.frame = frame }
                    self.frameIsKnown = result.frame != nil
                    self.canRestore = result.canRestore
                    self.message = result.message
                } else { self.frameIsKnown = true }
                self.isBusy = false
            } catch {
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.message = error.localizedDescription
                self.isBusy = false
            }
        }
        operation = task
        return task
    }
}

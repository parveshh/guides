import Foundation
import Observation

public protocol ImageInspecting: Sendable {
    func inspect(_ input: ImageInspectionInput) async throws -> InspectedImage
}

@MainActor @Observable
public final class ImageInspectorModel {
    public private(set) var image: InspectedImage?
    public private(set) var isLoading = false
    public private(set) var error: String?
    public var isDropTarget = false
    private let loader: any ImageInspecting

    public init(loader: any ImageInspecting = ImageInspectionLoader()) { self.loader = loader }
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    @discardableResult
    public func load(_ input: ImageInspectionInput) -> Task<Void, Never> {
        task?.cancel()
        let id = UUID()
        requestID = id
        isLoading = true
        error = nil
        let operation = Task { [weak self, loader] in
            do {
                let result = try await loader.inspect(input)
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.image = result
                self.isLoading = false
            } catch {
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
        task = operation
        return operation
    }

    public func rejectImport(_ message: String) {
        task?.cancel()
        task = nil
        requestID = UUID()
        isLoading = false
        error = message
    }

    public func clear() {
        task?.cancel()
        task = nil
        requestID = UUID()
        image = nil
        error = nil
        isLoading = false
        isDropTarget = false
    }
}

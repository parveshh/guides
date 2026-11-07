import AppKit
import GuidesCore
@preconcurrency import ScreenCaptureKit

@MainActor
final class CornerCaptureService: CornerCapturing {
    private var filter: SCContentFilter?
    private var display: DisplayConfiguration?
    private var generation = UUID()
    static var hasAccess: Bool { CGPreflightScreenCaptureAccess() }
    // Called only by the dedicated permission button, never by capture/startup.
    static func requestAccess() { CGRequestScreenCaptureAccess() }

    func reset() { generation = UUID(); filter = nil; display = nil }

    func capture(_ request: CornerCaptureRequest) async throws -> CGImage {
        guard Self.hasAccess else { throw CaptureError.access }
        let generation = self.generation
        let filter: SCContentFilter
        if display == request.display, let existing = self.filter { filter = existing }
        else {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            guard generation == self.generation else { throw CancellationError() }
            guard let display = content.displays.first(where: { $0.displayID == request.display.id }),
                  display.frame.size == request.display.size else { throw CaptureError.display }
            guard let ownApp = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else { throw CaptureError.filter }
            filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
            self.filter = filter; self.display = request.display
        }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = request.sourceRect
        configuration.width = request.outputPixels; configuration.height = request.outputPixels
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let result = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        guard generation == self.generation else { throw CancellationError() }
        return result
    }

    private enum CaptureError: Error, LocalizedError {
        case access, display, filter
        var errorDescription: String? {
            switch self {
            case .access: "Allow Screen Recording for Guides, then Check Access. A relaunch may be needed. Measurement still works without access."
            case .display: "The display changed. Close the magnifier and reopen it on the intended display."
            case .filter: "Guides could not exclude its own windows. Close and reopen the magnifier."
            }
        }
    }
}

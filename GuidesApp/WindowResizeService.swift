import ApplicationServices
import Foundation
import GuidesCore

/// Owns AX objects on a serial actor; potentially slow IPC never runs on the UI actor.
actor WindowResizeService: WindowResizing {
    private var window: AXUIElement?
    private var targetID: UUID?
    private var previousFrame: CGRect?

    func capture(processID: Int32, applicationName: String) throws -> ResizeTarget {
        try Task.checkCancellation()
        window = nil; targetID = nil; previousFrame = nil
        try checkAccess()
        guard processID != ProcessInfo.processInfo.processIdentifier else { throw WindowResizeError.noWindow }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 1)
        guard let value = try? attribute(application, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { throw WindowResizeError.noWindow }
        let candidate = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(candidate, 1)
        try checkResizable(candidate)
        let frame = try frame(of: candidate)
        let title = (try? attribute(candidate, kAXTitleAttribute)) as? String ?? "Untitled window"
        try Task.checkCancellation()
        let id = UUID()
        window = candidate; targetID = id
        return ResizeTarget(id: id, applicationName: applicationName, title: title, frame: frame)
    }

    func resize(targetID: UUID, request: WindowSizeRequest) async throws -> WindowResizeResult {
        let window = try currentWindow(targetID)
        try checkResizable(window)
        let original = try frame(of: window)
        var size = request.size
        guard let value = AXValueCreate(.cgSize, &size) else { throw WindowResizeError.invalidSize }
        try Task.checkCancellation()
        // Preserve recovery even when a remote app changes its window then times out.
        previousFrame = original
        let error = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        try? await Task.sleep(for: .milliseconds(200))
        guard self.targetID == targetID else { throw WindowResizeError.staleTarget }
        let actual = try? frame(of: window)
        let message: String
        if error != .success {
            message = "Resize was not confirmed (\(error.rawValue)). Check the actual size or use Restore."
        } else if let actual, WindowSizeRequest.matches(actual.size, request.size) {
            message = "Window resized to \(WindowSizeRequest.text(actual.size))."
        } else if let actual {
            message = "Requested \(WindowSizeRequest.text(request.size)); the app accepted \(WindowSizeRequest.text(actual.size)). App or display limits may constrain it."
        } else {
            message = "Resize was sent, but the actual size could not be read. Use its front window again to check, or try Restore."
        }
        return WindowResizeResult(frame: actual, canRestore: true, message: message)
    }

    func restore(targetID: UUID) async throws -> WindowResizeResult {
        let window = try currentWindow(targetID)
        guard let saved = previousFrame else { throw WindowResizeError.noRestore }
        try checkResizable(window)
        try requireSettable(window, kAXPositionAttribute)
        var size = saved.size
        var origin = saved.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let pointValue = AXValueCreate(.cgPoint, &origin) else {
            throw WindowResizeError.noRestore
        }
        try Task.checkCancellation()
        let sizeError = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        // Finder applies size asynchronously. An immediate position write can
        // reapply the old size. Wait for size to settle before restoring position.
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(200))
            guard self.targetID == targetID else { throw WindowResizeError.staleTarget }
            if let resized = try? frame(of: window), WindowSizeRequest.matches(resized.size, saved.size) { break }
        }
        try Task.checkCancellation()
        let positionError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        try? await Task.sleep(for: .milliseconds(200))
        guard self.targetID == targetID else { throw WindowResizeError.staleTarget }
        let actual = try? frame(of: window)
        let restored = actual.map {
            WindowSizeRequest.matches($0.size, saved.size) && abs($0.minX - saved.minX) < 0.5 && abs($0.minY - saved.minY) < 0.5
        } ?? false
        let confirmed = restored && sizeError == .success && positionError == .success
        if confirmed { previousFrame = nil }
        return WindowResizeResult(frame: actual, canRestore: !confirmed,
            message: confirmed ? "Previous window size and position restored." : "The app did not confirm the full restore. Check its actual size and position; Restore remains available.")
    }

    private func currentWindow(_ id: UUID) throws -> AXUIElement {
        try Task.checkCancellation()
        try checkAccess()
        guard targetID == id, let window else { throw WindowResizeError.staleTarget }
        return window
    }

    private func checkAccess() throws {
        guard AXIsProcessTrusted() else { throw WindowResizeError.permissionRequired }
    }

    private func checkResizable(_ window: AXUIElement) throws {
        guard (try attribute(window, kAXSubroleAttribute) as? String) == (kAXStandardWindowSubrole as String),
              (try? attribute(window, kAXMinimizedAttribute) as? Bool) != true else { throw WindowResizeError.unsupported }
        try requireSettable(window, kAXSizeAttribute)
        // Position is needed to restore any automatic repositioning caused by resizing.
        try requireSettable(window, kAXPositionAttribute)
    }

    private func requireSettable(_ window: AXUIElement, _ name: String) throws {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(window, name as CFString, &settable)
        guard error == .success, settable.boolValue else { throw WindowResizeError.unsupported }
    }

    private func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success, let value else {
            if error == .invalidUIElement { throw WindowResizeError.staleTarget }
            throw WindowResizeError.system(error.rawValue)
        }
        return value
    }

    private func frame(of window: AXUIElement) throws -> CGRect {
        let positionValue = try attribute(window, kAXPositionAttribute)
        let sizeValue = try attribute(window, kAXSizeAttribute)
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            throw WindowResizeError.unsupported
        }
        let position = unsafeDowncast(positionValue, to: AXValue.self)
        let dimensions = unsafeDowncast(sizeValue, to: AXValue.self)
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(position) == .cgPoint, AXValueGetType(dimensions) == .cgSize,
              AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(dimensions, .cgSize, &size),
              origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { throw WindowResizeError.unsupported }
        return CGRect(origin: origin, size: size)
    }
}

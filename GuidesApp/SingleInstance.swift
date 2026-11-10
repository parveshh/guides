import AppKit
import GuidesCore

/// All copies share one per-user lease, independently of the CLI protocol or app location.
@MainActor
enum SingleInstance {
    private static let bundleIdentifier = "dev.guides.local"

    static func runningApplication() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != getpid() && !$0.isTerminated && $0.isFinishedLaunching
                && kill($0.processIdentifier, 0) == 0 }
            .sorted { $0.processIdentifier < $1.processIdentifier }.first
    }

    static func acquire() throws -> InstanceLease? {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("Guides", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let lease = try InstanceLease(at: directory.appendingPathComponent("instance-\(getuid()).lock")) else {
            _ = runningApplication()?.activate(options: [])
            return nil
        }
        // Older builds have no lease. Respect an already-launched copy instead of adding another UI.
        if let existing = runningApplication() {
            _ = existing.activate(options: [])
            return nil
        }
        return lease
    }

    static func launch() throws -> [String: Any] {
        let existing = runningApplication()
        if let existing, ready(existing) { return description(existing, alreadyRunning: true) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = true
        let completion = LaunchCompletion()
        if existing == nil {
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
                completion.finish(error: error?.localizedDescription)
            }
        }
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if let running = runningApplication(), ready(running) {
                return description(running, alreadyRunning: existing != nil)
            }
            if let error = completion.error { throw CommandLineError(error) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        throw CommandLineError("Guides has not finished launching or its command channel is unavailable. The execution sandbox may block local Mach IPC; use the normal command-approval path. Check status before retrying; do not start another copy.")
    }

    private static func ready(_ application: NSRunningApplication) -> Bool {
        // Legacy builds without a CLI can still be reused for computer use.
        let protocolVersion = application.bundleURL.flatMap { Bundle(url: $0) }?
            .object(forInfoDictionaryKey: "GuidesCommandProtocol") as? NSNumber
        return protocolVersion?.intValue != 1 || CommandChannel.isReady(processIdentifier: application.processIdentifier)
    }

    private static func description(_ application: NSRunningApplication, alreadyRunning: Bool) -> [String: Any] {
        ["ok": true, "pid": application.processIdentifier, "appPath": application.bundleURL?.path ?? "",
         "alreadyRunning": alreadyRunning]
    }
}

/// Only a copied error string crosses NSWorkspace's concurrent completion queue.
private final class LaunchCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var failure: String?
    var error: String? { lock.withLock { failure } }
    func finish(error: String?) { lock.withLock { failure = error } }
}

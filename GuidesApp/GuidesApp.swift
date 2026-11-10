import AppKit
import Darwin
import GuidesCore

@main
@MainActor
enum GuidesApp {
    static func main() {
        if CommandLine.arguments.dropFirst().first == "--cli" {
            exit(CommandChannel.runClient(arguments: Array(CommandLine.arguments.dropFirst(2))))
        }
        do {
            guard let lease = try SingleInstance.acquire() else { return }
            withExtendedLifetime(lease) {
                let application = NSApplication.shared
                let controller = AppController()
                application.delegate = controller
                withExtendedLifetime(controller) { application.run() }
            }
        } catch {
            FileHandle.standardError.write(Data("Guides could not establish single-instance ownership: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

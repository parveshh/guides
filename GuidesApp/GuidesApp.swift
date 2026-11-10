import AppKit
import Darwin

@main
@MainActor
enum GuidesApp {
    static func main() {
        if CommandLine.arguments.dropFirst().first == "--cli" {
            exit(CommandChannel.runClient(arguments: Array(CommandLine.arguments.dropFirst(2))))
        }
        let application = NSApplication.shared
        let controller = AppController()
        application.delegate = controller
        withExtendedLifetime(controller) { application.run() }
    }
}

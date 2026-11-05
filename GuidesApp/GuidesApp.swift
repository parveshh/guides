import AppKit

@main
@MainActor
enum GuidesApp {
    static func main() {
        let application = NSApplication.shared
        let controller = AppController()
        application.delegate = controller
        withExtendedLifetime(controller) { application.run() }
    }
}

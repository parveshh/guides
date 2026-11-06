import Foundation

enum PreferenceMigration {
    /// The optional Accessibility tool requires leaving App Sandbox. Preserve only
    /// our known local preferences, without overwriting values in the new domain.
    static func importSandboxSettings() {
        let defaults = UserDefaults.standard
        let marker = "importedSandboxSettings"
        guard !defaults.bool(forKey: marker), let identifier = Bundle.main.bundleIdentifier else { return }
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(identifier)/Data/Library/Preferences/\(identifier).plist")
        if let data = try? Data(contentsOf: file),
           let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for key in ["rootFontSize", "rulerAppearance", "KeyboardShortcuts_editGuides"] where defaults.object(forKey: key) == nil {
                if let value = values[key] { defaults.set(value, forKey: key) }
            }
        }
        defaults.set(true, forKey: marker)
    }
}

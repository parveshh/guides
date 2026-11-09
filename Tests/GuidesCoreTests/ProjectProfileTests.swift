import Foundation
import CoreGraphics
import Testing
@testable import GuidesCore

private func temporaryProfiles() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("guides-profile-test-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("profiles.json")
}

private func profileContent(root: CGFloat = 20, source: String = SpacingScale.example, tolerance: String = "0.5") throws -> ProjectProfileContent {
    try ProjectProfileContent(rootPixels: root, spacingScale: SpacingScale(source: source, tolerance: tolerance))
}

@MainActor private func temporaryPreferences() -> (GuidesPreferences, () -> Void) {
    let suite = "dev.guides.profile-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    return (GuidesPreferences(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
}

@Test func profileContentRoundTripsAndRejectsInvalidRootSizes() throws {
    let content = try profileContent()
    let decoded = try JSONDecoder().decode(ProjectProfileContent.self, from: JSONEncoder().encode(content))
    #expect(decoded == content)
    #expect(try decoded.spacingScale() == SpacingScale(source: SpacingScale.example, tolerance: "0.5"))
    #expect(content.summary == "20px root · 6 spacing tokens · 0.5px tolerance")
    #expect(try profileContent(root: 10.5, source: "--gap: 8px", tolerance: "1").summary == "10.5px root · 1 spacing token · 1px tolerance")
    for root in [0, -16, CGFloat.infinity, .nan] {
        #expect(throws: ProfileError.self) { try profileContent(root: root) }
    }
}

@Test @MainActor func profileLibrarySavesRenamesDeletesAndRecoversAcrossFreshStores() throws {
    let url = try temporaryProfiles()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = ProjectProfilesStore(fileURL: url)
    #expect(store.storageError == nil && store.profiles.isEmpty)
    let content = try profileContent()
    let id = try store.save(name: "  Shop  ", content: content)
    #expect(store.profiles[0].name == "Shop")
    let second = try store.save(name: "Admin", content: try profileContent(root: 16, source: "", tolerance: "1"))
    try store.rename(id, to: "SHOP")
    #expect(store.profiles[0].id == id && store.profiles[0].content == content)
    #expect(throws: ProfileError.self) { try store.rename(second, to: "shop") }
    let bytes = try Data(contentsOf: url)
    for badName in [" ", "A\nB", "A\u{7}B", String(repeating: "x", count: 81), "shop"] {
        #expect(throws: ProfileError.self) { try store.save(name: badName, content: content) }
        #expect(try Data(contentsOf: url) == bytes)
    }
    try store.delete(id)
    #expect(store.profiles.map(\.id) == [second] && store.canUndoDelete)
    #expect(try store.undoDelete() == id)
    #expect(store.profiles.map(\.id) == [id, second] && !store.canUndoDelete)
    let relaunched = ProjectProfilesStore(fileURL: url)
    #expect(relaunched.profiles == store.profiles && !relaunched.canUndoDelete && !relaunched.canUndoApply)
    try store.delete(id)
    _ = try store.save(name: "shop", content: content)
    #expect(throws: ProfileError.self) { try store.undoDelete() }
    #expect(store.canUndoDelete)
    #expect(throws: ProfileError.self) { try store.rename(UUID(), to: "Missing") }
}

@Test @MainActor func applyingAProfileReplacesBothSettingsAndUndoRestoresThem() throws {
    let url = try temporaryProfiles()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let (preferences, cleanUp) = temporaryPreferences()
    defer { cleanUp() }
    let original = try SpacingScale(source: "--old: 3px;", tolerance: "2")
    preferences.setRootPixels(18)
    preferences.setSpacingScale(original)
    let store = ProjectProfilesStore(fileURL: url)
    let content = try profileContent()
    let id = try store.save(name: "Shop", content: content)
    #expect(try ProjectProfileContent(preferences: preferences) != content)
    #expect(throws: ProfileError.self) { try store.undoApply(to: preferences) }
    #expect(throws: ProfileError.self) { try store.apply(UUID(), to: preferences) }
    #expect(preferences.rootPixels == 18 && preferences.spacingScale == original && !store.canUndoApply)

    var roots: [CGFloat] = [], scales: [SpacingScale] = []
    preferences.onRootChange = { roots.append($0) }
    preferences.onSpacingScaleChange = { scales.append($0) }
    try store.apply(id, to: preferences)
    let applied = try content.spacingScale()
    #expect(preferences.rootPixels == 20 && preferences.spacingScale == applied)
    #expect(roots == [20] && scales.count == 1 && store.canUndoApply)
    #expect(try ProjectProfileContent(preferences: preferences) == content)
    // Saving is a snapshot; applying never rewrites the library.
    #expect(ProjectProfilesStore(fileURL: url).profiles == store.profiles)

    try store.delete(id)
    try store.undoApply(to: preferences)
    #expect(preferences.rootPixels == 18 && preferences.spacingScale == original && !store.canUndoApply)
    #expect(throws: ProfileError.self) { try store.undoApply(to: preferences) }
}

@Test @MainActor func unreadableCorruptFutureAndOversizedProfileLibrariesAreRetainedAndBlockWrites() throws {
    let url = try temporaryProfiles()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let content = try profileContent()
    for bytes in [Data("corrupt".utf8), Data("{\"version\":2,\"profiles\":[]}".utf8), Data(repeating: 32, count: ProjectProfilesStore.maximumBytes + 1)] {
        try bytes.write(to: url)
        let store = ProjectProfilesStore(fileURL: url)
        #expect(store.storageError != nil && store.profiles.isEmpty)
        #expect(throws: ProfileError.self) { try store.save(name: "Do not overwrite", content: content) }
        #expect(try Data(contentsOf: url) == bytes)
        try FileManager.default.removeItem(at: url)
        store.reload()
        #expect(store.storageError == nil)
        _ = try store.save(name: "Retry works", content: content)
    }
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    #expect(ProjectProfilesStore(fileURL: url).storageError != nil)
}

@Test @MainActor func invalidProfileArchiveContentsFailAsAWhole() throws {
    let url = try temporaryProfiles()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let good = ProjectProfile(id: UUID(), name: "One", content: try profileContent())
    func altered(_ change: (inout [String: Any]) -> Void) throws -> ProjectProfile {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(good.content)) as! [String: Any]
        change(&object)
        let content = try JSONDecoder().decode(ProjectProfileContent.self, from: JSONSerialization.data(withJSONObject: object))
        return ProjectProfile(id: UUID(), name: "Two", content: content)
    }
    let duplicateName = ProjectProfile(id: UUID(), name: "ONE", content: good.content)
    let candidates = [
        [good, try altered { $0["rootPixels"] = 0 }],
        [good, try altered { $0["spacingSource"] = "--bad: 8rem;" }],
        [good, try altered { $0["spacingTolerance"] = "101" }],
        [good, good], [good, duplicateName],
        (0...50).map { ProjectProfile(id: UUID(), name: "Profile \($0)", content: good.content) }
    ]
    for items in candidates {
        let bytes = try JSONEncoder().encode(ProjectProfilesStore.Archive(version: 1, profiles: items))
        try bytes.write(to: url)
        let store = ProjectProfilesStore(fileURL: url)
        #expect(store.storageError != nil && store.profiles.isEmpty)
        #expect(try Data(contentsOf: url) == bytes)
    }
}

@Test @MainActor func failedProfileWritesLeaveLibraryAndDeleteRecoveryUnchanged() throws {
    let url = try temporaryProfiles()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = ProjectProfilesStore(fileURL: url)
    let id = try store.save(name: "Keep", content: profileContent())
    let original = store.profiles
    // A directory at the destination reliably fails even when the test process can bypass file permissions.
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    #expect(throws: (any Error).self) { try store.rename(id, to: "Failed") }
    #expect(throws: (any Error).self) { try store.delete(id) }
    #expect(store.profiles == original && !store.canUndoDelete)
}

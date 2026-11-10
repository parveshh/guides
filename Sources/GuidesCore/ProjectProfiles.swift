import Foundation
import Observation

public enum ProfileError: Error, LocalizedError {
    case invalid, version, name, duplicate, limit, missing, noRecovery
    public var errorDescription: String? {
        switch self {
        case .invalid: "The profile library contains invalid or unsupported content. Its file has been retained."
        case .version: "This profile library needs a newer version of Guides. Its file has been retained."
        case .name: "Use a name of 1–80 characters, without line breaks or control characters."
        case .duplicate: "A profile already has that name. Choose a unique name."
        case .limit: "Keep at most 50 profiles within a 2 MiB library."
        case .missing: "That profile is no longer available. Select another profile."
        case .noRecovery: "There is no profile apply to undo."
        }
    }
}

/// A versioned file representation of the project settings a profile applies. Later slices extend it.
public struct ProjectProfileContent: Codable, Equatable, Sendable {
    public let rootPixels: CGFloat
    let spacingSource: String
    let spacingTolerance: String
    /// Added in archive version 2. A version 1 profile was saved without breakpoints and reads as none.
    let breakpointSource: String

    public init(rootPixels: CGFloat, spacingScale: SpacingScale, breakpoints: BreakpointSet = .empty) throws {
        self.rootPixels = rootPixels
        spacingSource = spacingScale.source; spacingTolerance = spacingScale.toleranceText
        breakpointSource = breakpoints.source
        _ = try self.spacingScale()
    }

    @MainActor public init(preferences: GuidesPreferences) throws {
        try self.init(rootPixels: preferences.rootPixels, spacingScale: preferences.spacingScale,
                      breakpoints: preferences.breakpoints)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rootPixels = try container.decode(CGFloat.self, forKey: .rootPixels)
        spacingSource = try container.decode(String.self, forKey: .spacingSource)
        spacingTolerance = try container.decode(String.self, forKey: .spacingTolerance)
        breakpointSource = try container.decodeIfPresent(String.self, forKey: .breakpointSource) ?? ""
    }

    /// Validation precedes use so a corrupt profile can never reach preferences.
    public func spacingScale() throws -> SpacingScale {
        guard rootPixels.isFinite, rootPixels > 0,
              let scale = try? SpacingScale(source: spacingSource, tolerance: spacingTolerance) else { throw ProfileError.invalid }
        return scale
    }

    public func breakpoints() throws -> BreakpointSet {
        guard let set = try? BreakpointSet(source: breakpointSource) else { throw ProfileError.invalid }
        return set
    }

    public var summary: String {
        let count = (try? spacingScale().tokens.count) ?? 0
        let breakpoints = (try? self.breakpoints().summary) ?? "0 breakpoints"
        return "\(MeasurementText.number(rootPixels, decimals: 4))px root · \(count) spacing token\(count == 1 ? "" : "s") · \(spacingTolerance.trimmingCharacters(in: .whitespacesAndNewlines))px tolerance · \(breakpoints)"
    }
}

public struct ProjectProfile: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let content: ProjectProfileContent
}

@MainActor @Observable
public final class ProjectProfilesStore {
    struct Archive: Codable { let version: Int; let profiles: [ProjectProfile] }
    public static let maximumBytes = 2 * 1024 * 1024
    /// Version 2 adds breakpoints. Version 1 libraries are read and rewritten as version 2 on the next change.
    static let version = 2
    public let fileURL: URL
    public private(set) var profiles: [ProjectProfile] = []
    public private(set) var storageError: String?
    private var deleted: (index: Int, profile: ProjectProfile)?
    private var beforeApply: ProjectProfileContent?
    public var canUndoDelete: Bool { deleted != nil && storageError == nil }
    public var canUndoApply: Bool { beforeApply != nil }

    public init(fileURL: URL) { self.fileURL = fileURL; reload() }

    public func reload() {
        do {
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path) }
            catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                profiles = []; storageError = nil; deleted = nil
                return
            }
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ProfileError.invalid }
            guard let bytes = attributes[.size] as? NSNumber, bytes.intValue <= Self.maximumBytes else { throw ProfileError.limit }
            let data = try Data(contentsOf: fileURL)
            guard data.count <= Self.maximumBytes else { throw ProfileError.limit }
            struct Header: Decodable { let version: Int }
            guard (1...Self.version).contains(try JSONDecoder().decode(Header.self, from: data).version) else { throw ProfileError.version }
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            try validate(archive.profiles)
            profiles = archive.profiles; storageError = nil; deleted = nil
        } catch {
            profiles = []; deleted = nil
            storageError = "Could not read project profiles. No files were changed. \(error.localizedDescription)"
        }
    }

    @discardableResult public func save(name: String, content: ProjectProfileContent) throws -> UUID {
        let item = ProjectProfile(id: UUID(), name: try Self.normalizedName(name), content: content)
        try persist(profiles + [item])
        return item.id
    }
    public func rename(_ id: UUID, to name: String) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.missing }
        var updated = profiles
        updated[index].name = try Self.normalizedName(name)
        try persist(updated)
    }
    public func delete(_ id: UUID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.missing }
        var updated = profiles
        let removed = updated.remove(at: index)
        try persist(updated)
        deleted = (index, removed)
    }
    @discardableResult public func undoDelete() throws -> UUID {
        guard let deleted else { throw ProfileError.missing }
        var updated = profiles
        updated.insert(deleted.profile, at: min(deleted.index, updated.count))
        try persist(updated)
        self.deleted = nil
        return deleted.profile.id
    }

    /// Replaces the rem base, spacing scale and breakpoints together, keeping one recovery point for this run.
    public func apply(_ id: UUID, to preferences: GuidesPreferences) throws {
        guard let profile = profiles.first(where: { $0.id == id }) else { throw ProfileError.missing }
        let previous = try ProjectProfileContent(preferences: preferences)
        try Self.write(profile.content, to: preferences)
        beforeApply = previous
    }
    public func undoApply(to preferences: GuidesPreferences) throws {
        guard let beforeApply else { throw ProfileError.noRecovery }
        try Self.write(beforeApply, to: preferences)
        self.beforeApply = nil
    }
    private static func write(_ content: ProjectProfileContent, to preferences: GuidesPreferences) throws {
        let scale = try content.spacingScale()
        let breakpoints = try content.breakpoints()
        guard preferences.setRootPixels(content.rootPixels) else { throw ProfileError.invalid }
        preferences.setSpacingScale(scale)
        preferences.setBreakpoints(breakpoints)
    }

    static func normalizedName(_ name: String) throws -> String {
        do { return try SavedLayoutsStore.normalizedName(name) } catch { throw ProfileError.name }
    }
    private func validate(_ items: [ProjectProfile]) throws {
        guard items.count <= 50 else { throw ProfileError.limit }
        guard Set(items.map(\.id)).count == items.count else { throw ProfileError.invalid }
        var names = Set<String>()
        for item in items {
            guard try Self.normalizedName(item.name) == item.name else { throw ProfileError.name }
            guard names.insert(item.name.lowercased()).inserted else { throw ProfileError.duplicate }
            _ = try item.content.spacingScale()
            _ = try item.content.breakpoints()
        }
    }
    private func persist(_ updated: [ProjectProfile]) throws {
        guard storageError == nil else { throw ProfileError.invalid }
        try validate(updated)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Archive(version: Self.version, profiles: updated))
        guard data.count <= Self.maximumBytes else { throw ProfileError.limit }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        profiles = updated
    }
}

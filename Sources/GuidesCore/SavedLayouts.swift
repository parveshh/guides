import Foundation
import Observation

public enum LayoutError: Error, LocalizedError {
    case invalid, version, name, duplicate, limit, display, unavailable, noRecovery
    public var errorDescription: String? {
        switch self {
        case .invalid: "The layout library contains invalid or unsupported content. Its file has been retained."
        case .version: "This layout library needs a newer version of Guides. Its file has been retained."
        case .name: "Use a name of 1–80 characters, without line breaks or control characters."
        case .duplicate: "A layout already has that name. Choose a unique name."
        case .limit: "Keep at most 100 layouts, 1000 guides and 1000 annotations per layout, within an 8 MiB library."
        case .display: "This layout requires the same display size in screen points and backing factor."
        case .unavailable: "The active display changed. Close Saved Layouts and reopen it on the intended display."
        case .noRecovery: "There is no layout load to undo on this display."
        }
    }
}

/// A versioned file representation, independent of selection, history, calibration and reference files.
public struct SavedLayoutContent: Codable, Equatable, Sendable {
    struct GuideRecord: Codable, Equatable, Sendable { let axis: String; let position: CGFloat }
    struct StyleRecord: Codable, Equatable, Sendable {
        let color: String; let stroke: Int
        init(_ style: AnnotationStyle) { color = style.color.rawValue; stroke = style.stroke.rawValue }
        func value() throws -> AnnotationStyle {
            guard let color = AnnotationColor(rawValue: color), let stroke = AnnotationStroke(rawValue: stroke) else { throw LayoutError.invalid }
            return AnnotationStyle(color: color, stroke: stroke)
        }
    }
    struct ShapeRecord: Codable, Equatable, Sendable {
        let kind: String; let start: CGPoint; let end: CGPoint; let style: StyleRecord
    }
    struct GridRecord: Codable, Equatable, Sendable {
        let enabled: Bool; let spacing: CGFloat; let unit: String; let origin: CGPoint; let opacity: CGFloat
    }
    public let size: CGSize
    public let backingFactor: CGFloat
    let guides: [GuideRecord]
    let area: CGRect?
    let grid: GridRecord
    let shapes: [ShapeRecord]
    let spotlightIndex: Int?
    let dimOpacity: CGFloat
    let style: StyleRecord
    let newRectanglesSpotlight: Bool

    public var summary: String {
        "\(MeasurementText.number(size.width)) × \(MeasurementText.number(size.height)) screen pt · \(MeasurementText.number(backingFactor))× backing · \(guides.count) guides · \(area == nil ? 0 : 1) Area · \(shapes.count) annotations · grid \(grid.enabled ? "on" : "off")"
    }

    public init(session: DisplaySession, backingFactor: CGFloat) throws {
        size = session.document.size; self.backingFactor = backingFactor
        guides = session.document.guides.map { GuideRecord(axis: $0.axis.rawValue, position: $0.position) }
        area = session.document.area?.rect
        let g = session.grid
        grid = GridRecord(enabled: g.isEnabled, spacing: g.spacing, unit: g.unit.rawValue, origin: g.origin, opacity: g.opacity)
        shapes = session.annotations.document.shapes.map { ShapeRecord(kind: $0.kind.rawValue, start: $0.start, end: $0.end, style: StyleRecord($0.style)) }
        spotlightIndex = session.annotations.document.shapes.firstIndex { $0.id == session.annotations.document.spotlightID }
        dimOpacity = session.annotations.document.dimOpacity
        style = StyleRecord(session.annotations.style)
        newRectanglesSpotlight = session.annotations.newRectanglesSpotlight
        guard session.annotations.document.size == size else { throw LayoutError.invalid }
        _ = try restoredSession(rootPixels: session.calibration.rootPixels)
    }

    public func isCompatible(with display: DisplayConfiguration) -> Bool { size == display.size && backingFactor == display.backingFactor }

    /// Validation precedes construction so domain methods never silently clamp corrupt saved geometry.
    public func restoredSession(rootPixels: CGFloat) throws -> DisplaySession {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              size.width <= 100_000, size.height <= 100_000,
              backingFactor.isFinite, backingFactor > 0, backingFactor <= 16,
              dimOpacity.isFinite, (0...0.8).contains(dimOpacity) else { throw LayoutError.invalid }
        guard guides.count <= 1000, shapes.count <= 1000 else { throw LayoutError.limit }
        func contains(_ point: CGPoint) -> Bool {
            point.x.isFinite && point.y.isFinite && (0...size.width).contains(point.x) && (0...size.height).contains(point.y)
        }
        var result = DisplaySession(size: size, rootPixels: rootPixels)
        for guide in guides {
            guard let axis = GuideAxis(rawValue: guide.axis), guide.position.isFinite,
                  (0...(axis == .horizontal ? size.height : size.width)).contains(guide.position) else { throw LayoutError.invalid }
            result.document.add(axis: axis, position: guide.position)
        }
        if let area {
            guard area.size.width.isFinite, area.size.height.isFinite, area.size.width > 0, area.size.height > 0,
                  contains(area.origin), contains(CGPoint(x: area.maxX, y: area.maxY)) else { throw LayoutError.invalid }
            result.document.setArea(area)
        }
        result.document.select([])
        guard let unit = MeasurementUnit(rawValue: grid.unit), contains(grid.origin) else { throw LayoutError.invalid }
        result.grid = try GridConfiguration(isEnabled: grid.enabled, spacing: grid.spacing, unit: unit, origin: grid.origin, opacity: grid.opacity)
        let annotations = try shapes.map { record -> Annotation in
            guard let kind = AnnotationKind(rawValue: record.kind), contains(record.start), contains(record.end) else { throw LayoutError.invalid }
            let shape = Annotation(kind: kind, start: record.start, end: record.end, style: try record.style.value())
            guard shape.isValid else { throw LayoutError.invalid }
            return shape
        }
        var spotlightID: UUID?
        if let index = spotlightIndex {
            guard annotations.indices.contains(index), annotations[index].kind == .rectangle else { throw LayoutError.invalid }
            spotlightID = annotations[index].id
        }
        result.annotations = AnnotationSession(size: size, shapes: annotations, spotlightID: spotlightID, dimOpacity: dimOpacity,
            style: try style.value(), newRectanglesSpotlight: newRectanglesSpotlight)
        return result
    }
}

public struct SavedLayout: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let content: SavedLayoutContent
}

/// One recovery point for an explicit load, separate from ordinary tool undo.
public struct LayoutLoadRecovery {
    private var previous: (DisplayConfiguration, DisplaySession)?
    public init() {}
    public func canUndo(on display: DisplayConfiguration) -> Bool { previous?.0 == display }
    public mutating func invalidate(_ ids: Set<UInt32>) {
        if let previous, ids.contains(previous.0.id) { self.previous = nil }
    }
    public mutating func load(_ content: SavedLayoutContent, into session: inout DisplaySession, on display: DisplayConfiguration) throws {
        guard content.isCompatible(with: display), session.document.size == display.size else { throw LayoutError.display }
        var restored = try content.restoredSession(rootPixels: session.calibration.rootPixels)
        restored.reference = session.reference
        var previousSession = session
        // Recovery restores layout state only; it must not keep a removed/replaced image alive.
        previousSession.reference = nil
        previous = (display, previousSession)
        session = restored
    }
    public mutating func undo(into session: inout DisplaySession, on display: DisplayConfiguration) throws {
        guard let previous, previous.0 == display else { throw LayoutError.noRecovery }
        var restored = previous.1
        restored.reference = session.reference
        restored.calibration.setRootPixels(session.calibration.rootPixels)
        session = restored
        self.previous = nil
    }
}

@MainActor @Observable
public final class SavedLayoutsStore {
    struct Archive: Codable { let version: Int; let layouts: [SavedLayout] }
    public static let maximumBytes = 8 * 1024 * 1024
    public let fileURL: URL
    public private(set) var layouts: [SavedLayout] = []
    public private(set) var storageError: String?
    private var deleted: (index: Int, layout: SavedLayout)?
    public var canUndoDelete: Bool { deleted != nil && storageError == nil }

    public init(fileURL: URL) { self.fileURL = fileURL; reload() }

    public func reload() {
        do {
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path) }
            catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                layouts = []; storageError = nil; deleted = nil
                return
            }
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw LayoutError.invalid }
            guard let bytes = attributes[.size] as? NSNumber, bytes.intValue <= Self.maximumBytes else { throw LayoutError.limit }
            let data = try Data(contentsOf: fileURL)
            guard data.count <= Self.maximumBytes else { throw LayoutError.limit }
            struct Header: Decodable { let version: Int }
            guard try JSONDecoder().decode(Header.self, from: data).version == 1 else { throw LayoutError.version }
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            try validate(archive.layouts)
            layouts = archive.layouts; storageError = nil; deleted = nil
        } catch {
            layouts = []; deleted = nil
            storageError = "Could not read saved layouts. No files were changed. \(error.localizedDescription)"
        }
    }

    @discardableResult public func save(name: String, content: SavedLayoutContent) throws -> UUID {
        let item = SavedLayout(id: UUID(), name: try Self.normalizedName(name), content: content)
        try persist(layouts + [item])
        return item.id
    }
    public func rename(_ id: UUID, to name: String) throws {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { throw LayoutError.invalid }
        var updated = layouts
        updated[index].name = try Self.normalizedName(name)
        try persist(updated)
    }
    public func delete(_ id: UUID) throws {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { throw LayoutError.invalid }
        var updated = layouts
        let removed = updated.remove(at: index)
        try persist(updated)
        deleted = (index, removed)
    }
    @discardableResult public func undoDelete() throws -> UUID {
        guard let deleted else { throw LayoutError.invalid }
        var updated = layouts
        updated.insert(deleted.layout, at: min(deleted.index, updated.count))
        try persist(updated)
        self.deleted = nil
        return deleted.layout.id
    }
    static func normalizedName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(name.count), !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }) else { throw LayoutError.name }
        return name
    }
    private func validate(_ items: [SavedLayout]) throws {
        guard items.count <= 100 else { throw LayoutError.limit }
        guard Set(items.map(\.id)).count == items.count else { throw LayoutError.invalid }
        var names = Set<String>()
        for item in items {
            guard try Self.normalizedName(item.name) == item.name else { throw LayoutError.name }
            guard names.insert(item.name.lowercased()).inserted else { throw LayoutError.duplicate }
            _ = try item.content.restoredSession(rootPixels: 16)
        }
    }
    private func persist(_ updated: [SavedLayout]) throws {
        guard storageError == nil else { throw LayoutError.invalid }
        try validate(updated)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Archive(version: 1, layouts: updated))
        guard data.count <= Self.maximumBytes else { throw LayoutError.limit }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        layouts = updated
    }
}

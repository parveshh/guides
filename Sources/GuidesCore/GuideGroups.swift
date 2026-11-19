import Foundation

public struct GuideGroup: Identifiable, Sendable {
    public let id: UUID
    public fileprivate(set) var name: String
    public fileprivate(set) var frame: CGRect
    public var measurements: MeasurementWorkspace
}

public struct GuideGroups: Sendable {
    public private(set) var items: [GuideGroup] = []
    public var activeID: UUID?
    public init() {}

    public func group(_ id: UUID) throws -> GuideGroup {
        guard let group = items.first(where: { $0.id == id }) else { throw CommandLineError("Unknown group on this display.") }
        return group
    }

    @discardableResult
    public mutating func create(name: String, frame: CGRect, display: CGSize, rootPixels: CGFloat) throws -> UUID {
        guard items.count < 64 else { throw CommandLineError("Each display supports up to 64 groups.") }
        let name = try validated(name: name, frame: frame, display: display, excluding: nil)
        let group = GuideGroup(id: UUID(), name: name, frame: frame,
                               measurements: MeasurementWorkspace(size: frame.size, rootPixels: rootPixels))
        items.append(group)
        return group.id
    }

    public mutating func edit(_ id: UUID, name: String, frame: CGRect, display: CGSize) throws {
        let name = try validated(name: name, frame: frame, display: display, excluding: id)
        var group = try group(id)
        if frame.size != group.frame.size {
            try group.measurements.document.resize(to: frame.size)
            // Snapshots have the old bounds. A later undo must never restore those bounds.
            group.measurements.history = DocumentHistory()
        }
        group.name = name
        group.frame = frame
        if let index = items.firstIndex(where: { $0.id == id }) { items[index] = group }
    }

    public mutating func update(_ id: UUID, measurements: MeasurementWorkspace) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].frame.size == measurements.document.size else { return }
        items[index].measurements = measurements
    }

    public mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        if activeID == id { activeID = nil }
    }

    public mutating func setRootPixels(_ pixels: CGFloat) {
        for index in items.indices { items[index].measurements.calibration.setRootPixels(pixels) }
    }

    private func validated(name: String, frame: CGRect, display: CGSize, excluding id: UUID?) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 128,
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw CommandLineError("Enter a group name of 1–128 bytes on one line.")
        }
        guard frame.size.width > 0, frame.size.height > 0, frame.minX >= 0, frame.minY >= 0,
              frame.maxX <= display.width, frame.maxY <= display.height else {
            throw CommandLineError("The group must fit inside this display.")
        }
        guard !items.contains(where: { other in
            let overlap = other.frame.intersection(frame)
            return other.id != id && overlap.width > 0 && overlap.height > 0
        }) else { throw CommandLineError("Group regions can touch, but cannot overlap.") }
        return name
    }
}

public extension MeasurementWorkspace {
    var spacingDistance: CGFloat? {
        if document.isAreaSelected, let rect = document.area?.rect {
            switch areaDimension {
            case .width: return rect.width
            case .height: return rect.height
            case .both, .radius: return nil
            }
        }
        return document.selectedGap?.distance
    }
    func copyText(backingFactor: CGFloat) -> String? {
        if document.isAreaSelected, let rect = document.area?.rect, rect.width > 0, rect.height > 0 {
            return MeasurementEngine.areaText(rect, dimension: areaDimension, unit: unit,
                calibration: calibration, backingFactor: backingFactor, cornerRadius: document.area?.cornerRadius ?? 0)
        }
        return document.selectedGap.flatMap { MeasurementEngine.text($0.distance, unit: unit,
            calibration: calibration, backingFactor: backingFactor) }
    }
    /// The selected measurement in screen points, for CSS and Tailwind copy formats.
    var copySubject: CopySubject? {
        if document.isAreaSelected, let area = document.area, area.rect.width > 0, area.rect.height > 0 {
            switch areaDimension {
            case .width: return .width(area.rect.width)
            case .height: return .height(area.rect.height)
            case .both: return .size(width: area.rect.width, height: area.rect.height)
            case .radius: return .radius(area.cornerRadius)
            }
        }
        return document.selectedGap.map { .gap($0.distance) }
    }
}

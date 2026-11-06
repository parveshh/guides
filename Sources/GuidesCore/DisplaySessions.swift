import Foundation

public struct DisplayConfiguration: Equatable, Sendable {
    public let id: UInt32
    public let size: CGSize
    public let backingFactor: CGFloat
    public init(id: UInt32, size: CGSize, backingFactor: CGFloat) {
        self.id = id; self.size = size; self.backingFactor = backingFactor
    }
}

public struct DisplaySession: Sendable {
    public var document: MeasurementDocument
    public var history = DocumentHistory()
    public var calibration: Calibration
    public var unit: MeasurementUnit = .screenPoints
    public var areaDimension: AreaDimension = .both
    public var grid = GridConfiguration()
    public var reference: ReferenceOverlay?
    public init(size: CGSize, rootPixels: CGFloat) {
        document = MeasurementDocument(size: size)
        calibration = Calibration(rootPixels: rootPixels)
    }
}

/// Session IDs are only meaningful during this process. Nothing here is persisted.
public struct DisplaySessions: Sendable {
    private var configurations: [UInt32: DisplayConfiguration] = [:]
    private var sessions: [UInt32: DisplaySession] = [:]
    public private(set) var activeID: UInt32?
    public init() {}

    @discardableResult
    public mutating func synchronize(_ current: [DisplayConfiguration]) -> Set<UInt32> {
        let updated = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let invalidated = Set(configurations.keys.filter { configurations[$0] != updated[$0] })
        for id in invalidated { sessions[id] = nil }
        if let activeID, invalidated.contains(activeID) { self.activeID = nil }
        configurations = updated
        return invalidated
    }

    public mutating func activate(_ id: UInt32, rootPixels: CGFloat) -> DisplaySession? {
        guard let configuration = configurations[id] else { return nil }
        activeID = id
        var session = sessions[id] ?? DisplaySession(size: configuration.size, rootPixels: rootPixels)
        session.calibration.setRootPixels(rootPixels)
        return session
    }

    public mutating func save(_ session: DisplaySession) {
        guard let activeID, configurations[activeID]?.size == session.document.size else { return }
        sessions[activeID] = session
    }
}

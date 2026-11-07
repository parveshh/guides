import Foundation
import Testing
@testable import GuidesCore

@Test func radiusValidatesBoundsAndMovesResizesAndReplacesPredictably() {
    var document = MeasurementDocument(size: CGSize(width: 800, height: 600))
    let missing = document.setCornerRadius(10); #expect(!missing)
    document.setArea(CGRect(x: 100, y: 100, width: 200, height: 100))
    let maximum = document.setCornerRadius(50); #expect(maximum)
    for invalid: CGFloat in [-1, 50.1, .infinity, .nan] {
        let accepted = document.setCornerRadius(invalid); #expect(!accepted)
        #expect(document.area?.cornerRadius == 50)
    }
    document.nudge(dx: 10, dy: 20)
    #expect(document.area?.cornerRadius == 50 && document.area?.rect.origin == CGPoint(x: 110, y: 120))
    document.setArea(CGRect(x: 110, y: 120, width: 20, height: 100))
    #expect(document.area?.cornerRadius == 10)
    document.setArea(CGRect(x: 110, y: 120, width: 80, height: 100), id: UUID())
    #expect(document.area?.cornerRadius == 0)
    let fractional = document.setCornerRadius(0.5); #expect(fractional)
    let zero = document.setCornerRadius(0); #expect(zero)
}

@Test func radiusChangesAndDeletionShareMeasurementHistory() {
    var document = MeasurementDocument(size: CGSize(width: 800, height: 600))
    document.add(axis: .vertical, position: 40)
    document.setArea(CGRect(x: 100, y: 100, width: 200, height: 100))
    let original = document
    var history = DocumentHistory()
    document.setCornerRadius(24)
    history.record(before: original, after: document)
    let rounded = document
    document = history.undo(current: document)!
    #expect(document.area?.cornerRadius == 0)
    document = history.redo(current: document)!
    #expect(document == rounded)
    document.deleteSelection()
    history.record(before: rounded, after: document)
    #expect(document.area == nil && document.guides.count == 1)
    #expect(history.undo(current: document)?.area?.cornerRadius == 24)
}

@Test func radiusReadoutConvertsOnlyWithExplicitCalibration() {
    let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
    var calibration = Calibration()
    func text(_ unit: MeasurementUnit) -> String? {
        MeasurementEngine.areaText(rect, dimension: .radius, unit: unit, calibration: calibration, backingFactor: 2, cornerRadius: 32)
    }
    #expect(text(.screenPoints) == "32 screen pt")
    #expect(text(.backingPixels) == "64 backing px")
    #expect(text(.designPixels) == nil && text(.rem) == nil)
    calibration.setScale(percent: 200)
    #expect(text(.designPixels) == "16px" && text(.rem) == "1rem")
    #expect(MeasurementEngine.areaText(rect, dimension: .both, unit: .screenPoints, calibration: calibration, backingFactor: 2, cornerRadius: 32) == "200 × 100 screen pt")
}

@Test @MainActor func radiusArchivesMigrateLegacyAndRejectInvalidValues() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("radius-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    var session = DisplaySession(size: CGSize(width: 800, height: 600), rootPixels: 16)
    session.document.setArea(CGRect(x: 50, y: 80, width: 200, height: 100))
    session.document.setCornerRadius(24.5)
    let content = try SavedLayoutContent(session: session, backingFactor: 2)
    let store = SavedLayoutsStore(fileURL: url)
    try store.save(name: "Rounded", content: content)
    let archive = try JSONDecoder().decode(SavedLayoutsStore.Archive.self, from: Data(contentsOf: url))
    #expect(archive.version == 2)
    #expect(try SavedLayoutsStore(fileURL: url).layouts[0].content.restoredSession(rootPixels: 16).document.area?.cornerRadius == 24.5)
    var record = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(content)) as? [String: Any])
    for radius in [-1.0, 50.1] {
        record["areaRadius"] = radius
        let bad = try JSONDecoder().decode(SavedLayoutContent.self, from: JSONSerialization.data(withJSONObject: record))
        #expect(throws: LayoutError.self) { try bad.restoredSession(rootPixels: 16) }
    }
    record.removeValue(forKey: "areaRadius")
    let legacy = try JSONDecoder().decode(SavedLayoutContent.self, from: JSONSerialization.data(withJSONObject: record))
    try JSONEncoder().encode(SavedLayoutsStore.Archive(version: 1, layouts: [SavedLayout(id: UUID(), name: "Old", content: legacy)])).write(to: url)
    let old = SavedLayoutsStore(fileURL: url)
    #expect(old.storageError == nil)
    #expect(try old.layouts[0].content.restoredSession(rootPixels: 16).document.area?.cornerRadius == 0)
    var recovery = LayoutLoadRecovery()
    let display = DisplayConfiguration(id: 1, size: session.document.size, backingFactor: 2)
    try recovery.load(legacy, into: &session, on: display)
    #expect(session.document.area?.cornerRadius == 0)
    try recovery.undo(into: &session, on: display)
    #expect(session.document.area?.cornerRadius == 24.5)
}

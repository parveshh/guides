import Foundation
import Testing
@testable import GuidesCore

@Test func commandParsingRejectsInvalidRequests() throws {
    let invalid: [[String]] = [[], ["capture"], ["status", "extra"], ["guide", "diagonal", "10"],
        ["guide", "vertical", "nan"], ["area", "1", "2", "3"], ["select", "not-a-uuid"],
        ["show", "area", "-1"], ["show", "unknown"], ["calibrate", "inf"], ["read", "html"],
        ["unit", "css"], [String(repeating: "a", count: 129)], Array(repeating: "x", count: 9)]
    for args in invalid { #expect(throws: CommandLineError.self) { try GuidesCommand.parse(args) } }
    #expect(try GuidesCommand.parse(["show"]) == .show(.guides, nil))
    #expect(try GuidesCommand.parse(["show", "area", "42"]) == .show(.area, 42))
    #expect(try GuidesCommand.parse(["area", "10", "20", "64", "80", "8"]) == .area(CGRect(x: 10, y: 20, width: 64, height: 80), 8))
}

@Test func commandGapUsesExactPointsAndOneUndoAction() throws {
    var session = DisplaySession(size: CGSize(width: 1000, height: 800), rootPixels: 16)
    try CommandLineEditing.apply(.gap(.vertical, 400.125, 336.125), to: &session)
    #expect(session.document.selectedGap?.distance == 64)
    #expect(session.document.guides.first?.position == 400.125)
    try CommandLineEditing.apply(.undo, to: &session)
    #expect(session.document.guides.isEmpty && !session.history.canUndo)
    try CommandLineEditing.apply(.redo, to: &session)
    #expect(session.document.selectedGap?.distance == 64)
}

@Test func invalidCommandGeometryLeavesSessionUnchanged() throws {
    var session = DisplaySession(size: CGSize(width: 1000, height: 800), rootPixels: 16)
    try CommandLineEditing.apply(.gap(.horizontal, 100, 164), to: &session)
    let before = session.document
    for command: GuidesCommand in [.guide(.vertical, -1), .gap(.horizontal, 10, 801),
        .area(CGRect(x: 900, y: 1, width: 101, height: 30), 0),
        .area(CGRect(x: 1, y: 1, width: -10, height: 30), 0),
        .area(CGRect(x: 1, y: 1, width: 20, height: 30), 11), .select([UUID()])] {
        #expect(throws: CommandLineError.self) { try CommandLineEditing.apply(command, to: &session) }
        #expect(session.document == before)
    }
    try CommandLineEditing.apply(.undo, to: &session)
    #expect(session.document.guides.isEmpty && !session.history.canUndo)
}

@Test func commandCalibrationAndUnitGatingAreAtomic() throws {
    var session = DisplaySession(size: CGSize(width: 1000, height: 800), rootPixels: 16)
    #expect(throws: CommandLineError.self) { try CommandLineEditing.apply(.unit(.rem), to: &session) }
    #expect(throws: CommandLineError.self) { try CommandLineEditing.apply(.calibrate(200, -1), to: &session) }
    #expect(!session.calibration.isConfirmed && session.unit == .screenPoints)
    try CommandLineEditing.apply(.calibrate(200, 20), to: &session)
    try CommandLineEditing.apply(.unit(.rem), to: &session)
    #expect(MeasurementEngine.text(64, unit: session.unit, calibration: session.calibration, backingFactor: 2) == "1.6rem")
    #expect(!session.history.canUndo)
}

@Test func commandAreaReplacementAndSelectionPreserveHistory() throws {
    var session = DisplaySession(size: CGSize(width: 1000, height: 800), rootPixels: 16)
    try CommandLineEditing.apply(.area(CGRect(x: 0, y: 0, width: 64, height: 80), 8), to: &session)
    let first = session.document.area
    try CommandLineEditing.apply(.selectArea(.radius), to: &session)
    #expect(session.areaDimension == .radius)
    try CommandLineEditing.apply(.area(CGRect(x: 1, y: 2, width: 40, height: 30), 0), to: &session)
    #expect(session.document.area?.cornerRadius == 0 && session.areaDimension == .both)
    try CommandLineEditing.apply(.undo, to: &session)
    #expect(session.document.area == first)
    try CommandLineEditing.apply(.delete, to: &session)
    #expect(session.document.area == nil)
    try CommandLineEditing.apply(.undo, to: &session)
    #expect(session.document.area == first)
}

@Test func commandSelectionRequiresExistingParallelGuides() throws {
    var session = DisplaySession(size: CGSize(width: 1000, height: 800), rootPixels: 16)
    try CommandLineEditing.apply(.gap(.vertical, 10, 20), to: &session)
    let ids = session.document.selection
    try CommandLineEditing.apply(.guide(.horizontal, 30), to: &session)
    let horizontal = session.document.selection[0]
    #expect(throws: CommandLineError.self) { try CommandLineEditing.apply(.select([ids[0], horizontal]), to: &session) }
    #expect(throws: CommandLineError.self) { try CommandLineEditing.apply(.select([ids[0], ids[0]]), to: &session) }
    try CommandLineEditing.apply(.select(ids), to: &session)
    #expect(session.document.selectedGap?.distance == 10)
}

@Test func commandGuideBudgetDoesNotPartiallyCreateAPair() throws {
    var session = DisplaySession(size: CGSize(width: 1000, height: 800), rootPixels: 16)
    for _ in 0..<999 { session.document.add(axis: .vertical, position: 0) }
    #expect(throws: CommandLineError.self) { try CommandLineEditing.apply(.gap(.vertical, 10, 20), to: &session) }
    #expect(session.document.guides.count == 999)
    try CommandLineEditing.apply(.guide(.vertical, 10), to: &session)
    #expect(throws: CommandLineError.self) { try CommandLineEditing.apply(.guide(.vertical, 20), to: &session) }
    #expect(session.document.guides.count == 1000)
}

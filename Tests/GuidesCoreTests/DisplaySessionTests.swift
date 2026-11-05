import Foundation
import Testing
@testable import GuidesCore

private let firstDisplay = DisplayConfiguration(id: 1, size: CGSize(width: 1000, height: 800), backingFactor: 2)
private let secondDisplay = DisplayConfiguration(id: 2, size: CGSize(width: 1000, height: 800), backingFactor: 1)

@Test func sameSizeDisplaysKeepIndependentDocumentsHistoryAndCalibration() throws {
    var store = DisplaySessions()
    store.synchronize([firstDisplay, secondDisplay])
    var first = try activate(&store, 1, rootPixels: 16)
    let before = first.document
    first.document.add(axis: .horizontal, position: 300)
    first.document.setArea(CGRect(x: 20, y: 40, width: 300, height: 150))
    first.history.record(before: before, after: first.document)
    first.calibration.setScale(percent: 200)
    first.unit = .rem
    store.save(first)
    let second = try activate(&store, 2, rootPixels: 16)
    #expect(second.document.guides.isEmpty)
    #expect(second.document.area == nil)
    #expect(!second.history.canUndo)
    #expect(!second.calibration.isConfirmed)
    store.save(second)
    let restored = try activate(&store, 1, rootPixels: 20)
    #expect(restored.document == first.document)
    #expect(restored.history.canUndo)
    #expect(restored.unit == .rem)
    #expect(restored.calibration.pointsPerPixel == 2)
    #expect(restored.calibration.rootPixels == 20)
}

@Test func backingOrResolutionChangeClearsOnlyAffectedSession() throws {
    var store = DisplaySessions()
    store.synchronize([firstDisplay, secondDisplay])
    for id: UInt32 in [1, 2] {
        var session = try activate(&store, id, rootPixels: 16)
        session.document.add(axis: .vertical, position: 100)
        session.calibration.setScale(percent: 150)
        store.save(session)
    }
    let changed = DisplayConfiguration(id: 2, size: secondDisplay.size, backingFactor: 2)
    let invalidated = store.synchronize([firstDisplay, changed])
    #expect(invalidated == [2])
    #expect(store.activeID == nil)
    let untouched = try activate(&store, 1, rootPixels: 16)
    #expect(untouched.document.guides.count == 1)
    let reset = try activate(&store, 2, rootPixels: 16)
    #expect(reset.document.guides.isEmpty)
    #expect(!reset.calibration.isConfirmed)
    let resized = DisplayConfiguration(id: 1, size: CGSize(width: 800, height: 600), backingFactor: 2)
    let resizedIDs = store.synchronize([resized, changed])
    #expect(resizedIDs == [1])
}

@Test func disconnectReconnectStartsFreshAndUnchangedRefreshRetains() throws {
    var store = DisplaySessions()
    store.synchronize([firstDisplay])
    var session = try activate(&store, 1, rootPixels: 16)
    session.document.add(axis: .horizontal, position: 20)
    store.save(session)
    let unchanged = store.synchronize([firstDisplay])
    #expect(unchanged.isEmpty)
    #expect(store.activeID == 1)
    let retained = store.activate(1, rootPixels: 16)
    #expect(retained?.document.guides.count == 1)
    let removed = store.synchronize([])
    #expect(removed == [1])
    #expect(store.activeID == nil)
    let absent = store.activate(1, rootPixels: 16)
    #expect(absent == nil)
    store.synchronize([firstDisplay])
    let reconnected = store.activate(1, rootPixels: 16)
    #expect(reconnected?.document.guides.isEmpty == true)
}

@Test func keyboardSelectionCyclesAndExtendsNonadjacentPairs() throws {
    var document = MeasurementDocument(size: firstDisplay.size)
    let firstID = document.add(axis: .horizontal, position: 10)
    let first = try #require(firstID)
    document.add(axis: .horizontal, position: 30)
    let lastID = document.add(axis: .horizontal, position: 60)
    let last = try #require(lastID)
    document.setArea(CGRect(x: 10, y: 10, width: 10, height: 10))
    document.select([])
    document.cycleSelection(backwards: false, extending: false)
    #expect(document.selection == [first])
    document.cycleSelection(backwards: false, extending: true)
    document.cycleSelection(backwards: false, extending: true)
    #expect(document.selection == [first, last])
    #expect(document.selectedGap?.distance == 50)
    document.cycleSelection(backwards: false, extending: false)
    #expect(document.isAreaSelected)
    document.cycleSelection(backwards: false, extending: false)
    #expect(document.selection == [first])
    document.cycleSelection(backwards: true, extending: false)
    #expect(document.isAreaSelected)
}

@Test func bracketKeysRespectEditingModifiers() {
    #expect(KeyboardEditing.action(keyCode: 30, characters: "]") == .cycle(backwards: false, extending: false))
    #expect(KeyboardEditing.action(keyCode: 33, characters: "{", shift: true) == .cycle(backwards: true, extending: true))
    #expect(KeyboardEditing.action(keyCode: 30, characters: "]", command: true) == nil)
    #expect(KeyboardEditing.action(keyCode: 30, characters: "]", option: true) == nil)
}

private func activate(_ store: inout DisplaySessions, _ id: UInt32, rootPixels: CGFloat) throws -> DisplaySession {
    let session = store.activate(id, rootPixels: rootPixels)
    return try #require(session)
}

import CoreGraphics
import Testing
@testable import GuidesCore

@Test func extendedSelectionMeasuresOnlyParallelGuides() {
    var doc = MeasurementDocument(size: CGSize(width: 100, height: 100))
    let a = doc.add(axis: .vertical, position: 10)!
    let b = doc.add(axis: .vertical, position: 30)!
    let c = doc.add(axis: .vertical, position: 70)!
    let h = doc.add(axis: .horizontal, position: 20)!
    doc.selectGuide(a, extending: false)
    doc.selectGuide(c, extending: true)
    #expect(doc.selectedGap?.distance == 60)
    doc.selectGuide(b, extending: true)
    #expect(doc.selection == [a, b])
    doc.selectGuide(h, extending: true)
    #expect(doc.selection == [h])
    #expect(doc.selectedGap == nil)
}

@Test func groupedNudgingPreservesGapAtEdges() {
    var doc = MeasurementDocument(size: CGSize(width: 100, height: 100))
    let a = doc.add(axis: .vertical, position: 80)!
    let b = doc.add(axis: .vertical, position: 90)!
    doc.select([a, b]); doc.nudge(dx: 50, dy: 0)
    #expect(doc.guides.map(\.position) == [90, 100])
    #expect(doc.selectedGap?.distance == 10)
    doc.nudge(dx: -0.5, dy: 0)
    #expect(doc.guides.map(\.position) == [89.5, 99.5])
}

@Test func historyTreatsDragAsOneAction() {
    var doc = MeasurementDocument(size: CGSize(width: 100, height: 100))
    let id = doc.add(axis: .vertical, position: 10)!
    let before = doc
    for x in 11...80 { doc.move(id: id, to: CGFloat(x)) }
    var history = DocumentHistory()
    history.record(before: before, after: doc)
    doc = history.undo(current: doc)!
    #expect(doc.guides[0].position == 10)
    #expect(!history.canUndo)
    doc = history.redo(current: doc)!
    #expect(doc.guides[0].position == 80)
}

@Test func selectionIsNotAnUndoActionAndNewEditDropsRedo() {
    var doc = MeasurementDocument(size: CGSize(width: 100, height: 100))
    let empty = doc
    _ = doc.add(axis: .vertical, position: 10)
    var history = DocumentHistory()
    history.record(before: empty, after: doc)
    let selected = doc
    doc.select([])
    history.record(before: selected, after: doc)
    doc = history.undo(current: doc)!
    #expect(doc == empty)
    #expect(history.canRedo)
    let before = doc
    _ = doc.add(axis: .horizontal, position: 40)
    history.record(before: before, after: doc)
    #expect(!history.canRedo)
}

@Test func clearAndDeleteCanBeUndone() {
    var doc = MeasurementDocument(size: CGSize(width: 100, height: 100))
    let a = doc.add(axis: .horizontal, position: 10)!
    _ = doc.add(axis: .vertical, position: 20)
    var history = DocumentHistory()
    let both = doc
    doc.select([a]); doc.deleteSelection()
    history.record(before: both, after: doc)
    #expect(doc.guides.count == 1)
    doc = history.undo(current: doc)!
    #expect(doc.guides.count == 2)
    let beforeClear = doc
    doc.clear(); history.record(before: beforeClear, after: doc)
    #expect(doc.guides.isEmpty)
    doc = history.undo(current: doc)!
    #expect(doc == beforeClear)
}

import CoreGraphics
import Foundation
import Testing
@testable import GuidesCore

@Test func reverseAreaDragAndBounds() {
    let rect = AreaGeometry.rectangle(from: CGPoint(x: 150, y: 80), to: CGPoint(x: 30, y: -10), within: CGSize(width: 200, height: 100))
    #expect(rect == CGRect(x: 30, y: 0, width: 120, height: 80))
}

@Test func movingAreaPreservesSizeAtBounds() {
    let rect = CGRect(x: 20, y: 30, width: 40, height: 50)
    #expect(AreaGeometry.moved(rect, dx: 1000, dy: -1000, within: CGSize(width: 200, height: 100)) == CGRect(x: 160, y: 0, width: 40, height: 50))
}

@Test func resizeCanCrossOppositeCorner() {
    let rect = CGRect(x: 20, y: 30, width: 40, height: 50)
    let result = AreaGeometry.resized(rect, handle: .topLeft, to: CGPoint(x: 80, y: 100), within: CGSize(width: 200, height: 200))
    #expect(result == CGRect(x: 60, y: 80, width: 20, height: 20))
    let edge = AreaGeometry.resized(rect, handle: .right, to: CGPoint(x: 150, y: 999), within: CGSize(width: 200, height: 200))
    #expect(edge == CGRect(x: 20, y: 30, width: 130, height: 50))
}

@Test(arguments: AreaHandle.allCases)
func resizingAtOriginalHandleIsIdentity(handle: AreaHandle) {
    let rect = CGRect(x: 20, y: 30, width: 40, height: 50)
    #expect(AreaGeometry.resized(rect, handle: handle, to: handle.point(on: rect), within: CGSize(width: 200, height: 200)) == rect)
}

@Test func areaReplacementAndDeletionAreUndoableWithoutLosingGuides() {
    var doc = MeasurementDocument(size: CGSize(width: 200, height: 200))
    _ = doc.add(axis: .vertical, position: 10)
    doc.setArea(CGRect(x: 20, y: 30, width: 40, height: 50))
    let original = doc
    doc.setArea(CGRect(x: 10, y: 10, width: 100, height: 100), id: UUID())
    var history = DocumentHistory()
    history.record(before: original, after: doc)
    doc = history.undo(current: doc)!
    #expect(doc == original)
    let beforeDelete = doc
    doc.deleteSelection()
    #expect(doc.area == nil)
    #expect(doc.guides.count == 1)
    history.record(before: beforeDelete, after: doc)
    #expect(history.undo(current: doc) == original)
}

@Test func areaNudgeAndInvalidRectangles() {
    var doc = MeasurementDocument(size: CGSize(width: 100, height: 100))
    doc.setArea(CGRect(x: 10, y: 20, width: 30, height: 40))
    doc.nudge(dx: 0.5, dy: 10)
    #expect(doc.area?.rect == CGRect(x: 10.5, y: 30, width: 30, height: 40))
    let before = doc
    doc.setArea(CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10))
    #expect(doc == before)
    doc.select([])
    #expect(!doc.isAreaSelected)
}

@Test(arguments: [CGFloat(1), 5, 10])
func nearestHandleWinsOnTinyRectangles(side: CGFloat) {
    let rect = CGRect(x: 50, y: 50, width: side, height: side)
    for handle in AreaHandle.allCases {
        #expect(AreaGeometry.hitHandle(at: handle.point(on: rect), rect: rect) == handle)
    }
}

@Test func handleHitRequiresProximity() {
    let rect = CGRect(x: 20, y: 20, width: 100, height: 100)
    #expect(AreaGeometry.hitHandle(at: CGPoint(x: 120, y: 120), rect: rect) == .bottomRight)
    #expect(AreaGeometry.hitHandle(at: CGPoint(x: 70, y: 70), rect: rect) == nil)
    #expect(AreaGeometry.hitHandle(at: CGPoint(x: 200, y: 200), rect: rect) == nil)
}

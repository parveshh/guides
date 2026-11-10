import Foundation
import Testing
@testable import GuidesCore

private let labelDisplaySize = CGSize(width: 1200, height: 900)
private let labelUsable = CGRect(x: 0, y: 24, width: 1200, height: 840)

@Test func labelDragLocksTheMeasuredAxisAndKeepsPointerOffset() {
    let width = GuideGap(first: Guide(axis: .vertical, position: 100), second: Guide(axis: .vertical, position: 500))
    let height = GuideGap(first: Guide(axis: .horizontal, position: 200), second: Guide(axis: .horizontal, position: 700))
    let start = CGPoint(x: 310, y: 240)
    let widthDrag = GapLabelDrag(gap: width, anchor: CGPoint(x: 300, y: 230), start: start)
    let heightDrag = GapLabelDrag(gap: height, anchor: CGPoint(x: 300, y: 450), start: start)
    #expect(widthDrag.position(at: CGPoint(x: 1000, y: 310)) == 300)
    #expect(widthDrag.position(at: CGPoint(x: 0, y: 240)) == 230)
    #expect(heightDrag.position(at: CGPoint(x: 380, y: 800)) == 370)
    #expect(heightDrag.position(at: CGPoint(x: 310, y: 0)) == 300)
}

@Test func gapAnchorKeepsConnectorBetweenGuidesAndClampsOnlyLabelTravel() {
    let toolbar = CGRect(x: 100, y: 40, width: 900, height: 130)
    for axis in GuideAxis.allCases {
        let gap = GuideGap(first: Guide(axis: axis, position: 100), second: Guide(axis: axis, position: 500))
        for position in [-1000.0, 0, 300, 5000] {
            let anchor = MeasurementReadoutLayout.gapAnchor(gap, usable: labelUsable, toolbar: toolbar, orthogonalPosition: position)
            #expect(axis == .vertical ? anchor.x == 300 : anchor.y == 300)
            if axis == .vertical { #expect((36...852).contains(anchor.y)) }
            else { #expect((12...1188).contains(anchor.x)) }
        }
        let fallback = MeasurementReadoutLayout.gapAnchor(gap, usable: labelUsable, toolbar: toolbar)
        let invalid = MeasurementReadoutLayout.gapAnchor(gap, usable: labelUsable, toolbar: toolbar, orthogonalPosition: .infinity)
        #expect(fallback == invalid)
    }
}

@Test func labelPositionsFollowGuideIdentityAcrossReorderingAndRejectInvalidPairs() throws {
    var doc = MeasurementDocument(size: labelDisplaySize)
    let first = try requiredLabelValue(doc.add(axis: .vertical, position: 100))
    let second = try requiredLabelValue(doc.add(axis: .vertical, position: 500))
    doc.select([first, second])
    let original = try #require(doc.selectedGap)
    doc.setGapLabelPosition(450, for: original)
    doc.move(id: first, to: 700)
    doc.select([second, first])
    let reversed = try #require(doc.selectedGap)
    #expect(doc.gapLabelPosition(for: reversed) == 450)
    doc.setGapLabelPosition(.nan, for: reversed)
    #expect(doc.gapLabelPosition(for: reversed) == 450)
    let unrelated = GuideGap(first: Guide(axis: .vertical, position: 100), second: original.second)
    doc.setGapLabelPosition(100, for: unrelated)
    #expect(doc.gapLabelPosition(for: unrelated) == nil)
    let duplicate = GuideGap(first: original.first, second: original.first)
    doc.setGapLabelPosition(100, for: duplicate)
    #expect(doc.gapLabelPosition(for: duplicate) == nil)
    let horizontal = try requiredLabelValue(doc.add(axis: .horizontal, position: 300))
    let mixed = GuideGap(first: original.first, second: try #require(doc.guides.first { $0.id == horizontal }))
    doc.setGapLabelPosition(100, for: mixed)
    #expect(doc.gapLabelPosition(for: mixed) == nil)
}

@Test func labelMovementDoesNotChangeMeasurementOrAreaAndIsOneUndoAction() throws {
    var doc = MeasurementDocument(size: labelDisplaySize)
    let first = try requiredLabelValue(doc.add(axis: .horizontal, position: 100))
    let second = try requiredLabelValue(doc.add(axis: .horizontal, position: 500))
    doc.setArea(CGRect(x: 50, y: 80, width: 300, height: 150))
    doc.select([first, second])
    let gap = try #require(doc.selectedGap)
    let before = doc
    for x in 100...600 { doc.setGapLabelPosition(CGFloat(x), for: gap) }
    #expect(doc.guides == before.guides)
    #expect(doc.area == before.area)
    #expect(doc.selectedGap?.distance == 400)
    var calibration = Calibration(); calibration.setScale(percent: 200)
    #expect(MeasurementEngine.text(doc.selectedGap!.distance, unit: .designPixels, calibration: calibration, backingFactor: 2) == "200px")
    var history = DocumentHistory()
    history.record(before: before, after: doc)
    let undone = try requiredLabelValue(history.undo(current: doc))
    #expect(undone == before)
    #expect(!history.canUndo)
    let redone = try requiredLabelValue(history.redo(current: undone))
    #expect(redone.gapLabelPosition(for: gap) == 600)
    #expect(redone.guides == before.guides)
    doc = before // The same value restore is used when Escape cancels an in-flight gesture.
    #expect(doc.gapLabelPosition(for: gap) == nil)
}

@Test func positionsClampPerAxisAndDeletingGuidesPrunesOnlyTheirPairs() throws {
    var doc = MeasurementDocument(size: labelDisplaySize)
    let a = try requiredLabelValue(doc.add(axis: .vertical, position: 100))
    let b = try requiredLabelValue(doc.add(axis: .vertical, position: 300))
    let c = try requiredLabelValue(doc.add(axis: .vertical, position: 700))
    doc.select([a, b]); let ab = try #require(doc.selectedGap)
    doc.setGapLabelPosition(10000, for: ab)
    #expect(doc.gapLabelPosition(for: ab) == 900)
    doc.select([b, c]); let bc = try #require(doc.selectedGap)
    doc.setGapLabelPosition(-100, for: bc)
    #expect(doc.gapLabelPosition(for: bc) == 0)
    doc.select([a]); doc.deleteSelection()
    #expect(doc.gapLabelPosition(for: ab) == nil)
    #expect(doc.gapLabelPosition(for: bc) == 0)
    doc.setGapLabelPosition(nil, for: bc)
    #expect(doc.gapLabelPosition(for: bc) == nil)
    doc.setGapLabelPosition(200, for: bc)
    doc.clear()
    #expect(doc.gapLabelPosition(for: bc) == nil)
    #expect(doc.hasSameContent(as: MeasurementDocument(size: labelDisplaySize)))
}

@Test func labelPositionsArePerDisplayAndFreshAfterInvalidation() throws {
    let configuration = DisplayConfiguration(id: 1, size: labelDisplaySize, backingFactor: 2)
    let other = DisplayConfiguration(id: 2, size: labelDisplaySize, backingFactor: 2)
    var store = DisplaySessions(); store.synchronize([configuration, other])
    var session = try requiredLabelValue(store.activate(1, rootPixels: 16))
    let first = try requiredLabelValue(session.document.add(axis: .vertical, position: 100))
    let second = try requiredLabelValue(session.document.add(axis: .vertical, position: 300))
    session.document.select([first, second])
    let gap = try #require(session.document.selectedGap)
    session.document.setGapLabelPosition(650, for: gap)
    store.save(session)
    let secondSession = store.activate(2, rootPixels: 16)
    let restored = store.activate(1, rootPixels: 20)
    #expect(secondSession?.document.gapLabelPosition(for: gap) == nil)
    #expect(restored?.document.gapLabelPosition(for: gap) == 650)
    store.synchronize([DisplayConfiguration(id: 1, size: labelDisplaySize, backingFactor: 1), other])
    let reset = store.activate(1, rootPixels: 16)
    #expect(reset?.document.gapLabelPosition(for: gap) == nil)
}

@Test func copyPanelAvoidsDraggableChipForBothAxes() {
    let toolbar = CGRect(x: 100, y: 40, width: 900, height: 130)
    for beside in [false, true] {
        for center in [CGPoint(x: 400, y: 400), CGPoint(x: 400, y: 40), CGPoint(x: 1100, y: 830)] {
            let chip = CGRect(x: center.x - 55, y: center.y - 12, width: 110, height: 24)
            let panel = MeasurementReadoutLayout.frame(size: CGSize(width: 400, height: 80), anchor: center,
                beside: beside, usable: labelUsable, toolbar: toolbar, area: chip)
            #expect(!panel.intersects(chip.insetBy(dx: -8, dy: -8)))
            #expect(labelUsable.contains(panel))
        }
    }
}

private func requiredLabelValue<T>(_ value: T?) throws -> T { try #require(value) }

@Test func savedLayoutsKeepGeometryButResetViewingPositions() throws {
    var session = DisplaySession(size: labelDisplaySize, rootPixels: 16)
    let first = try requiredLabelValue(session.document.add(axis: .vertical, position: 100))
    let second = try requiredLabelValue(session.document.add(axis: .vertical, position: 500))
    session.document.select([first, second])
    let gap = try #require(session.document.selectedGap)
    let original = try SavedLayoutContent(session: session, backingFactor: 2)
    session.document.setGapLabelPosition(600, for: gap)
    let moved = try SavedLayoutContent(session: session, backingFactor: 2)
    #expect(moved == original)
    let restored = try moved.restoredSession(rootPixels: 16)
    let restoredGap = try #require(restored.document.adjacentGaps.first)
    #expect(restoredGap.distance == gap.distance)
    #expect(restored.document.gapLabelPosition(for: restoredGap) == nil)
}

@Test func wideHeightLabelsClampTheirCenterSoTheyStayOnTheirConnector() {
    let gap = GuideGap(first: Guide(axis: .horizontal, position: 100), second: Guide(axis: .horizontal, position: 500))
    let size = CGSize(width: 180, height: 24)
    let left = MeasurementReadoutLayout.gapAnchor(gap, usable: labelUsable, toolbar: .zero, orthogonalPosition: -500, labelSize: size)
    let right = MeasurementReadoutLayout.gapAnchor(gap, usable: labelUsable, toolbar: .zero, orthogonalPosition: 5000, labelSize: size)
    #expect(left == CGPoint(x: 90, y: 300))
    #expect(right == CGPoint(x: 1110, y: 300))
}

@Test func draggedLabelsAvoidTheToolbarWithoutChangingTheMeasuredAxis() {
    let toolbar = CGRect(x: 200, y: 60, width: 800, height: 140)
    let size = CGSize(width: 100, height: 24)
    for axis in GuideAxis.allCases {
        let gap = GuideGap(first: Guide(axis: axis, position: 40), second: Guide(axis: axis, position: 180))
        // Horizontal guides give a height label at y=110, inside the toolbar's vertical range.
        // Vertical guides give a width label at x=110; use a second pair inside the toolbar for that case.
        let measured = axis == .vertical
            ? GuideGap(first: Guide(axis: axis, position: 300), second: Guide(axis: axis, position: 700)) : gap
        for coordinate in stride(from: 60.0, through: 1000, by: 20) {
            let anchor = MeasurementReadoutLayout.gapAnchor(measured, usable: labelUsable, toolbar: toolbar,
                orthogonalPosition: coordinate, labelSize: size)
            let rect = CGRect(x: anchor.x - 50, y: anchor.y - 12, width: 100, height: 24)
            #expect(!rect.intersects(toolbar.insetBy(dx: -8, dy: -8)))
            #expect(labelUsable.contains(rect))
            #expect(axis == .vertical ? anchor.x == measured.midpoint : anchor.y == measured.midpoint)
        }
    }
}

@Test func toolbarAvoidanceUsesTheDrawnRectForGuidePairsAtDisplayEdges() {
    let usable = CGRect(x: 0, y: 0, width: 1024, height: 768)
    let toolbar = CGRect(x: 65.5, y: 32, width: 893, height: 132)
    let size = CGSize(width: 100, height: 24)
    for positions in [[0.0, 2], [1022.0, 1024]] {
        let gap = GuideGap(first: Guide(axis: .vertical, position: positions[0]), second: Guide(axis: .vertical, position: positions[1]))
        let requested = CGPoint(x: gap.midpoint, y: 80)
        let shifted = MeasurementReadoutLayout.labelFrame(size: size, centered: requested, usable: usable)
        #expect(shifted.intersects(toolbar)) // Reproduces the review finding after the label shifts in from the screen edge.
        let anchor = MeasurementReadoutLayout.gapAnchor(gap, usable: usable, toolbar: toolbar,
            orthogonalPosition: 80, labelSize: size)
        let drawn = MeasurementReadoutLayout.labelFrame(size: size, centered: anchor, usable: usable)
        #expect(usable.contains(drawn))
        #expect(!drawn.intersects(toolbar.insetBy(dx: -8, dy: -8)))
        #expect(anchor.x == gap.midpoint)
        #expect(gap.distance == 2)
    }
}

@Test func directionalLabelMovesCanCrossTheToolbarInBothDirections() {
    let usable = CGRect(x: 0, y: 0, width: 1200, height: 900)
    let toolbar = CGRect(x: 200, y: 100, width: 800, height: 140)
    let size = CGSize(width: 100, height: 24)
    for axis in GuideAxis.allCases {
        let gap = axis == .vertical
            ? GuideGap(first: Guide(axis: axis, position: 300), second: Guide(axis: axis, position: 700))
            : GuideGap(first: Guide(axis: axis, position: 100), second: Guide(axis: axis, position: 200))
        let lower = axis == .vertical ? CGPoint(x: 500, y: 80) : CGPoint(x: 142, y: 150)
        let upper = axis == .vertical ? CGPoint(x: 500, y: 260) : CGPoint(x: 1058, y: 150)
        let forward = MeasurementReadoutLayout.nudgedGapAnchor(gap, anchor: lower, by: 10,
            usable: usable, toolbar: toolbar, labelSize: size)
        #expect(forward == upper)
        let backward = MeasurementReadoutLayout.nudgedGapAnchor(gap, anchor: forward, by: -10,
            usable: usable, toolbar: toolbar, labelSize: size)
        #expect(backward == lower)
        let further = MeasurementReadoutLayout.nudgedGapAnchor(gap, anchor: backward, by: -10,
            usable: usable, toolbar: toolbar, labelSize: size)
        #expect(axis == .vertical ? further.y == lower.y - 10 : further.x == lower.x - 10)
        #expect(axis == .vertical ? further.x == gap.midpoint : further.y == gap.midpoint)
    }
}

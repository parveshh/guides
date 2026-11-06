import Foundation
import Testing
@testable import GuidesCore

private let annotationSize = CGSize(width: 800, height: 600)
private func draw(_ session: inout AnnotationSession, _ tool: AnnotationTool, _ a: CGPoint, _ b: CGPoint) {
    session.setTool(tool); session.begin(at: a); session.drag(to: b); session.end()
}

@Test func rectanglesNormalizeEveryDragDirectionAndStartAsSpotlights() throws {
    for end in [CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 300), CGPoint(x: 300, y: 100), CGPoint(x: 300, y: 300)] {
        var session = AnnotationSession(size: annotationSize)
        draw(&session, .rectangle, CGPoint(x: 200, y: 200), end)
        let shape = try #require(session.document.selected)
        #expect(shape.bounds.width == 100 && shape.bounds.height == 100)
        #expect(session.document.spotlight == shape.bounds)
        #expect(session.document.dimOpacity == 0.55 && session.tool == .select)
        session.undo(); #expect(session.document.shapes.isEmpty && session.document.spotlight == nil)
        session.redo(); #expect(session.document.selected?.id == shape.id)
    }
}

@Test func spotlightReplacementCancellationDeletionAndClearAreAtomic() throws {
    var session = AnnotationSession(size: annotationSize)
    draw(&session, .rectangle, CGPoint(x: 20, y: 30), CGPoint(x: 200, y: 180))
    let first = try #require(session.document.spotlightID)
    session.setTool(.rectangle); session.begin(at: CGPoint(x: 300, y: 300)); session.drag(to: CGPoint(x: 500, y: 500))
    #expect(session.document.spotlightID != first)
    let cancelled = session.cancel()
    #expect(cancelled)
    #expect(session.document.spotlightID == first && session.document.shapes.count == 1)
    draw(&session, .rectangle, CGPoint(x: 300, y: 300), CGPoint(x: 500, y: 500))
    let second = try #require(session.document.spotlightID)
    session.undo(); #expect(session.document.spotlightID == first && session.document.shapes.count == 1)
    session.redo(); #expect(session.document.spotlightID == second && session.document.shapes.count == 2)
    session.deleteSelection(); #expect(session.document.spotlight == nil && session.document.shapes.count == 1)
    session.undo(); #expect(session.document.spotlightID == second)
    session.clear(); #expect(session.document.shapes.isEmpty && session.document.spotlight == nil)
    session.undo(); #expect(session.document.shapes.count == 2 && session.document.spotlightID == second)
}

@Test func degenerateOrCancelledShapesPreserveThePreviousSpotlight() {
    var session = AnnotationSession(size: annotationSize)
    draw(&session, .rectangle, CGPoint(x: 20, y: 20), CGPoint(x: 100, y: 100))
    let before = session.document
    for tool in AnnotationTool.allCases where tool != .select {
        draw(&session, tool, CGPoint(x: 300, y: 300), CGPoint(x: 300, y: 300))
        #expect(session.document.shapes == before.shapes && session.document.spotlightID == before.spotlightID)
        #expect(session.document.selectedID == nil)
    }
    draw(&session, .rectangle, CGPoint(x: 200, y: 200), CGPoint(x: 200, y: 300))
    #expect(session.document.shapes == before.shapes && session.document.spotlightID == before.spotlightID)
    let deselected = session.document
    session.setTool(.line); session.begin(at: CGPoint(x: CGFloat.nan, y: 10))
    #expect(!session.isDragging && session.document == deselected)
}

@Test func lineAndArrowEndpointsCanBeEditedInBothDirections() throws {
    for tool in [AnnotationTool.line, .arrow] {
        var session = AnnotationSession(size: annotationSize)
        draw(&session, tool, CGPoint(x: 200, y: 200), CGPoint(x: 100, y: 100))
        session.begin(at: CGPoint(x: 100, y: 100)); session.drag(to: CGPoint(x: 350, y: 250)); session.end()
        #expect(session.document.selected?.start == CGPoint(x: 200, y: 200))
        #expect(session.document.selected?.end == CGPoint(x: 350, y: 250))
        session.undo(); #expect(session.document.selected?.end == CGPoint(x: 100, y: 100))
        session.begin(at: CGPoint(x: 200, y: 200)); session.drag(to: CGPoint(x: -20, y: 800)); session.end()
        #expect(session.document.selected?.start == CGPoint(x: 0, y: 600))
        #expect(session.document.spotlight == nil)
    }
}

@Test func movingAndResizingKeepsShapesBoundedAndOneDragIsOneUndo() throws {
    var session = AnnotationSession(size: annotationSize)
    draw(&session, .rectangle, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 250))
    let before = session.document
    session.begin(at: CGPoint(x: 150, y: 150))
    session.drag(to: CGPoint(x: 400, y: 400)); session.drag(to: CGPoint(x: 800, y: 600)); session.end()
    #expect(session.document.selected?.bounds == CGRect(x: 600, y: 450, width: 200, height: 150))
    session.undo(); #expect(session.document == before)
    session.begin(at: CGPoint(x: 100, y: 100)); session.drag(to: CGPoint(x: 400, y: 300)); session.end()
    #expect(session.document.selected?.bounds == CGRect(x: 300, y: 250, width: 100, height: 50))
    session.undo(); #expect(session.document == before)
    session.begin(at: CGPoint(x: 100, y: 100)); session.drag(to: CGPoint(x: 150, y: 150))
    session.setTool(.arrow)
    #expect(session.document.shapes == before.shapes && session.document.spotlightID == before.spotlightID)
    #expect(session.document.selectedID == nil && !session.isDragging)
}

@Test func hitTestingUsesTopmostShapeAndSelectedHandles() throws {
    var session = AnnotationSession(size: annotationSize)
    draw(&session, .rectangle, CGPoint(x: 50, y: 50), CGPoint(x: 400, y: 400))
    draw(&session, .line, CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 200))
    let line = try #require(session.document.selected)
    session.select(nil); session.begin(at: CGPoint(x: 180, y: 203)); session.end()
    #expect(session.document.selectedID == line.id)
    session.begin(at: CGPoint(x: 100, y: 200)); session.drag(to: CGPoint(x: 120, y: 220)); session.end()
    #expect(session.document.selected?.end == CGPoint(x: 300, y: 200))
    #expect(session.document.selected?.start == CGPoint(x: 120, y: 220))
    #expect(!AnnotationGeometry.hits(line, at: CGPoint(x: 180, y: 220)))
}

@Test func arrowHeadsFollowTheTipAndRemainFiniteAtShortLengths() {
    for end in [CGPoint(x: 110, y: 100), CGPoint(x: 90, y: 100), CGPoint(x: 100, y: 110), CGPoint(x: 100, y: 90)] {
        let shape = Annotation(kind: .arrow, start: CGPoint(x: 100, y: 100), end: end)
        let wings = AnnotationGeometry.arrowWings(shape)
        #expect(wings.count == 2)
        for wing in wings {
            #expect(wing.x.isFinite && wing.y.isFinite)
            #expect(AnnotationGeometry.hits(shape, at: wing))
            let direction = CGPoint(x: end.x - 100, y: end.y - 100)
            #expect((end.x - wing.x) * direction.x + (end.y - wing.y) * direction.y > 0)
        }
    }
    #expect(AnnotationGeometry.arrowWings(Annotation(kind: .arrow, start: .zero, end: .zero)).isEmpty)
}

@Test func annotationStyleSpotlightAndDimmingUndoTogether() throws {
    var session = AnnotationSession(size: annotationSize)
    draw(&session, .rectangle, CGPoint(x: 0, y: 0), CGPoint(x: 800, y: 600))
    let original = session.document
    let style = AnnotationStyle(color: .cyan, stroke: .thick)
    session.apply(style: style, spotlight: false, dimOpacity: 0.8)
    #expect(session.document.selected?.style == style && session.document.spotlight == nil && session.document.dimOpacity == 0.8)
    session.undo(); #expect(session.document == original)
    session.redo(); #expect(session.document.spotlight == nil)
    session.apply(style: style, spotlight: true, dimOpacity: 0)
    #expect(session.document.spotlight == CGRect(origin: .zero, size: annotationSize) && session.document.dimOpacity == 0)
    let beforeInvalid = session.document
    session.apply(style: style, spotlight: false, dimOpacity: .nan)
    #expect(session.document == beforeInvalid)
}

@Test func selectionNudgesDefaultsAndHistoryStayIndependent() throws {
    var session = AnnotationSession(size: annotationSize)
    session.apply(style: AnnotationStyle(color: .yellow, stroke: .thin), spotlight: false, dimOpacity: 0.55)
    #expect(!session.canUndo)
    draw(&session, .rectangle, CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 100))
    #expect(session.document.spotlight == nil && session.document.selected?.style.color == .yellow)
    let first = session.document.selectedID
    draw(&session, .arrow, CGPoint(x: 200, y: 200), CGPoint(x: 300, y: 300))
    session.cycle(backwards: true); #expect(session.document.selectedID == first)
    session.nudge(dx: 0.5, dy: 10)
    #expect(session.document.selected?.bounds.origin == CGPoint(x: 10.5, y: 20))
    session.undo(); #expect(session.document.selected?.bounds.origin == CGPoint(x: 10, y: 10))
    session.nudge(dx: -100, dy: -100)
    #expect(session.document.selected?.bounds.origin == .zero && !session.canRedo)
    session.undo(); session.undo(); session.undo()
    #expect(session.document.shapes.isEmpty)
}

@Test func quickColorChangesOnlyTheSelectionAndFutureColor() throws {
    for tool in [AnnotationTool.rectangle, .line, .arrow] {
        var session = AnnotationSession(size: annotationSize)
        draw(&session, .rectangle, CGPoint(x: 10, y: 10), CGPoint(x: 80, y: 80))
        let untouched = try #require(session.document.selected)
        draw(&session, tool, CGPoint(x: 200, y: 200), CGPoint(x: 300, y: 300))
        let selectedID = try #require(session.document.selectedID)
        session.apply(style: AnnotationStyle(color: .white, stroke: .thick), spotlight: true, dimOpacity: 0.8)
        let before = session.document

        session.setColor(.cyan)
        #expect(session.document.selected?.style == AnnotationStyle(color: .cyan, stroke: .thick))
        #expect(session.document.shapes.first == untouched)
        #expect(session.document.spotlightID == before.spotlightID && session.document.dimOpacity == 0.8)
        #expect(session.style == AnnotationStyle(color: .cyan, stroke: .thick))
        session.undo(); #expect(session.document == before)
        session.redo(); #expect(session.document.selected?.style.color == .cyan)
        session.select(nil)
        let unselected = session.document
        session.setColor(.orange)
        #expect(session.document == unselected)
        draw(&session, .line, CGPoint(x: 400, y: 400), CGPoint(x: 500, y: 500))
        #expect(session.document.selected?.style == AnnotationStyle(color: .orange, stroke: .thick))
        #expect(session.document.shapes.first(where: { $0.id == selectedID })?.style.color == .cyan)
        session.undo(); #expect(session.document == unselected)
    }
}

@Test func drawingToolsUseTheFutureColorAfterUndoOrSelectingAnOlderShape() throws {
    var session = AnnotationSession(size: annotationSize)
    session.setColor(.yellow)
    #expect(!session.canUndo)
    draw(&session, .rectangle, CGPoint(x: 20, y: 20), CGPoint(x: 100, y: 100))
    let first = try #require(session.document.selected)
    session.setColor(.cyan); session.undo()
    #expect(session.document.selected?.style.color == .yellow && session.style.color == .cyan)
    session.setTool(.line)
    #expect(session.document.selected == nil && session.style.color == .cyan)
    session.setColor(.orange)
    #expect(session.document.shapes == [first])
    draw(&session, .line, CGPoint(x: 200, y: 200), CGPoint(x: 300, y: 300))
    #expect(session.document.selected?.style.color == .orange)
    session.select(first.id)
    #expect(session.document.selected?.style.color == .yellow)
    session.setTool(.arrow)
    #expect(session.document.selected == nil && session.style.color == .orange)
    draw(&session, .arrow, CGPoint(x: 400, y: 400), CGPoint(x: 500, y: 500))
    #expect(session.document.selected?.style.color == .orange && session.document.shapes.first == first)
}

@Test func annotationsShareDisplayLifecycleButNotMeasurementState() throws {
    var sessions = DisplaySessions()
    let a = DisplayConfiguration(id: 1, size: annotationSize, backingFactor: 2)
    let b = DisplayConfiguration(id: 2, size: annotationSize, backingFactor: 1)
    sessions.synchronize([a, b])
    let value = sessions.activate(1, rootPixels: 16)
    var session = try #require(value)
    session.document.setArea(CGRect(x: 10, y: 20, width: 30, height: 40))
    session.document.add(axis: .horizontal, position: 100)
    session.calibration.setScale(percent: 200)
    let measurements = session.document
    draw(&session.annotations, .rectangle, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 300))
    sessions.save(session)
    #expect(sessions.activate(2, rootPixels: 16)?.annotations.document.shapes.isEmpty == true)
    let restored = sessions.activate(1, rootPixels: 20)
    #expect(restored?.annotations.document == session.annotations.document && restored?.annotations.canUndo == true)
    session.annotations.clear(); session.annotations.undo()
    #expect(session.document == measurements && session.calibration.pointsPerPixel == 2)
    session.document.clear(); #expect(session.annotations.document.spotlight != nil)
    let changed = DisplayConfiguration(id: 1, size: annotationSize, backingFactor: 1)
    sessions.synchronize([changed, b])
    #expect(sessions.activate(1, rootPixels: 16)?.annotations.document.shapes.isEmpty == true)
    sessions.synchronize([b]); sessions.synchronize([a, b])
    #expect(sessions.activate(1, rootPixels: 16)?.annotations.document.spotlight == nil)
}

@Test func spotlightKeepsToolbarOutsideWhenSpaceAllows() {
    let usable = CGRect(x: 0, y: 20, width: 1400, height: 880)
    let preferred = CGRect(x: 200, y: 52, width: 1000, height: 108)
    let opening = CGRect(x: 100, y: 30, width: 1200, height: 400)
    let moved = AnnotationGeometry.toolbarFrame(preferred: preferred, usable: usable, spotlight: opening)
    #expect(usable.contains(moved) && !moved.intersects(opening))
    #expect(AnnotationGeometry.toolbarFrame(preferred: preferred, usable: usable, spotlight: usable) == preferred)
    #expect(AnnotationGeometry.toolbarFrame(preferred: preferred, usable: usable, spotlight: nil) == preferred)
}

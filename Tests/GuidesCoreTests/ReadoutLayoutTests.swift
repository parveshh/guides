import Foundation
import Testing
@testable import GuidesCore

@Test func readoutStaysInsideDisplayAtEveryEdge() {
    let usable = CGRect(x: 0, y: 25, width: 1280, height: 900)
    let toolbar = CGRect(x: 230, y: 57, width: 820, height: 66)
    for point in [CGPoint(x: 0, y: 0), CGPoint(x: 1280, y: 0), CGPoint(x: 0, y: 925), CGPoint(x: 1280, y: 925)] {
        let frame = MeasurementReadoutLayout.frame(size: CGSize(width: 340, height: 76), anchor: point,
            beside: false, usable: usable, toolbar: toolbar)
        #expect(usable.contains(frame))
        #expect(!toolbar.intersects(frame))
        #expect(frame.width == 340 && frame.height == 76)
    }
}

@Test func areaReadoutAvoidsAreaAndResizeHandles() {
    let usable = CGRect(x: 0, y: 25, width: 1280, height: 900)
    let toolbar = CGRect(x: 230, y: 57, width: 820, height: 66)
    for area in [CGRect(x: 400, y: 250, width: 320, height: 160), CGRect(x: 400, y: 740, width: 320, height: 180)] {
        let frame = MeasurementReadoutLayout.frame(size: CGSize(width: 340, height: 115),
            anchor: CGPoint(x: area.midX, y: area.midY), beside: false, usable: usable, toolbar: toolbar, area: area)
        #expect(usable.contains(frame))
        #expect(!frame.intersects(area.insetBy(dx: -8, dy: -8)))
        #expect(!frame.intersects(toolbar))
    }
}

@Test func readoutMovesBelowToolbarWhenMeasurementIsNearTop() {
    let usable = CGRect(x: 0, y: 0, width: 800, height: 600)
    let toolbar = CGRect(x: 8, y: 32, width: 784, height: 106)
    let gap = GuideGap(first: Guide(axis: .vertical, position: 300), second: Guide(axis: .vertical, position: 500))
    let anchor = MeasurementReadoutLayout.gapAnchor(gap, usable: usable, toolbar: toolbar)
    let frame = MeasurementReadoutLayout.frame(size: CGSize(width: 350, height: 76), anchor: anchor,
        beside: false, usable: usable, toolbar: toolbar)
    #expect(anchor.x == 400)
    #expect(frame.minY > toolbar.maxY)
    #expect(usable.contains(frame))
}

@Test func readoutClampsOversizedContentOnNarrowDisplays() {
    let usable = CGRect(x: 0, y: 0, width: 320, height: 600)
    let frame = MeasurementReadoutLayout.frame(size: CGSize(width: 460, height: 115), anchor: CGPoint(x: 160, y: 300),
        beside: true, usable: usable, toolbar: CGRect(x: 0, y: 0, width: 320, height: 106))
    #expect(frame.width == 304)
    #expect(usable.contains(frame))
}

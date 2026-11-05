import Foundation
import CoreGraphics
import Testing
@testable import GuidesCore

@Test(arguments: [CGRect(x: 0, y: 0, width: 1440, height: 900),
                  CGRect(x: -1920, y: 200, width: 1920, height: 1080),
                  CGRect(x: 300, y: 900, width: 1440, height: 900)])
func displayCoordinatesRoundTrip(frame: CGRect) {
    let display = DisplayGeometry(frame: frame)
    let point = CGPoint(x: 32.5, y: 71.25)
    #expect(display.localPoint(fromGlobal: display.globalPoint(fromLocal: point)) == point)
    #expect(display.localPoint(fromGlobal: CGPoint(x: frame.minX, y: frame.maxY)) == .zero)
    #expect(display.localRect(fromGlobal: frame) == CGRect(origin: .zero, size: frame.size))
}

@Test func gapsArePositiveAndAxisSpecific() {
    var document = MeasurementDocument(size: CGSize(width: 1000, height: 800))
    let a = document.add(axis: .vertical, position: 132)!
    let b = document.add(axis: .vertical, position: 100)!
    _ = document.add(axis: .horizontal, position: 200)
    #expect(document.adjacentGaps.count == 1)
    #expect(document.adjacentGaps[0].distance == 32)
    document.select([a, b])
    #expect(document.selectedGap?.distance == 32)
    document.move(id: a, to: 80)
    #expect(document.selectedGap?.distance == 20)
    document.move(id: a, to: 100)
    #expect(document.adjacentGaps[0].distance == 0)
}

@Test func guideBoundsAndInvalidPositions() {
    var document = MeasurementDocument(size: CGSize(width: 100, height: 80))
    let id = document.add(axis: .horizontal, position: -10)!
    #expect(document.guides[0].position == 0)
    document.move(id: id, to: 1000)
    #expect(document.guides[0].position == 80)
    document.move(id: id, to: .infinity)
    #expect(document.guides[0].position == 80)
    #expect(document.add(axis: .vertical, position: .nan) == nil)
}

@Test func screenPointCopyIsNotCSSPoints() {
    #expect(MeasurementText.screenPoints(32) == "32 screen pt")
    #expect(MeasurementText.screenPoints(32.125) == "32.12 screen pt")
    #expect(MeasurementText.number(0) == "0")
    #expect(MeasurementText.number(-0.0001) == "0")
}

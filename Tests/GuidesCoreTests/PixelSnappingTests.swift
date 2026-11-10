import CoreGraphics
import Foundation
import Testing
@testable import GuidesCore

@Test func snappingRoundsToBackingPixelBoundaries() {
    // At 2x a boundary falls every half screen point.
    #expect(PixelSnapping.snap(300.33, backingFactor: 2) == 300.5)
    #expect(PixelSnapping.snap(300.2, backingFactor: 2) == 300)
    #expect(PixelSnapping.snap(300.5, backingFactor: 2) == 300.5)
    // At 1x only whole points are boundaries.
    #expect(PixelSnapping.snap(300.4, backingFactor: 1) == 300)
    #expect(PixelSnapping.snap(300.6, backingFactor: 1) == 301)
    // At 3x a boundary falls every third of a point.
    #expect(abs(PixelSnapping.snap(10.3, backingFactor: 3) - 31.0 / 3) < 1e-9)
    #expect(PixelSnapping.snap(0, backingFactor: 2) == 0)
    #expect(PixelSnapping.snap(CGPoint(x: 12.26, y: 7.74), backingFactor: 2) == CGPoint(x: 12.5, y: 7.5))
}

@Test func snappingIsIdempotentAndStaysOnTheDisplay() {
    for factor in [1.0, 2.0, 3.0] as [CGFloat] {
        for raw in stride(from: CGFloat(0), through: 1728, by: 0.37) {
            let snapped = PixelSnapping.snap(raw, backingFactor: factor)
            #expect(PixelSnapping.snap(snapped, backingFactor: factor) == snapped)
            #expect(abs(snapped - raw) <= 0.5 / factor + 1e-9)
            #expect(snapped >= 0 && snapped <= 1728)
        }
    }
}

@Test func snappingLeavesInvalidInputUnchanged() {
    #expect(PixelSnapping.snap(10.3, backingFactor: 0) == 10.3)
    #expect(PixelSnapping.snap(10.3, backingFactor: -2) == 10.3)
    #expect(PixelSnapping.snap(10.3, backingFactor: .nan) == 10.3)
    #expect(PixelSnapping.snap(10.3, backingFactor: .infinity) == 10.3)
    #expect(PixelSnapping.snap(CGFloat.infinity, backingFactor: 2) == .infinity)
    #expect(PixelSnapping.snap(CGFloat.nan, backingFactor: 2).isNaN)
}

@Test func snappedGuidesMeasureWholeBackingPixels() {
    var document = MeasurementDocument(size: CGSize(width: 1728, height: 1117))
    document.add(axis: .vertical, position: PixelSnapping.snap(100.21, backingFactor: 2))
    document.add(axis: .vertical, position: PixelSnapping.snap(164.77, backingFactor: 2))
    let gap = document.adjacentGaps[0]
    #expect(gap.distance == 65)
    #expect(MeasurementEngine.text(gap.distance, unit: .backingPixels, calibration: Calibration(), backingFactor: 2) == "130 backing px")
}

@Test func snappedAreaMoveKeepsSizeAndLandsOnABoundary() {
    let size = CGSize(width: 400, height: 300)
    // An Area placed freely, off the pixel grid, with a whole-pixel size.
    let rect = CGRect(x: 20.2, y: 30.3, width: 40, height: 50)
    let moved = PixelSnapping.moved(rect, dx: 10.14, dy: -5.02, within: size, backingFactor: 2)
    #expect(moved.origin == CGPoint(x: 30.5, y: 25.5))
    #expect(moved.size == rect.size)
    // The origin is exact, not within rounding error, for arbitrary movements.
    for step in stride(from: CGFloat(-20), through: 300, by: 0.173) {
        let x = PixelSnapping.moved(rect, dx: step, dy: 0, within: size, backingFactor: 2).minX
        #expect(x * 2 == (x * 2).rounded())
    }
    // The display edge still wins over snapping, including on a display that is not a whole number of pixels.
    #expect(PixelSnapping.moved(rect, dx: 1000, dy: -1000, within: size, backingFactor: 2).origin == CGPoint(x: 360, y: 0))
    let odd = PixelSnapping.moved(rect, dx: 1000, dy: 0, within: CGSize(width: 400.3, height: 300), backingFactor: 2)
    #expect(odd.maxX <= 400.3 && odd.width == 40)
}

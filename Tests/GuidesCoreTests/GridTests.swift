import Foundation
import Testing
@testable import GuidesCore

private let gridSize = CGSize(width: 100, height: 80)

@Test func gridDefaultsStartHiddenAndConfigurationRejectsInvalidValues() throws {
    let defaults = GridConfiguration()
    #expect(!defaults.isEnabled && defaults.spacing == 8 && defaults.unit == .screenPoints)
    #expect(defaults.origin == .zero && defaults.opacity == 0.25)
    for spacing: CGFloat in [0, -1, .nan, .infinity, 1_000_001] {
        #expect(throws: GridError.spacing) { try grid(spacing: spacing) }
    }
    for origin in [CGPoint(x: -1, y: 0), CGPoint(x: 0, y: -1), CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 0, y: CGFloat.infinity)] {
        #expect(throws: GridError.origin) { try grid(origin: origin) }
    }
    for opacity: CGFloat in [0, 0.09, 0.81, .nan, .infinity] {
        #expect(throws: GridError.opacity) { try grid(opacity: opacity) }
    }
}

@Test func gridConvertsAllUnitsAndRequiresExplicitCalibration() throws {
    var calibration = Calibration()
    for unit in [MeasurementUnit.designPixels, .rem] {
        #expect(throws: GridError.calibration) {
            try GridGeometry(configuration: grid(unit: unit), size: gridSize, calibration: calibration, backingFactor: 2)
        }
    }
    calibration.setScale(percent: 200)
    for (spacing, unit, expected): (CGFloat, MeasurementUnit, CGFloat) in [
        (16, .screenPoints, 16), (32, .backingPixels, 16), (8, .designPixels, 16), (0.5, .rem, 16)
    ] {
        let result = try GridGeometry(configuration: grid(spacing: spacing, unit: unit), size: gridSize,
            calibration: calibration, backingFactor: 2)
        #expect(result.spacingInPoints == expected)
        #expect(result.verticalLines == [0, 16, 32, 48, 64, 80, 96])
    }
    calibration.setRootPixels(20)
    #expect(try GridGeometry(configuration: grid(spacing: 0.5, unit: .rem), size: gridSize,
        calibration: calibration, backingFactor: 1).spacingInPoints == 20)
    calibration.setScale(percent: 50)
    #expect(try GridGeometry(configuration: grid(spacing: 16, unit: .designPixels), size: gridSize,
        calibration: calibration, backingFactor: 1).spacingInPoints == 8)
}

@Test func gridOriginDefinesAnUnroundedLatticeInBothDirections() throws {
    let configuration = try grid(spacing: 16, origin: CGPoint(x: 35, y: 20))
    let result = try GridGeometry(configuration: configuration, size: gridSize, calibration: Calibration(), backingFactor: 1)
    #expect(result.verticalLines == [3, 19, 35, 51, 67, 83, 99])
    #expect(result.horizontalLines == [4, 20, 36, 52, 68])
    let fractional = try GridGeometry(configuration: grid(spacing: 4.25, origin: CGPoint(x: 1.5, y: 2.5)),
        size: gridSize, calibration: Calibration(), backingFactor: 2)
    #expect(fractional.verticalLines.prefix(3) == [1.5, 5.75, 10])
    #expect(fractional.horizontalLines.allSatisfy { $0 >= 0 && $0 <= gridSize.height })
    let edge = try GridGeometry(configuration: grid(spacing: 20, origin: CGPoint(x: 100, y: 80)),
        size: gridSize, calibration: Calibration(), backingFactor: 1)
    #expect(edge.verticalLines == [0, 20, 40, 60, 80, 100])
    #expect(edge.horizontalLines == [0, 20, 40, 60, 80])
}

@Test func gridRejectsDenseUnboundedAndUnrepresentableGeometry() throws {
    for backing: CGFloat in [0, -1, .nan, .infinity] {
        #expect(throws: GridError.conversion) {
            try GridGeometry(configuration: grid(unit: .backingPixels), size: gridSize, calibration: Calibration(), backingFactor: backing)
        }
    }
    #expect(throws: GridError.density) {
        try GridGeometry(configuration: grid(spacing: 3.99), size: gridSize, calibration: Calibration(), backingFactor: 1)
    }
    #expect(throws: GridError.density) {
        try GridGeometry(configuration: grid(spacing: 4), size: CGSize(width: 8192, height: 80), calibration: Calibration(), backingFactor: 1)
    }
    #expect(throws: GridError.density) {
        try GridGeometry(configuration: grid(spacing: 4), size: CGSize(width: 1e300, height: 80), calibration: Calibration(), backingFactor: 1)
    }
    let bounded = try GridGeometry(configuration: grid(spacing: 4), size: CGSize(width: 8188, height: 80), calibration: Calibration(), backingFactor: 1)
    #expect(bounded.verticalLines.count == 2048)
    var calibration = Calibration(); calibration.setScale(percent: 1e300)
    #expect(throws: GridError.conversion) {
        try GridGeometry(configuration: grid(spacing: 1e6, unit: .rem), size: gridSize,
            calibration: { var value = calibration; value.setRootPixels(1e300); return value }(), backingFactor: 1)
    }
    for size in [CGSize.zero, CGSize(width: CGFloat.infinity, height: 100), CGSize(width: 100, height: -1)] {
        #expect(throws: GridError.display) { try GridGeometry(configuration: grid(), size: size, calibration: Calibration(), backingFactor: 1) }
    }
    #expect(throws: GridError.origin) {
        try GridGeometry(configuration: grid(origin: CGPoint(x: 101, y: 0)), size: gridSize, calibration: Calibration(), backingFactor: 1)
    }
}

@Test func gridRecalibrationMovesLatticeAroundTheSameOriginAndCanPause() throws {
    let config = try grid(spacing: 8, unit: .designPixels, origin: CGPoint(x: 10, y: 10))
    var calibration = Calibration(); calibration.setScale(percent: 100)
    let original = try GridGeometry(configuration: config, size: gridSize, calibration: calibration, backingFactor: 2)
    calibration.setScale(percent: 200)
    let zoomed = try GridGeometry(configuration: config, size: gridSize, calibration: calibration, backingFactor: 2)
    #expect(original.verticalLines.contains(10) && zoomed.verticalLines.contains(10))
    #expect(original.spacingInPoints == 8 && zoomed.spacingInPoints == 16)
    #expect(zoomed.summary(configuration: config, calibration: calibration).contains("200% scale"))
    calibration.setScale(percent: 25)
    #expect(throws: GridError.density) {
        try GridGeometry(configuration: config, size: gridSize, calibration: calibration, backingFactor: 2)
    }
}

@Test func gridSessionsStayIndependentAndResetOnDisplayInvalidation() throws {
    var sessions = DisplaySessions()
    let a = DisplayConfiguration(id: 1, size: gridSize, backingFactor: 1)
    let b = DisplayConfiguration(id: 2, size: gridSize, backingFactor: 2)
    sessions.synchronize([a, b])
    let firstValue = sessions.activate(1, rootPixels: 16)
    var first = try #require(firstValue)
    first.grid = try grid(spacing: 16, origin: CGPoint(x: 12, y: 20))
    first.document.add(axis: .horizontal, position: 25)
    first.document.setArea(CGRect(x: 20, y: 30, width: 40, height: 40))
    sessions.save(first)
    let secondValue = sessions.activate(2, rootPixels: 16)
    let second = try #require(secondValue)
    #expect(!second.grid.isEnabled)
    sessions.save(second)
    let restoredValue = sessions.activate(1, rootPixels: 16)
    let restored = try #require(restoredValue)
    #expect(restored.grid == first.grid && restored.document == first.document)
    #expect(!restored.history.canUndo)
    let changed = DisplayConfiguration(id: 1, size: gridSize, backingFactor: 2)
    #expect(sessions.synchronize([changed, b]) == [1])
    #expect(sessions.activate(1, rootPixels: 16)?.grid == GridConfiguration())
    sessions.synchronize([b]); sessions.synchronize([a, b])
    #expect(sessions.activate(1, rootPixels: 16)?.grid == GridConfiguration())
    #expect(DisplaySession(size: gridSize, rootPixels: 16).grid == GridConfiguration())
}

private func grid(spacing: CGFloat = 8, unit: MeasurementUnit = .screenPoints, origin: CGPoint = .zero,
                  opacity: CGFloat = 0.25) throws -> GridConfiguration {
    try GridConfiguration(isEnabled: true, spacing: spacing, unit: unit, origin: origin, opacity: opacity)
}

import CoreGraphics
import Foundation
import Testing
@testable import GuidesCore

@Test func unitsRequireExplicitCalibration() {
    let calibration = Calibration()
    #expect(MeasurementEngine.text(32, unit: .screenPoints, calibration: calibration, backingFactor: 2) == "32 screen pt")
    #expect(MeasurementEngine.text(32, unit: .backingPixels, calibration: calibration, backingFactor: 2) == "64 backing px")
    #expect(MeasurementEngine.text(32, unit: .designPixels, calibration: calibration, backingFactor: 2) == nil)
    #expect(MeasurementEngine.text(32, unit: .rem, calibration: calibration, backingFactor: 2) == nil)
}

@Test func zoomAndRemConversions() {
    var calibration = Calibration()
    let accepted = calibration.setScale(percent: 200)
    #expect(accepted)
    #expect(MeasurementEngine.text(64, unit: .designPixels, calibration: calibration, backingFactor: 2) == "32px")
    #expect(MeasurementEngine.text(64, unit: .rem, calibration: calibration, backingFactor: 2) == "2rem")
    calibration.setScale(percent: 50)
    #expect(MeasurementEngine.text(16, unit: .designPixels, calibration: calibration, backingFactor: 1) == "32px")
    calibration.setRootPixels(20)
    #expect(MeasurementEngine.text(16, unit: .rem, calibration: calibration, backingFactor: 1) == "1.6rem")
}

@Test func knownDistanceCalibrationHandlesCombinedScaling() {
    var calibration = Calibration()
    let accepted = calibration.setKnownDistance(screenPoints: 80, designPixels: 32)
    #expect(accepted)
    #expect(calibration.pointsPerPixel == 2.5)
    #expect(MeasurementEngine.text(40, unit: .designPixels, calibration: calibration, backingFactor: 2) == "16px")
}

@Test func invalidCalibrationLeavesPreviousValueUntouched() {
    var calibration = Calibration()
    calibration.setScale(percent: 125)
    let before = calibration
    for value: CGFloat in [0, -1, .nan, .infinity] {
        let acceptedScale = calibration.setScale(percent: value)
        let acceptedRoot = calibration.setRootPixels(value)
        let acceptedKnown = calibration.setKnownDistance(screenPoints: 100, designPixels: value)
        #expect(!acceptedScale)
        #expect(!acceptedRoot)
        #expect(!acceptedKnown)
        #expect(calibration == before)
    }
    let acceptedZero = calibration.setKnownDistance(screenPoints: 0, designPixels: 100)
    #expect(!acceptedZero)
}

@Test func overflowCannotBeCopied() {
    var calibration = Calibration()
    calibration.setScale(percent: 1e-300)
    #expect(MeasurementEngine.text(1e100, unit: .designPixels, calibration: calibration, backingFactor: 2) == nil)
    #expect(MeasurementEngine.text(.infinity, unit: .screenPoints, calibration: calibration, backingFactor: 2) == nil)
    #expect(MeasurementEngine.text(10, unit: .backingPixels, calibration: calibration, backingFactor: 0) == nil)
}

@Test func areaFormattingUsesTheSameConversion() {
    var calibration = Calibration()
    calibration.setScale(percent: 200)
    let rect = CGRect(x: 0, y: 0, width: 640, height: 360)
    #expect(MeasurementEngine.areaText(rect, dimension: .both, unit: .designPixels, calibration: calibration, backingFactor: 2) == "320 × 180 px")
    #expect(MeasurementEngine.areaText(rect, dimension: .height, unit: .designPixels, calibration: calibration, backingFactor: 2) == "180px")
    #expect(MeasurementEngine.text(24, unit: .rem, calibration: calibration, backingFactor: 2) == "0.75rem")
}

@MainActor @Test func preferencesPersistOnlyValidRootSizes() {
    let suite = "dev.guides.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = GuidesPreferences(defaults: defaults)
    #expect(preferences.rootPixels == 16)
    #expect(preferences.setRootPixels(18))
    #expect(!preferences.setRootPixels(.nan))
    #expect(GuidesPreferences(defaults: defaults).rootPixels == 18)
}

@MainActor @Test func malformedPreferencesRecoverToDefault() {
    let suite = "dev.guides.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(-5, forKey: "rootFontSize")
    #expect(GuidesPreferences(defaults: defaults).rootPixels == 16)
}

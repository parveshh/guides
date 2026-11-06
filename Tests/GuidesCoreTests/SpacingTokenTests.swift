import Foundation
import Testing
@testable import GuidesCore

@Test func spacingScaleParsesSmallDeclarationListsWithoutRounding() throws {
    let scale = try SpacingScale(source: " --space-0: 0px;\r\n\r\n--Space_1: .125px\n--space-fine: 1.23456789px;", tolerance: " 0.000001 ")
    #expect(scale.tokens.map(\.name) == ["--space-0", "--Space_1", "--space-fine"])
    #expect(scale.tokens.map(\.pixels) == [0, 0.125, 1.23456789])
    #expect(scale.tolerance == 0.000001)
    #expect(scale.tokens[1].cssReference == "var(--Space_1)")
    #expect(try SpacingScale(source: "\n ", tolerance: "0").tokens.isEmpty)
}

@Test func spacingScaleRejectsMalformedOrExcessiveInput() throws {
    for line in ["space: 8px", "--: 8px", "--1: 8px", "--a: -8px", "--a: nanpx", "--a: infpx",
                 "--a: 8rem", "--a: 8", "--a: 1e3px", "--a: 1000001px", "--a: 1.2.3px",
                 "--a: 8px; --b: 16px;", ":root {", "--a): 8px", "--é: 8px"] {
        #expect(throws: SpacingScaleError.line(1)) { try SpacingScale(source: line, tolerance: "1") }
    }
    #expect(throws: SpacingScaleError.line(3)) {
        try SpacingScale(source: "--a: 8px;\r\n\r\ninvalid", tolerance: "1")
    }
    #expect(throws: SpacingScaleError.duplicate("--a")) {
        try SpacingScale(source: "--a: 8px;\n--a: 16px;", tolerance: "1")
    }
    for tolerance in ["-1", "nan", "inf", "100.1", "", "1e1"] {
        #expect(throws: SpacingScaleError.tolerance) { try SpacingScale(source: "", tolerance: tolerance) }
    }
    #expect(throws: SpacingScaleError.tooLarge) {
        try SpacingScale(source: String(repeating: " ", count: 16_385), tolerance: "1")
    }
    let lines = (1...65).map { "--space-\($0): \($0)px;" }
    #expect(throws: SpacingScaleError.tooLarge) { try SpacingScale(source: lines.joined(separator: "\n"), tolerance: "1") }
    #expect(try SpacingScale(source: lines.prefix(64).joined(separator: "\n"), tolerance: "100").tokens.count == 64)
}

@Test func spacingMatchesRequireExplicitCalibrationAndFiniteMeasurements() throws {
    let scale = try SpacingScale(source: "--space-4: 16px;", tolerance: "1")
    var calibration = Calibration()
    #expect(scale.match(screenDistance: 16, calibration: calibration) == nil)
    calibration.setScale(percent: 100)
    for invalid: CGFloat in [-1, .nan, .infinity] {
        #expect(scale.match(screenDistance: invalid, calibration: calibration) == nil)
    }
    #expect(SpacingScale.empty.match(screenDistance: 16, calibration: calibration) == nil)
    calibration.setScale(percent: 1e-300)
    #expect(scale.match(screenDistance: 1e100, calibration: calibration) == nil)
}

@Test func spacingMatchesUseCalibratedPixelsIndependentlyOfRemRoot() throws {
    let scale = try SpacingScale(source: "--space-8: 32px;", tolerance: "0")
    var calibration = Calibration()
    for percent: CGFloat in [25, 50, 100, 125, 200] {
        calibration.setScale(percent: percent)
        calibration.setRootPixels(20)
        let result = try #require(scale.match(screenDistance: 32 * percent / 100, calibration: calibration))
        #expect(result.measuredPixels == 32)
        #expect(result.isExact && result.isWithinTolerance)
        #expect(result.copyReference == "var(--space-8)")
    }
}

@Test func spacingToleranceDoesNotRoundMeasurementsIntoMatches() throws {
    let scale = try SpacingScale(source: "--space-2: 8px;\n--space-4: 16px;", tolerance: "1")
    var calibration = Calibration(); calibration.setScale(percent: 100)
    for distance: CGFloat in [7, 8, 9] {
        #expect(scale.match(screenDistance: distance, calibration: calibration)?.copyReference == "var(--space-2)")
    }
    let outside = try #require(scale.match(screenDistance: 9.00001, calibration: calibration))
    #expect(!outside.isWithinTolerance && outside.copyReference == nil)
    #expect(outside.candidates.first?.name == "--space-2")
    #expect(outside.detail.contains("outside tolerance"))
    let exactOnly = try SpacingScale(source: "--zero: 0px;", tolerance: "0")
    let tiny = try #require(exactOnly.match(screenDistance: 0.0000000001, calibration: calibration))
    #expect(!tiny.isExact && tiny.copyReference == nil)
    #expect(tiny.detail.contains("<0.0001"))
}

@Test func spacingAliasesAndEqualDistanceTiesNeverPickArbitrarily() throws {
    var calibration = Calibration(); calibration.setScale(percent: 100)
    for source in ["--a: 8px;\n--b: 16px;", "--b: 16px;\n--a: 8px;"] {
        let scale = try SpacingScale(source: source, tolerance: "4")
        let tie = try #require(scale.match(screenDistance: 12, calibration: calibration))
        #expect(tie.isAmbiguous && tie.isWithinTolerance && !tie.isExact)
        #expect(Set(tie.candidates.map(\.name)) == ["--a", "--b"])
        #expect(tie.copyReference == nil)
    }
    let aliases = try SpacingScale(source: "--a: 8px;\n--alias: 8px;", tolerance: "0")
    let result = try #require(aliases.match(screenDistance: 8, calibration: calibration))
    #expect(result.isExact && result.isAmbiguous && result.copyReference == nil)
}

@MainActor @Test func spacingPreferencesPersistAndNotifyWithoutChangingMeasurements() throws {
    let suite = "dev.guides.spacing-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = GuidesPreferences(defaults: defaults)
    #expect(preferences.spacingScale == .empty)
    let scale = try SpacingScale(source: "--precise: 1.23456789px;", tolerance: "0.0000001")
    var received: SpacingScale?
    preferences.onSpacingScaleChange = { received = $0 }
    preferences.setSpacingScale(scale)
    #expect(received == scale)
    #expect(GuidesPreferences(defaults: defaults).spacingScale == scale)
    preferences.setSpacingScale(.empty)
    #expect(GuidesPreferences(defaults: defaults).spacingScale.tokens.isEmpty)
    defaults.set(["source": "--bad: 8rem;", "tolerance": "1"], forKey: "spacingScaleV1")
    #expect(GuidesPreferences(defaults: defaults).spacingScale == .empty)
}

import CoreGraphics
import Foundation
import Testing
@testable import GuidesCore

private func calibrated(percent: CGFloat) -> Calibration {
    var calibration = Calibration()
    calibration.setScale(percent: percent)
    return calibration
}

@Test func breakpointsParseAndSortByWidth() throws {
    let set = try BreakpointSet(source: " lg: 1024px;\r\nsm:640\n\n--breakpoint-md: 768.5px ;\ntablet_2: 768.5\n")
    #expect(set.breakpoints.map(\.name) == ["sm", "--breakpoint-md", "tablet_2", "lg"])
    #expect(set.breakpoints.map(\.pixels) == [640, 768.5, 768.5, 1024])
    #expect(set.breakpoints[1].label == "--breakpoint-md 768.5px")
    #expect(set.summary == "4 breakpoints")
    #expect(try BreakpointSet(source: "md: 768px").summary == "1 breakpoint")
    #expect(try BreakpointSet(source: " \n ").isEmpty && BreakpointSet.empty.isEmpty)
    #expect(try BreakpointSet(source: BreakpointSet.example).breakpoints.map(\.pixels) == [640, 768, 1024, 1280, 1536])
}

@Test func invalidBreakpointsAreRejectedWithTheirLine() {
    for bad in ["md", "md: ", "md: 48rem", "md: -768px", "md: 0", "md: 1e3", "md: 100001", "md: 768 px", "md: 7:68",
                ": 768px", "m d: 768px", "médium: 768px", "md: ７６８", String(repeating: "x", count: 33) + ": 768"] {
        #expect(throws: BreakpointError.line(2)) { try BreakpointSet(source: "sm: 640px\n" + bad) }
    }
    #expect(throws: BreakpointError.duplicate("md")) { try BreakpointSet(source: "md: 768px\nmd: 800px") }
    // Names are case-sensitive, as in the spacing scale.
    #expect((try? BreakpointSet(source: "md: 768px\nMD: 800px"))?.breakpoints.count == 2)
    let seventeen = (1...17).map { "b\($0): \($0 * 100)px" }.joined(separator: "\n")
    #expect(throws: BreakpointError.tooLarge) { try BreakpointSet(source: seventeen) }
    #expect((try? BreakpointSet(source: (1...16).map { "b\($0): \($0 * 100)px" }.joined(separator: "\n")))?.breakpoints.count == 16)
    #expect(throws: BreakpointError.tooLarge) { try BreakpointSet(source: String(repeating: "\n", count: 4097)) }
}

@Test func breakpointMarkersNeedAnExplicitScale() throws {
    let set = try BreakpointSet(source: BreakpointSet.example)
    // An assumed 100% scale must not place a CSS width on the ruler.
    #expect(set.markers(calibration: Calibration(), width: 1728).isEmpty)
    let full = set.markers(calibration: calibrated(percent: 100), width: 1728)
    #expect(full.map(\.position) == [640, 768, 1024, 1280, 1536])
    #expect(full.map(\.breakpoint.name) == ["sm", "md", "lg", "xl", "2xl"])
    // At 200% each CSS px covers two screen points; widths past the display edge are left out.
    #expect(set.markers(calibration: calibrated(percent: 200), width: 1728).map(\.position) == [1280, 1536])
    // At 50% they sit at half the distance.
    #expect(set.markers(calibration: calibrated(percent: 50), width: 1728).map(\.position) == [320, 384, 512, 640, 768])
    // A width exactly at the display edge is kept.
    #expect(set.markers(calibration: calibrated(percent: 100), width: 1536).count == 5)
    #expect(set.markers(calibration: calibrated(percent: 100), width: 1535.5).count == 4)
    for width in [0, -1, CGFloat.nan, .infinity] {
        #expect(set.markers(calibration: calibrated(percent: 100), width: width).isEmpty)
    }
    #expect(BreakpointSet.empty.markers(calibration: calibrated(percent: 100), width: 1728).isEmpty)
}

@Test func windowPresetsAreValidResizeRequests() throws {
    let all = WindowSizePreset.devices + WindowSizePreset.displays
    #expect(Set(all.map(\.id)).count == all.count)
    for preset in all {
        let height = try #require(preset.height)
        #expect(try WindowSizeRequest(width: String(preset.width), height: String(height)).size
            == CGSize(width: preset.width, height: height))
    }
    #expect(WindowSizePreset.devices[1].title == "Phone · 375 × 667")
    // Breakpoints become width-only presets; fractional or out-of-range widths cannot be a whole-point window.
    let set = try BreakpointSet(source: "sm: 640px\nodd: 700.5px\nhuge: 20000px\nlg: 1024")
    let widths = WindowSizePreset.widths(for: set)
    #expect(widths.map(\.width) == [640, 1024] && widths.allSatisfy { $0.height == nil })
    #expect(widths[0].title == "sm · 640 wide")
    #expect(WindowSizePreset.widths(for: .empty).isEmpty)
}

@Test @MainActor func breakpointPreferencePersistsAndIgnoresCorruptStorage() throws {
    let suite = "dev.guides.breakpoint-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = GuidesPreferences(defaults: defaults)
    #expect(preferences.breakpoints.isEmpty)
    var changes = 0
    preferences.onBreakpointsChange = { _ in changes += 1 }
    let set = try BreakpointSet(source: "md: 768px")
    preferences.setBreakpoints(set)
    #expect(changes == 1 && GuidesPreferences(defaults: defaults).breakpoints == set)
    defaults.set("md: 48rem", forKey: "breakpointsV1")
    #expect(GuidesPreferences(defaults: defaults).breakpoints.isEmpty)
}

@Test func breakpointLabelsNeverCoverAnotherMarkOrLabel() {
    func origins(_ positions: [CGFloat], width: CGFloat = 60, upTo: CGFloat = 1000) -> [CGFloat?] {
        BreakpointLabelLayout.origins(positions: positions, widths: positions.map { _ in width }, in: 24...upTo)
    }
    // Well-spaced marks carry their label on the right.
    #expect(origins([640, 768, 900]) == [643, 771, 903])
    // The next mark is too close on the right, so the label moves left of its own mark.
    #expect(origins([160, 192]) == [97, 195])
    // With no room on either side the label is left out; the mark is still drawn by the caller.
    #expect(origins([100, 130, 160]) == [37, nil, 163])
    #expect(origins([40, 70]) == [nil, 73])
    // At the ruler's end the label moves left, unless the previous label or mark is there.
    #expect(origins([990]) == [927])
    #expect(origins([900, 990]) == [903, nil])
    // Equal widths share one mark; their labels sit on either side of it.
    #expect(origins([500, 500]) == [437, 503])
    #expect(origins([500, 500, 500]) == [437, nil, 503])
    // Whatever the spacing, labels stay in range and clear of every mark and of each other.
    for spacing in stride(from: CGFloat(1), through: 140, by: 7.5) {
        let positions = (0..<8).map { 60 + CGFloat($0) * spacing }
        let rects = zip(positions, origins(positions, upTo: 1100)).compactMap { _, origin in origin.map { $0...($0 + 60) } }
        for rect in rects {
            #expect(rect.lowerBound >= 24 && rect.upperBound <= 1100)
            #expect(positions.allSatisfy { !(rect.lowerBound - 1...rect.upperBound + 1).contains($0) })
        }
        for (a, b) in zip(rects, rects.dropFirst()) { #expect(a.upperBound < b.lowerBound) }
    }
    #expect(BreakpointLabelLayout.origins(positions: [100], widths: [], in: 0...500) == [nil])
}

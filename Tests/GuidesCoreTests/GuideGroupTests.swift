import Foundation
import Testing
@testable import GuidesCore

@Test func independentGroupMeasurementsAndHistory() throws {
    let display = CGSize(width: 1000, height: 800)
    var groups = GuideGroups()
    var ids: [UUID] = []
    for (x, scale, gap) in [(0, 200, 48), (500, 100, 24)] {
        let id = try groups.create(name: "Pane", frame: CGRect(x: x, y: 0, width: 500, height: 600), display: display, rootPixels: 16)
        ids.append(id)
        var workspace = try groups.group(id).measurements
        for args in [["calibrate", String(scale)], ["unit", "design-px"], ["gap", "vertical", String(gap), "0"]] {
            let scoped = try GuidesCommand.parse(["group", id.uuidString] + args)
            guard case let .group(target, command) = scoped, target == id else { Issue.record("Missing target"); return }
            try CommandLineEditing.apply(command, to: &workspace)
        }
        groups.update(id, measurements: workspace)
    }
    for id in ids { #expect(try groups.group(id).measurements.copyText(backingFactor: 2) == "24px") }
    var implementation = try groups.group(ids[1]).measurements
    try CommandLineEditing.apply(.area(CGRect(x: 8, y: 16, width: 32, height: 40), 4), to: &implementation)
    try CommandLineEditing.apply(.undo, to: &implementation)
    #expect(implementation.document.area == nil && implementation.document.guides.count == 2)
    try CommandLineEditing.apply(.gap(.vertical, 0, 32), to: &implementation)
    #expect(implementation.copyText(backingFactor: 2) == "32px")
    #expect(try groups.group(ids[0]).measurements.copyText(backingFactor: 2) == "24px")
}

@Test func groupBoundsAndResizeAreAtomic() throws {
    let display = CGSize(width: 600, height: 400)
    var groups = GuideGroups()
    let rect = CGRect(x: 10, y: 10, width: 200, height: 200)
    let id = try groups.create(name: "One", frame: rect, display: display, rootPixels: 16)
    var workspace = try groups.group(id).measurements
    try CommandLineEditing.apply(.guide(.vertical, 190), to: &workspace)
    groups.update(id, measurements: workspace)
    for invalid in [rect, CGRect(x: 250, y: 0, width: -5, height: 30), CGRect(x: 590, y: 0, width: 30, height: 40)] {
        #expect(throws: CommandLineError.self) { try groups.create(name: "Other", frame: invalid, display: display, rootPixels: 16) }
    }
    #expect(throws: CommandLineError.self) {
        try groups.edit(id, name: "Renamed", frame: CGRect(x: 80, y: 50, width: 100, height: 200), display: display)
    }
    #expect(try groups.group(id).name == "One")
    try groups.edit(id, name: "Moved", frame: rect.offsetBy(dx: 60, dy: 0), display: display)
    #expect(try groups.group(id).measurements.document.guides.first?.position == 190)
    #expect(try groups.group(id).measurements.history.canUndo)
    #expect(throws: CommandLineError.self) { try GuidesCommand.parse(["group", id.uuidString, "hide"]) }
}

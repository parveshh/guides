import Foundation

public struct CommandLineError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// The local CLI accepts only explicit measurement operations, never arbitrary selectors or file paths.
public enum GuidesCommand: Equatable, Sendable {
    case status, displays, show(OverlayTool, UInt32?), pin, hide, clear, undo, redo, delete
    case guide(GuideAxis, CGFloat), gap(GuideAxis, CGFloat, CGFloat)
    case area(CGRect, CGFloat), select([UUID]), selectArea(AreaDimension)
    case unit(MeasurementUnit), calibrate(CGFloat, CGFloat?), read(String)

    public static let help = """
    Usage: guides COMMAND [ARGUMENTS]
      launch                         Open Guides (launcher script only)
      status | displays              Read current state or attached displays
      show [guides|area|annotate] [DISPLAY_ID]
      guide horizontal|vertical POSITION
      gap horizontal|vertical FIRST SECOND
      area X Y WIDTH HEIGHT [RADIUS]
      select GUIDE_ID [GUIDE_ID]      Select one guide or a parallel pair
      select area [width|height|both|radius]
      unit screen-pt|backing-px|design-px|rem
      calibrate PERCENT [ROOT_PX]     Confirm scale; optional root is saved in Settings
      read [plain|css|tailwind|variable]
      delete | clear | undo | redo   Measurement editing only
      pin | hide
      --help
    Open the current build of Guides before sending commands. All replies are JSON.
    Coordinates are display-local screen points from the top left. Geometry is exact,
    not pointer-snapped. Design px, rem and code formats require explicit calibration.
    Commands never inspect underlying apps, capture screens or request privacy access.
    """

    public static func parse(_ arguments: [String]) throws -> GuidesCommand {
        guard !arguments.isEmpty, arguments.count <= 8,
              arguments.allSatisfy({ $0.utf8.count <= 128 }) else {
            throw CommandLineError("Expected a command with at most seven bounded arguments. Use --help.")
        }
        let values = Array(arguments.dropFirst())
        func count(_ range: ClosedRange<Int>) throws {
            guard range.contains(values.count) else { throw CommandLineError("Wrong number of arguments. Use --help.") }
        }
        func number(_ index: Int) throws -> CGFloat {
            guard let value = Double(values[index]), value.isFinite else {
                throw CommandLineError("Expected a finite number: \(values[index])")
            }
            return CGFloat(value)
        }
        func axis() throws -> GuideAxis {
            guard let axis = GuideAxis(rawValue: values[0]) else { throw CommandLineError("Axis must be horizontal or vertical.") }
            return axis
        }
        switch arguments[0] {
        case "status": try count(0...0); return .status
        case "displays": try count(0...0); return .displays
        case "pin": try count(0...0); return .pin
        case "hide": try count(0...0); return .hide
        case "clear": try count(0...0); return .clear
        case "undo": try count(0...0); return .undo
        case "redo": try count(0...0); return .redo
        case "delete": try count(0...0); return .delete
        case "show":
            try count(0...2)
            let tools: [String: OverlayTool] = ["guides": .guides, "area": .area, "annotate": .annotate]
            guard let tool = values.first.map({ tools[$0] }) ?? .guides else { throw CommandLineError("Unknown tool.") }
            var display: UInt32?
            if values.count == 2 {
                guard let id = UInt32(values[1]) else { throw CommandLineError("Invalid display ID.") }
                display = id
            }
            return .show(tool, display)
        case "guide": try count(2...2); return try .guide(axis(), number(1))
        case "gap": try count(3...3); return try .gap(axis(), number(1), number(2))
        case "area":
            try count(4...5)
            return try .area(CGRect(x: number(0), y: number(1), width: number(2), height: number(3)), values.count == 5 ? number(4) : 0)
        case "select":
            try count(1...2)
            if values[0] == "area" {
                let dimensions: [String: AreaDimension] = ["width": .width, "height": .height, "both": .both, "radius": .radius]
                guard let dimension = values.count == 1 ? .both : dimensions[values[1]] else { throw CommandLineError("Unknown area dimension.") }
                return .selectArea(dimension)
            }
            let ids = values.compactMap(UUID.init(uuidString:))
            guard ids.count == values.count, Set(ids).count == ids.count else { throw CommandLineError("Expected distinct guide UUIDs.") }
            return .select(ids)
        case "unit":
            try count(1...1)
            let units: [String: MeasurementUnit] = ["screen-pt": .screenPoints, "backing-px": .backingPixels, "design-px": .designPixels, "rem": .rem]
            guard let unit = units[values[0]] else { throw CommandLineError("Unknown unit.") }
            return .unit(unit)
        case "calibrate": try count(1...2); return try .calibrate(number(0), values.count == 2 ? number(1) : nil)
        case "read":
            try count(0...1)
            let format = values.first ?? "plain"
            guard ["plain", "css", "tailwind", "variable"].contains(format) else { throw CommandLineError("Unknown read format.") }
            return .read(format)
        default: throw CommandLineError("Unknown command. Use --help.")
        }
    }
}

public enum CommandLineEditing {
    /// Validate and apply to a copy so rejected operations leave selection, geometry and history intact.
    public static func apply(_ command: GuidesCommand, to session: inout DisplaySession) throws {
        var updated = session
        let before = updated.document
        switch command {
        case let .guide(axis, position):
            try check(position, limit: axis.limit(in: updated.document.size))
            guard updated.document.guides.count < 1000 else { throw CommandLineError("CLI guide limit is 1000.") }
            updated.document.add(axis: axis, position: position)
        case let .gap(axis, first, second):
            try check(first, limit: axis.limit(in: updated.document.size)); try check(second, limit: axis.limit(in: updated.document.size))
            guard updated.document.guides.count <= 998 else { throw CommandLineError("CLI guide limit is 1000.") }
            let a = updated.document.add(axis: axis, position: first)!
            let b = updated.document.add(axis: axis, position: second)!
            updated.document.select([a, b])
        case let .area(rect, radius):
            guard [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, radius].allSatisfy(\.isFinite),
                  rect.origin.x >= 0, rect.origin.y >= 0, rect.size.width > 0, rect.size.height > 0,
                  rect.maxX <= updated.document.size.width, rect.maxY <= updated.document.size.height,
                  radius >= 0, radius <= min(rect.width, rect.height) / 2 else {
                throw CommandLineError("Area must fit inside the display with positive dimensions and a valid radius.")
            }
            updated.document.setArea(rect, id: UUID())
            _ = updated.document.setCornerRadius(radius)
            updated.areaDimension = .both
        case let .select(ids):
            let guides = ids.compactMap { id in updated.document.guides.first { $0.id == id } }
            guard !guides.isEmpty, guides.count == ids.count, guides.count <= 2,
                  Set(ids).count == ids.count, guides.allSatisfy({ $0.axis == guides[0].axis }) else {
                throw CommandLineError("Select existing guides on the same axis.")
            }
            updated.document.select(ids)
        case let .selectArea(dimension):
            guard updated.document.area != nil else { throw CommandLineError("No measured Area exists.") }
            updated.document.selectArea(); updated.areaDimension = dimension
        case let .unit(unit):
            guard !unit.requiresCalibration || updated.calibration.isConfirmed else { throw CommandLineError("Confirm calibration first.") }
            updated.unit = unit
        case let .calibrate(percent, root):
            guard updated.calibration.setScale(percent: percent), root == nil || updated.calibration.setRootPixels(root!) else {
                throw CommandLineError("Scale and rem base must be positive finite numbers.")
            }
        case .clear: updated.document.clear()
        case .delete: updated.document.deleteSelection()
        case .undo:
            guard let document = updated.history.undo(current: updated.document) else { throw CommandLineError("No measurement to undo.") }
            updated.document = document
        case .redo:
            guard let document = updated.history.redo(current: updated.document) else { throw CommandLineError("No measurement to redo.") }
            updated.document = document
        default: throw CommandLineError("This command requires the app controller.")
        }
        if command != .undo && command != .redo { updated.history.record(before: before, after: updated.document) }
        session = updated
    }

    private static func check(_ position: CGFloat, limit: CGFloat) throws {
        guard position.isFinite, position >= 0, position <= limit else { throw CommandLineError("Guide position is outside the display.") }
    }
}

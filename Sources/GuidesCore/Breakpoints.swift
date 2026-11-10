import Foundation
import CoreGraphics

public struct Breakpoint: Equatable, Sendable {
    public let name: String
    /// A viewport width in CSS px, as the user typed it.
    public let pixels: CGFloat
    public var label: String { "\(name) \(MeasurementText.number(pixels))px" }
}

/// Where a breakpoint width falls on the top ruler, in screen points from the display's left edge.
public struct BreakpointMarker: Equatable, Sendable {
    public let breakpoint: Breakpoint
    public let position: CGFloat
}

/// Breakpoint widths typed by the user. Guides never reads them from a stylesheet or a browser.
public struct BreakpointSet: Equatable, Sendable {
    public let source: String
    /// Ordered by width, then by the order they were written.
    public let breakpoints: [Breakpoint]
    public static let empty = BreakpointSet(source: "", breakpoints: [])
    /// Tailwind's default widths, written in px.
    public static let example = "sm: 640px;\nmd: 768px;\nlg: 1024px;\nxl: 1280px;\n2xl: 1536px;"
    public var isEmpty: Bool { breakpoints.isEmpty }

    private init(source: String, breakpoints: [Breakpoint]) {
        self.source = source; self.breakpoints = breakpoints
    }

    /// A small `name: 768px` list, not a CSS parser. Names are case-sensitive.
    public init(source: String) throws {
        guard source.utf8.count <= 4096 else { throw BreakpointError.tooLarge }
        var items: [Breakpoint] = []
        var names = Set<String>()
        for (offset, rawLine) in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasSuffix(";") { line.removeLast() }
            let parts = line.components(separatedBy: ":")
            guard parts.count == 2 else { throw BreakpointError.line(offset + 1) }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            if value.hasSuffix("px") { value.removeLast(2) }
            guard (1...32).contains(name.count),
                  name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
                  !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
                  let pixels = Double(value), pixels.isFinite, pixels > 0, pixels <= 100_000 else {
                throw BreakpointError.line(offset + 1)
            }
            guard names.insert(name).inserted else { throw BreakpointError.duplicate(name) }
            items.append(Breakpoint(name: name, pixels: CGFloat(pixels)))
            guard items.count <= 16 else { throw BreakpointError.tooLarge }
        }
        // A stable sort keeps the written order for equal widths.
        let sorted = items.enumerated().sorted { ($0.element.pixels, $0.offset) < ($1.element.pixels, $1.offset) }.map(\.element)
        self.init(source: source, breakpoints: sorted)
    }

    /// Markers for the widths that fit on a display `width` screen points wide. A breakpoint is a
    /// CSS px width, so nothing is placed until the scale is explicitly set.
    public func markers(calibration: Calibration, width: CGFloat) -> [BreakpointMarker] {
        guard calibration.isConfirmed, width.isFinite, width > 0 else { return [] }
        return breakpoints.compactMap { breakpoint in
            let position = breakpoint.pixels * calibration.pointsPerPixel
            guard position.isFinite, position > 0, position <= width else { return nil }
            return BreakpointMarker(breakpoint: breakpoint, position: position)
        }
    }

    public var summary: String { "\(breakpoints.count) breakpoint\(breakpoints.count == 1 ? "" : "s")" }
}

public enum BreakpointLabelLayout {
    /// The left edge of each mark's label, or nil where the label is left out. `positions` ascend.
    /// A label sits right of its mark, or left of it when the next mark or the ruler's end is in
    /// the way; it never covers another mark or label.
    public static func origins(positions: [CGFloat], widths: [CGFloat], in range: ClosedRange<CGFloat>,
                               gap: CGFloat = 3) -> [CGFloat?] {
        guard positions.count == widths.count else { return positions.map { _ in nil } }
        var result: [CGFloat?] = []
        var occupied = range.lowerBound - gap
        for (index, position) in positions.enumerated() {
            let width = widths[index]
            let next = index + 1 < positions.count ? positions[index + 1] - gap : range.upperBound
            let previous = index > 0 ? positions[index - 1] : range.lowerBound - gap
            var origin: CGFloat?
            if position + gap + width <= min(next, range.upperBound) {
                origin = position + gap
            } else if position - gap - width >= max(occupied, previous) + gap {
                origin = position - gap - width
            }
            if let origin { occupied = max(occupied, origin + width) }
            result.append(origin)
        }
        return result
    }
}

public enum BreakpointError: Error, LocalizedError, Equatable {
    case tooLarge, line(Int), duplicate(String)
    public var errorDescription: String? {
        switch self {
        case .tooLarge: "Use at most 16 breakpoints and 4 KiB of text."
        case .line(let number): "Line \(number): use name: 768px with a width above 0 up to 100000. Names use ASCII letters, digits, _ or - and are at most 32 characters."
        case .duplicate(let name): "\(name) appears more than once. Give each breakpoint a unique name."
        }
    }
}

/// A window size offered in Resize Window, in screen points.
public struct WindowSizePreset: Equatable, Sendable, Identifiable {
    public let name: String
    public let width: Int
    public let height: Int?
    public var id: String { "\(name)|\(width)|\(height ?? 0)" }
    public var title: String {
        height.map { "\(name) · \(width) × \($0)" } ?? "\(name) · \(width) wide"
    }

    /// Common sizes by device class. They are not tied to named models and set a window, not a viewport.
    public static let devices: [WindowSizePreset] = [
        WindowSizePreset(name: "Phone, small", width: 320, height: 568),
        WindowSizePreset(name: "Phone", width: 375, height: 667),
        WindowSizePreset(name: "Phone, large", width: 390, height: 844),
        WindowSizePreset(name: "Phone, largest", width: 430, height: 932),
        WindowSizePreset(name: "Tablet, portrait", width: 768, height: 1024),
        WindowSizePreset(name: "Tablet, landscape", width: 1024, height: 768),
        WindowSizePreset(name: "Laptop", width: 1280, height: 800),
        WindowSizePreset(name: "Laptop, large", width: 1440, height: 900),
    ]
    public static let displays: [WindowSizePreset] = [
        WindowSizePreset(name: "HD", width: 1280, height: 720),
        WindowSizePreset(name: "Full HD", width: 1920, height: 1080),
        WindowSizePreset(name: "QHD", width: 2560, height: 1440),
    ]

    /// Width-only presets for the user's breakpoints, treating one CSS px as one screen point
    /// (a browser at 100% zoom). Widths that are not whole screen points in range are left out.
    public static func widths(for breakpoints: BreakpointSet) -> [WindowSizePreset] {
        breakpoints.breakpoints.compactMap { breakpoint in
            guard breakpoint.pixels == breakpoint.pixels.rounded(), (1...16_384).contains(breakpoint.pixels) else { return nil }
            return WindowSizePreset(name: breakpoint.name, width: Int(breakpoint.pixels), height: nil)
        }
    }
}

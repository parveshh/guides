import Foundation
import CoreGraphics

/// Development formats for a selected manual measurement. The text is a formatted visual
/// measurement; it is never an inspected CSS property.
public enum CopyFormat: String, CaseIterable, Sendable {
    case css = "CSS", tailwind = "Tailwind"
}

/// What is selected, in unrounded screen points.
public enum CopySubject: Equatable, Sendable {
    case gap(CGFloat)
    case width(CGFloat)
    case height(CGFloat)
    case size(width: CGFloat, height: CGFloat)
    case radius(CGFloat)

    /// The CSS property and Tailwind utility prefix for each measured distance.
    var parts: [(property: String, utility: String, distance: CGFloat)] {
        switch self {
        case .gap(let value): return [("gap", "gap", value)]
        case .width(let value): return [("width", "w", value)]
        case .height(let value): return [("height", "h", value)]
        case .size(let width, let height): return [("width", "w", width), ("height", "h", height)]
        case .radius(let value): return [("border-radius", "rounded", value)]
        }
    }
}

public enum CopyFormatter {
    /// Formats `subject` from explicitly calibrated values: rem when the measurement unit is rem,
    /// otherwise design px. Returns nil until calibration is confirmed or when a value is invalid.
    public static func text(_ subject: CopySubject, format: CopyFormat, unit: MeasurementUnit,
                            calibration: Calibration) -> String? {
        let cssUnit: MeasurementUnit = unit == .rem ? .rem : .designPixels
        var pieces: [String] = []
        for part in subject.parts {
            // Design px and rem do not depend on the backing factor.
            guard let value = MeasurementEngine.text(part.distance, unit: cssUnit, calibration: calibration,
                                                     backingFactor: 1) else { return nil }
            switch format {
            case .css: pieces.append("\(part.property): \(value);")
            case .tailwind: pieces.append("\(part.utility)-[\(value)]")
            }
        }
        return pieces.joined(separator: format == .css ? "\n" : " ")
    }
}

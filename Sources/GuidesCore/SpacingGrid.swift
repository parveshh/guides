import Foundation

/// Grid geometry and settings belong to a display session, never to a measurement.
public struct GridConfiguration: Equatable, Sendable {
    public var isEnabled = false
    public let spacing: CGFloat
    public let unit: MeasurementUnit
    public let origin: CGPoint
    public let opacity: CGFloat

    public init() {
        spacing = 8; unit = .screenPoints; origin = .zero; opacity = 0.25
    }

    public init(isEnabled: Bool, spacing: CGFloat, unit: MeasurementUnit, origin: CGPoint, opacity: CGFloat) throws {
        guard spacing.isFinite, spacing > 0, spacing <= 1_000_000 else { throw GridError.spacing }
        guard origin.x.isFinite, origin.y.isFinite, origin.x >= 0, origin.y >= 0 else { throw GridError.origin }
        guard opacity.isFinite, (0.1...0.8).contains(opacity) else { throw GridError.opacity }
        self.isEnabled = isEnabled; self.spacing = spacing; self.unit = unit
        self.origin = origin; self.opacity = opacity
    }
}

public enum GridError: Error, LocalizedError, Equatable {
    case spacing, origin, opacity, calibration, conversion, density, display
    public var errorDescription: String? {
        switch self {
        case .spacing: "Enter spacing greater than 0 and no more than 1000000."
        case .origin: "Set the origin inside this display, in screen points from its top-left corner."
        case .opacity: "Choose opacity from 10% to 80%."
        case .calibration: "Set scale before using a Design px or rem grid."
        case .conversion: "This grid spacing cannot be converted. Adjust spacing or scale."
        case .density: "Increase grid spacing: use at least 4 screen points and at most 2048 lines per axis."
        case .display: "The active display is unavailable."
        }
    }
}

public struct GridGeometry: Equatable, Sendable {
    public let spacingInPoints: CGFloat
    public let verticalLines: [CGFloat]
    public let horizontalLines: [CGFloat]

    public init(configuration: GridConfiguration, size: CGSize, calibration: Calibration, backingFactor: CGFloat) throws {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { throw GridError.display }
        guard configuration.origin.x <= size.width, configuration.origin.y <= size.height else { throw GridError.origin }
        let spacing: CGFloat
        switch configuration.unit {
        case .screenPoints: spacing = configuration.spacing
        case .backingPixels:
            guard backingFactor.isFinite, backingFactor > 0 else { throw GridError.conversion }
            spacing = configuration.spacing / backingFactor
        case .designPixels, .rem:
            guard calibration.isConfirmed else { throw GridError.calibration }
            let pixels = configuration.unit == .rem ? configuration.spacing * calibration.rootPixels : configuration.spacing
            spacing = pixels * calibration.pointsPerPixel
        }
        guard spacing.isFinite, spacing > 0 else { throw GridError.conversion }
        guard spacing >= 4 else { throw GridError.density }
        spacingInPoints = spacing
        verticalLines = try Self.lines(origin: configuration.origin.x, limit: size.width, spacing: spacing)
        horizontalLines = try Self.lines(origin: configuration.origin.y, limit: size.height, spacing: spacing)
    }

    private static func lines(origin: CGFloat, limit: CGFloat, spacing: CGFloat) throws -> [CGFloat] {
        // The origin is always on the lattice. Use integer indices in both directions
        // rather than accumulating floating-point steps or walking from the origin.
        let before = floor(origin / spacing)
        let after = floor((limit - origin) / spacing)
        guard before + after + 1 <= 2048 else { throw GridError.density }
        return (-Int(before)...Int(after)).map { min(limit, max(0, origin + CGFloat($0) * spacing)) }
    }

    public func summary(configuration: GridConfiguration, calibration: Calibration) -> String {
        let amount = MeasurementText.number(configuration.spacing, decimals: 4)
        let origin = "Origin (\(MeasurementText.number(configuration.origin.x)), \(MeasurementText.number(configuration.origin.y))) screen pt"
        var text = "Grid \(amount) \(configuration.unit.rawValue) · \(origin)"
        if configuration.unit.requiresCalibration {
            text += " · \(MeasurementText.number(calibration.pointsPerPixel * 100))% scale"
            if configuration.unit == .rem { text += " · \(MeasurementText.number(calibration.rootPixels))px/rem" }
        }
        return text
    }
}

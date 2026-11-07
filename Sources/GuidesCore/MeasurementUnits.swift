import Foundation
import CoreGraphics

public enum MeasurementUnit: String, CaseIterable, Sendable {
    case screenPoints = "Screen pt", backingPixels = "Backing px", designPixels = "Design px", rem = "rem"
    public var requiresCalibration: Bool { self == .designPixels || self == .rem }
    public var suffix: String {
        switch self {
        case .screenPoints: return " screen pt"
        case .backingPixels: return " backing px"
        case .designPixels: return "px"
        case .rem: return "rem"
        }
    }
}

public struct Calibration: Equatable, Sendable {
    public private(set) var pointsPerPixel: CGFloat = 1
    public private(set) var rootPixels: CGFloat = 16
    public private(set) var isConfirmed = false
    public init(rootPixels: CGFloat = 16) {
        if rootPixels.isFinite, rootPixels > 0 { self.rootPixels = rootPixels }
    }

    @discardableResult public mutating func setRootPixels(_ value: CGFloat) -> Bool {
        guard value.isFinite, value > 0 else { return false }
        rootPixels = value
        return true
    }

    @discardableResult public mutating func setScale(percent: CGFloat) -> Bool {
        guard percent.isFinite, percent > 0 else { return false }
        return setPointsPerPixel(percent / 100)
    }

    @discardableResult public mutating func setKnownDistance(screenPoints: CGFloat, designPixels: CGFloat) -> Bool {
        guard screenPoints.isFinite, designPixels.isFinite, screenPoints > 0, designPixels > 0 else { return false }
        return setPointsPerPixel(screenPoints / designPixels)
    }

    private mutating func setPointsPerPixel(_ value: CGFloat) -> Bool {
        guard value.isFinite, value > 0, (value * 100).isFinite else { return false }
        pointsPerPixel = value
        isConfirmed = true
        return true
    }
}

public enum MeasurementEngine {
    public static func value(_ distance: CGFloat, unit: MeasurementUnit, calibration: Calibration,
                             backingFactor: CGFloat) -> CGFloat? {
        guard distance.isFinite, distance >= 0 else { return nil }
        let result: CGFloat
        switch unit {
        case .screenPoints: result = distance
        case .backingPixels:
            guard backingFactor.isFinite, backingFactor > 0 else { return nil }
            result = distance * backingFactor
        case .designPixels, .rem:
            guard calibration.isConfirmed else { return nil }
            let pixels = distance / calibration.pointsPerPixel
            result = unit == .rem ? pixels / calibration.rootPixels : pixels
        }
        return result.isFinite ? result : nil
    }

    public static func text(_ distance: CGFloat, unit: MeasurementUnit, calibration: Calibration,
                            backingFactor: CGFloat) -> String? {
        guard let result = value(distance, unit: unit, calibration: calibration, backingFactor: backingFactor) else { return nil }
        return MeasurementText.number(result, decimals: unit == .rem ? 4 : 2) + unit.suffix
    }

    public static func areaText(_ rect: CGRect, dimension: AreaDimension, unit: MeasurementUnit,
                                calibration: Calibration, backingFactor: CGFloat, cornerRadius: CGFloat = 0) -> String? {
        if dimension == .radius { return text(cornerRadius, unit: unit, calibration: calibration, backingFactor: backingFactor) }
        if dimension == .width { return text(rect.width, unit: unit, calibration: calibration, backingFactor: backingFactor) }
        if dimension == .height { return text(rect.height, unit: unit, calibration: calibration, backingFactor: backingFactor) }
        guard let width = value(rect.width, unit: unit, calibration: calibration, backingFactor: backingFactor),
              let height = value(rect.height, unit: unit, calibration: calibration, backingFactor: backingFactor) else { return nil }
        let decimals = unit == .rem ? 4 : 2
        let suffix = unit.suffix.hasPrefix(" ") ? unit.suffix : " " + unit.suffix
        return "\(MeasurementText.number(width, decimals: decimals)) × \(MeasurementText.number(height, decimals: decimals))\(suffix)"
    }
}

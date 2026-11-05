import Foundation
import CoreGraphics
import Observation

public enum RulerAppearance: String, CaseIterable, Sendable {
    case solid = "Solid"
    case transparent = "Transparent"
}

@MainActor
@Observable
public final class GuidesPreferences {
    public private(set) var rootPixels: CGFloat
    public private(set) var rulerAppearance: RulerAppearance
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored public var onRootChange: ((CGFloat) -> Void)?
    @ObservationIgnored public var onRulerAppearanceChange: ((RulerAppearance) -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: "rootFontSize")
        rootPixels = stored.isFinite && stored > 0 ? CGFloat(stored) : 16
        rulerAppearance = defaults.string(forKey: "rulerAppearance").flatMap(RulerAppearance.init(rawValue:)) ?? .solid
    }

    @discardableResult public func setRootPixels(_ value: CGFloat) -> Bool {
        guard value.isFinite, value > 0 else { return false }
        rootPixels = value
        defaults.set(Double(value), forKey: "rootFontSize")
        onRootChange?(value)
        return true
    }

    public func setRulerAppearance(_ value: RulerAppearance) {
        rulerAppearance = value
        defaults.set(value.rawValue, forKey: "rulerAppearance")
        onRulerAppearanceChange?(value)
    }
}

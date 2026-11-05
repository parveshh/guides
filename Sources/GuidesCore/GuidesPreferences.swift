import Foundation
import CoreGraphics
import Observation

@MainActor
@Observable
public final class GuidesPreferences {
    public private(set) var rootPixels: CGFloat
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored public var onRootChange: ((CGFloat) -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: "rootFontSize")
        rootPixels = stored.isFinite && stored > 0 ? CGFloat(stored) : 16
    }

    @discardableResult public func setRootPixels(_ value: CGFloat) -> Bool {
        guard value.isFinite, value > 0 else { return false }
        rootPixels = value
        defaults.set(Double(value), forKey: "rootFontSize")
        onRootChange?(value)
        return true
    }
}

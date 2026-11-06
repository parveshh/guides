import Foundation

public struct SpacingToken: Equatable, Sendable {
    public let name: String
    public let pixels: CGFloat
    public var cssReference: String { "var(\(name))" }
}

public struct SpacingScale: Equatable, Sendable {
    public let source: String
    public let tolerance: CGFloat
    public let toleranceText: String
    public let tokens: [SpacingToken]
    public static let empty = SpacingScale(source: "", tolerance: 1, toleranceText: "1", tokens: [])
    public static let example = "--space-1: 4px;\n--space-2: 8px;\n--space-3: 12px;\n--space-4: 16px;\n--space-6: 24px;\n--space-8: 32px;"

    private init(source: String, tolerance: CGFloat, toleranceText: String, tokens: [SpacingToken]) {
        self.source = source; self.tolerance = tolerance; self.toleranceText = toleranceText; self.tokens = tokens
    }

    /// A small declaration list, not a CSS parser. Names are case-sensitive.
    public init(source: String, tolerance: String) throws {
        guard source.utf8.count <= 16_384 else { throw SpacingScaleError.tooLarge }
        guard let toleranceValue = Self.decimal(tolerance), toleranceValue <= 100 else {
            throw SpacingScaleError.tolerance
        }
        var tokens: [SpacingToken] = []
        var names = Set<String>()
        for (offset, rawLine) in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasSuffix(";") { line.removeLast() }
            let parts = line.components(separatedBy: ":")
            guard parts.count == 2 else { throw SpacingScaleError.line(offset + 1) }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            let identifier = name.dropFirst(2)
            guard name.hasPrefix("--"), name.count <= 64, let first = identifier.first,
                  first.isASCII && (first.isLetter || first == "_"),
                  identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
                  value.hasSuffix("px"), let pixels = Self.decimal(String(value.dropLast(2))), pixels <= 1_000_000 else {
                throw SpacingScaleError.line(offset + 1)
            }
            guard names.insert(name).inserted else { throw SpacingScaleError.duplicate(name) }
            tokens.append(SpacingToken(name: name, pixels: pixels))
            guard tokens.count <= 64 else { throw SpacingScaleError.tooLarge }
        }
        self.init(source: source, tolerance: toleranceValue, toleranceText: tolerance, tokens: tokens)
    }

    private static func decimal(_ text: String) -> CGFloat? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              let number = Double(value), number.isFinite, number >= 0 else { return nil }
        return CGFloat(number)
    }

    public func match(screenDistance: CGFloat, calibration: Calibration) -> SpacingMatch? {
        guard !tokens.isEmpty,
              let pixels = MeasurementEngine.value(screenDistance, unit: .designPixels,
                  calibration: calibration, backingFactor: 1) else { return nil }
        let closest = tokens.min { abs(pixels - $0.pixels) < abs(pixels - $1.pixels) }!
        let nearest = abs(pixels - closest.pixels)
        // Ignore only floating-point arithmetic noise, not displayed rounding.
        let epsilon = max(pixels.ulp, closest.pixels.ulp) * 4
        let candidates = tokens.filter { abs(abs(pixels - $0.pixels) - nearest) <= epsilon }
        return SpacingMatch(measuredPixels: pixels, candidates: candidates,
            distance: nearest, isWithinTolerance: nearest <= tolerance + epsilon, isExact: nearest <= epsilon)
    }
}

public enum SpacingScaleError: Error, LocalizedError, Equatable {
    case tolerance, tooLarge, line(Int), duplicate(String)
    public var errorDescription: String? {
        switch self {
        case .tolerance: "Enter a tolerance from 0 to 100 design pixels, using a decimal point."
        case .tooLarge: "Use at most 64 tokens and 16 KiB of text."
        case .line(let number): "Line \(number): use --name: 8px; with a value from 0 to 1000000. Names use ASCII letters, digits, _ or -, start with a letter or _ after --, and are at most 64 characters."
        case .duplicate(let name): "\(name) appears more than once. Give each token a unique name."
        }
    }
}

public struct SpacingMatch: Equatable, Sendable {
    public let measuredPixels: CGFloat
    public let candidates: [SpacingToken]
    public let distance: CGFloat
    public let isWithinTolerance: Bool
    public let isExact: Bool
    public var isAmbiguous: Bool { candidates.count > 1 }
    public var copyReference: String? {
        isWithinTolerance && !isAmbiguous ? candidates.first?.cssReference : nil
    }
    public var summary: String {
        let names = candidates.map(\.name).joined(separator: ", ")
        if isAmbiguous { return "Ambiguous nearest: \(names)" }
        return "\(isExact ? "Exact" : "Nearest"): \(names)"
    }
    public var detail: String {
        let measured = MeasurementText.number(measuredPixels, decimals: 4)
        if isAmbiguous {
            return "\(measured) design px · \(isWithinTolerance ? "tied tokens; no variable selected" : "outside tolerance")"
        }
        guard let token = candidates.first else { return "" }
        let delta = measuredPixels - token.pixels
        let difference = distance > 0 && distance < 0.0001 ? "<0.0001" : MeasurementText.number(distance, decimals: 4)
        let offset = isExact ? "exact" : "\(delta < 0 ? "−" : "+")\(difference)px from token"
        return "\(measured) design px · \(offset)\(isWithinTolerance ? "" : " · outside tolerance")"
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import GuidesCore

private func calibrated(percent: CGFloat = 100, root: CGFloat = 16) -> Calibration {
    var calibration = Calibration(rootPixels: root)
    calibration.setScale(percent: percent)
    return calibration
}

@Test func cssDeclarationsForEachSubject() {
    let calibration = calibrated()
    func css(_ subject: CopySubject) -> String? {
        CopyFormatter.text(subject, format: .css, unit: .designPixels, calibration: calibration)
    }
    #expect(css(.gap(24)) == "gap: 24px;")
    #expect(css(.width(320)) == "width: 320px;")
    #expect(css(.height(48)) == "height: 48px;")
    #expect(css(.radius(8)) == "border-radius: 8px;")
    #expect(css(.size(width: 320, height: 48)) == "width: 320px;\nheight: 48px;")
}

@Test func tailwindArbitraryValuesForEachSubject() {
    let calibration = calibrated()
    func tailwind(_ subject: CopySubject) -> String? {
        CopyFormatter.text(subject, format: .tailwind, unit: .designPixels, calibration: calibration)
    }
    #expect(tailwind(.gap(24)) == "gap-[24px]")
    #expect(tailwind(.width(320)) == "w-[320px]")
    #expect(tailwind(.height(48)) == "h-[48px]")
    #expect(tailwind(.radius(8)) == "rounded-[8px]")
    #expect(tailwind(.size(width: 320, height: 48)) == "w-[320px] h-[48px]")
}

@Test func copyFormatsRequireExplicitCalibration() {
    // An unconfirmed calibration assumes 100%, which must never reach a stylesheet.
    let assumed = Calibration()
    for format in CopyFormat.allCases {
        for unit in MeasurementUnit.allCases {
            for subject in [CopySubject.gap(24), .width(320), .height(48), .size(width: 320, height: 48), .radius(8), .radius(0)] {
                #expect(CopyFormatter.text(subject, format: format, unit: unit, calibration: assumed) == nil)
            }
        }
    }
}

@Test func copyFormatsUseCalibratedPixelsOrRem() {
    // 64 screen points at 200% is 32 design px, or 2rem with a 16px root.
    let calibration = calibrated(percent: 200)
    #expect(CopyFormatter.text(.width(64), format: .css, unit: .designPixels, calibration: calibration) == "width: 32px;")
    #expect(CopyFormatter.text(.width(64), format: .css, unit: .rem, calibration: calibration) == "width: 2rem;")
    #expect(CopyFormatter.text(.width(64), format: .tailwind, unit: .rem, calibration: calibration) == "w-[2rem]")
    // Screen pt and Backing px readouts still copy calibrated design px, never points.
    #expect(CopyFormatter.text(.width(64), format: .css, unit: .screenPoints, calibration: calibration) == "width: 32px;")
    #expect(CopyFormatter.text(.gap(64), format: .tailwind, unit: .backingPixels, calibration: calibration) == "gap-[32px]")
    // The rem base changes rem output only.
    let root10 = calibrated(percent: 200, root: 10)
    #expect(CopyFormatter.text(.radius(64), format: .css, unit: .rem, calibration: root10) == "border-radius: 3.2rem;")
    #expect(CopyFormatter.text(.radius(64), format: .css, unit: .designPixels, calibration: root10) == "border-radius: 32px;")
}

@Test func copyFormatsMatchReadoutPrecision() {
    let calibration = calibrated(percent: 150)
    // 100 / 1.5 = 66.666…px and 4.1666…rem, at the readout's two and four decimals.
    #expect(CopyFormatter.text(.width(100), format: .css, unit: .designPixels, calibration: calibration) == "width: 66.67px;")
    #expect(CopyFormatter.text(.width(100), format: .tailwind, unit: .rem, calibration: calibration) == "w-[4.1667rem]")
    #expect(CopyFormatter.text(.width(100), format: .css, unit: .designPixels, calibration: calibration)
        == MeasurementEngine.text(100, unit: .designPixels, calibration: calibration, backingFactor: 2).map { "width: \($0);" })
    #expect(CopyFormatter.text(.radius(0), format: .css, unit: .designPixels, calibration: calibration) == "border-radius: 0px;")
    // Tailwind arbitrary values must not contain whitespace.
    for subject in [CopySubject.gap(33.3), .width(1234.56), .radius(0.4)] {
        let text = CopyFormatter.text(subject, format: .tailwind, unit: .rem, calibration: calibration)
        #expect(text?.contains(" ") == false)
    }
}

@Test func copyFormatsRejectInvalidDistances() {
    let calibration = calibrated()
    for format in CopyFormat.allCases {
        #expect(CopyFormatter.text(.width(.nan), format: format, unit: .designPixels, calibration: calibration) == nil)
        #expect(CopyFormatter.text(.gap(-1), format: format, unit: .designPixels, calibration: calibration) == nil)
        #expect(CopyFormatter.text(.radius(.infinity), format: format, unit: .designPixels, calibration: calibration) == nil)
        // One invalid dimension yields nothing rather than half a result.
        #expect(CopyFormatter.text(.size(width: 320, height: .nan), format: format, unit: .designPixels, calibration: calibration) == nil)
    }
}

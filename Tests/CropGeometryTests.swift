import Foundation

/// Run without an iOS simulator:
/// swiftc Crppr/CropGeometry.swift Tests/CropGeometryTests.swift -o /tmp/crppr-tests
/// /tmp/crppr-tests
@main
struct CropGeometryTests {
    static var checks = 0
    static let ratio17to10 = CropRatio(widthTenths: 17, heightTenths: 10)!

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        precondition(condition(), message)
    }

    static func main() {
        testRatioInput()
        testExactRatios()
        testEquivalentRatios()
        testBoundariesAndScale()
        testTinyAndInvalidImages()
        testAspectFit()
        print("Passed \(checks) crop geometry checks.")
    }

    static func testRatioInput() {
        for (text, expected) in [(".7", 7), ("1", 10), ("1.0", 10), ("1,5", 15),
                                 ("  1.7\n", 17), ("0.1", 1), ("16.0", 160), ("16", 160),
                                 ("1.", 10), (",7", 7), ("999.9", 9999)] {
            expect(CropRatio.parseTenths(text) == expected, "Accept valid ratio component: \(text)")
        }
        for text in ["", " ", "0", "0.0", "-1", "1000", "999.99", "1.23", "NaN", "inf", "1e0",
                     ".", ",", "1..0", "1,0.0", "+1.0", "1 0", "1\n0", "999999999999999999999"] {
            expect(CropRatio.parseTenths(text) == nil, "Reject invalid ratio component: \(text)")
        }
        for value in CropRatio.supportedComponents {
            expect(CropRatio.parseTenths(CropRatio.text(for: value)) == value,
                   "Ratio component text must round-trip exactly")
        }
        expect(CropRatio.text(for: 17) == "1.7", "Display fractional component with one decimal")
        expect(CropRatio.text(for: 10) == "1", "Display integer component without decimal suffix")
        expect(CropRatio.text(for: 160) == "16", "Preserve familiar X:Y integer components")
        expect(CropRatio.square == CropRatio(widthTenths: 10, heightTenths: 10), "Default ratio is square")
        for invalid in [Int.min, -1, 0, 10000, Int.max] {
            expect(CropRatio(widthTenths: invalid, heightTenths: 10) == nil, "Reject invalid width")
            expect(CropRatio(widthTenths: 10, heightTenths: invalid) == nil, "Reject invalid height")
        }
    }

    static func validate(_ rect: CGRect, source: CGSize, ratio: CropRatio) {
        expect(rect.width * CGFloat(ratio.heightTenths) == rect.height * CGFloat(ratio.widthTenths),
               "Width and height must preserve both exact ratio components")
        expect(rect.width > 0 && rect.height > 0, "Crop must contain pixels")
        expect(rect.minX >= 0 && rect.minY >= 0, "Crop must not cross top/left")
        expect(rect.maxX <= source.width && rect.maxY <= source.height,
               "Crop must not cross bottom/right")
        expect(rect.minX.rounded() == rect.minX && rect.minY.rounded() == rect.minY,
               "Origin must be whole pixels")
        expect(rect.width.rounded() == rect.width && rect.height.rounded() == rect.height,
               "Dimensions must be whole pixels")
    }

    static func testExactRatios() {
        let ratios = [(10, 10), (90, 160), (15, 10), (10, 15), (25, 37), (50, 74),
                      (1, 9999), (9999, 1), (9999, 9999), (9998, 9999)]
            .map { CropRatio(widthTenths: $0.0, heightTenths: $0.1)! }
        // Odd dimensions exercise the unused-pixel remainder and boundary clamps.
        for source in [CGSize(width: 4033, height: 3025),
                       CGSize(width: 1179, height: 2557),
                       CGSize(width: 2049, height: 2049),
                       CGSize(width: 20001, height: 12001)] {
            for ratio in ratios {
                for scale in [CGFloat(0.15), 0.333, 0.6, 0.9999, 1] {
                    for center in [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0, y: 0),
                                   CGPoint(x: 1, y: 1), CGPoint(x: -4, y: 7)] {
                        let rect = CropGeometry.pixelCropRect(
                            imageSize: source, center: center, scale: scale, ratio: ratio
                        )
                        if let rect {
                            validate(rect, source: source, ratio: ratio)
                        } else {
                            expect(CGFloat(ratio.unitWidth) > source.width || CGFloat(ratio.unitHeight) > source.height,
                                   "Only a ratio unit larger than the photo may fail")
                        }
                    }
                }
            }
        }
        // Exercise arbitrary independent decimal components, not just preset ratios.
        let source = CGSize(width: 4033, height: 3025)
        for width in 1...100 {
            for height in 1...100 {
                let ratio = CropRatio(widthTenths: width, heightTenths: height)!
                let rect = CropGeometry.pixelCropRect(imageSize: source, center: CGPoint(x: 0.7, y: 0.2),
                                                      scale: 0.333, ratio: ratio)!
                validate(rect, source: source, ratio: ratio)
            }
        }
        let portrait = CropRatio(widthTenths: 90, heightTenths: 160)!
        expect(CropGeometry.maxCropSize(imageSize: source, ratio: portrait)
               == CGSize(width: 1701, height: 3024), "9:16 must be exact, without rounding its quotient to 0.6")
        expect(CropGeometry.maxCropSize(imageSize: source, ratio: CropRatio(widthTenths: 15, heightTenths: 10)!)
               == CGSize(width: 4032, height: 2688), "1.5:1 must reduce to 3:2")
        expect(CropGeometry.maxCropSize(imageSize: source, ratio: CropRatio(widthTenths: 10, heightTenths: 15)!)
               == CGSize(width: 2016, height: 3024), "1:1.5 must reduce to 2:3")
        expect(CropGeometry.maxCropSize(imageSize: source, ratio: CropRatio(widthTenths: 25, heightTenths: 37)!)
               == CGSize(width: 2025, height: 2997), "2.5:3.7 must reduce to 25:37")
        expect(CropGeometry.maxCropSize(imageSize: source, ratio: .square)
               == CGSize(width: 3025, height: 3025), "Square ratio must use all available square pixels")
    }

    static func testEquivalentRatios() {
        let pairs = [((10, 10), (250, 250)), ((90, 160), (45, 80)),
                     ((15, 10), (30, 20)), ((25, 37), (50, 74))]
        for pair in pairs {
            let first = CropRatio(widthTenths: pair.0.0, heightTenths: pair.0.1)!
            let second = CropRatio(widthTenths: pair.1.0, heightTenths: pair.1.1)!
            expect(first.unitWidth == second.unitWidth && first.unitHeight == second.unitHeight,
                   "Equivalent ratio inputs must reduce to identical pixel units")
            let source = CGSize(width: 4033, height: 3025)
            let center = CGPoint(x: 0.4, y: 0.7)
            expect(CropGeometry.pixelCropRect(imageSize: source, center: center, scale: 0.6, ratio: first)
                   == CropGeometry.pixelCropRect(imageSize: source, center: center, scale: 0.6, ratio: second),
                   "Equivalent ratio inputs must produce identical crops")
        }
    }

    static func testBoundariesAndScale() {
        let size = CGSize(width: 1001, height: 801)
        let small = CropGeometry.pixelCropRect(imageSize: size, center: CGPoint(x: 0, y: 0),
                                               scale: 0, ratio: ratio17to10)!
        expect(small == CGRect(x: 0, y: 0, width: 136, height: 80), "Clamp scale at 15 percent")
        let large = CropGeometry.pixelCropRect(imageSize: size, center: CGPoint(x: 1, y: 1),
                                               scale: 100, ratio: ratio17to10)!
        expect(large == CGRect(x: 15, y: 221, width: 986, height: 580), "Clamp to bottom-right at max size")
        let nonfinite = CropGeometry.pixelCropRect(
            imageSize: size, center: CGPoint(x: CGFloat.nan, y: CGFloat.infinity),
            scale: .nan, ratio: .square
        )!
        expect(nonfinite == CGRect(x: 100, y: 0, width: 801, height: 801),
               "Non-finite interaction values must resolve to safe centered defaults")
        let center = CropGeometry.clampedCenter(CGPoint(x: -5, y: 4),
                                               cropSize: CGSize(width: 200, height: 400),
                                               imageSize: CGSize(width: 1000, height: 800))
        expect(center == CGPoint(x: 0.1, y: 0.75), "Clamp normalized center using crop dimensions")
        let fractionalSource = CropGeometry.pixelCropRect(
            imageSize: CGSize(width: 100.7, height: 80.9), center: CGPoint(x: 1, y: 1),
            scale: 1, ratio: ratio17to10
        )!
        expect(fractionalSource == CGRect(x: 15, y: 30, width: 85, height: 50),
               "A fractional source size must use whole available pixels")
    }

    static func testTinyAndInvalidImages() {
        let portrait = CropRatio(widthTenths: 90, heightTenths: 160)!
        expect(CropGeometry.pixelCropRect(imageSize: CGSize(width: 9, height: 15), center: .zero,
                                         scale: 1, ratio: portrait) == nil,
               "A crop cannot claim an exact ratio if a ratio unit cannot fit")
        expect(CropGeometry.pixelCropRect(imageSize: CGSize(width: 9, height: 16), center: .zero,
                                         scale: 0.15, ratio: portrait)?.size
               == CGSize(width: 9, height: 16), "Smallest exact crop is one reduced ratio unit")
        expect(CropGeometry.maxCropSize(imageSize: CGSize(width: 1, height: 1), ratio: .square)
               == CGSize(width: 1, height: 1), "A one-pixel square is a valid exact crop")
        for size in [CGSize.zero, CGSize(width: -10, height: 20),
                     CGSize(width: .infinity, height: 20), CGSize(width: 20, height: .nan)] {
            expect(CropGeometry.maxCropSize(imageSize: size, ratio: portrait) == nil,
                   "Invalid source size must fail safely")
        }
        let widest = CropRatio(widthTenths: 9999, heightTenths: 1)!
        expect(CropGeometry.maxCropSize(imageSize: CGSize(width: 9998, height: 10000), ratio: widest) == nil,
               "A large reduced component cannot fit a narrower source")
        expect(CropGeometry.maxCropSize(imageSize: CGSize(width: 9999, height: 10000), ratio: widest)
               == CGSize(width: 9999, height: 1), "Largest valid ratio component remains exact")
    }

    static func testAspectFit() {
        let portrait = CropGeometry.aspectFitRect(imageSize: CGSize(width: 2000, height: 4000),
                                                  in: CGRect(x: 10, y: 20, width: 400, height: 400))
        expect(portrait == CGRect(x: 110, y: 20, width: 200, height: 400),
               "Portrait preview must be centered with side letterboxing")
        let landscape = CropGeometry.aspectFitRect(imageSize: CGSize(width: 4000, height: 2000),
                                                   in: CGRect(x: 0, y: 0, width: 400, height: 400))
        expect(landscape == CGRect(x: 0, y: 100, width: 400, height: 200),
               "Landscape preview must be centered with top letterboxing")
        let source = CGSize(width: 4033, height: 3025)
        let fit = CropGeometry.aspectFitRect(imageSize: source,
                                             in: CGRect(x: 0, y: 0, width: 361, height: 417))
        let ratio = CropRatio(widthTenths: 90, heightTenths: 160)!
        let crop = CropGeometry.pixelCropRect(imageSize: source, center: CGPoint(x: 0.7, y: 0.25),
                                              scale: 0.6, ratio: ratio)!
        let factor = fit.width / source.width
        let screenRect = CGRect(x: fit.minX + crop.minX * factor,
                                y: fit.minY + crop.minY * factor,
                                width: crop.width * factor, height: crop.height * factor)
        expect(abs(screenRect.width / screenRect.height - 9.0 / 16.0) < 0.0000001,
               "Fractional preview coordinates must preserve the exact 9:16 crop ratio")
        expect(abs((screenRect.minX - fit.minX) / factor - crop.minX) < 0.000001,
               "Preview and export must refer to the same pixel position")
        expect(CropGeometry.aspectFitRect(imageSize: .zero, in: CGRect(x: 0, y: 0, width: 20, height: 20))
               == .zero, "Invalid aspect fit must be safe")
    }
}

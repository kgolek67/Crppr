import Foundation

/// Width and height are stored independently in tenths so neither component
/// loses precision when the ratio is reduced to whole-pixel dimensions.
struct CropRatio: Equatable, Sendable {
    static let supportedComponents = 1...9999
    static let square = CropRatio(widthTenths: 10, heightTenths: 10)!

    let widthTenths: Int
    let heightTenths: Int

    init?(widthTenths: Int, heightTenths: Int) {
        guard Self.supportedComponents.contains(widthTenths),
              Self.supportedComponents.contains(heightTenths) else { return nil }
        self.widthTenths = widthTenths
        self.heightTenths = heightTenths
    }

    var unitWidth: Int { widthTenths / Self.gcd(widthTenths, heightTenths) }
    var unitHeight: Int { heightTenths / Self.gcd(widthTenths, heightTenths) }

    /// Accepts a decimal point or comma and at most one fractional digit.
    /// Returns tenths without floating-point parsing or silent rounding.
    static func parseTenths(_ text: String) -> Int? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !input.isEmpty,
              input.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }) else { return nil }
        let parts = input.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let whole: Int
        if parts[0].isEmpty {
            guard parts.count == 2, !parts[1].isEmpty else { return nil }
            whole = 0
        } else {
            guard let value = Int(parts[0]), value <= supportedComponents.upperBound / 10 else {
                return nil
            }
            whole = value
        }
        var decimal = 0
        if parts.count == 2 {
            guard parts[1].count <= 1 else { return nil }
            if !parts[1].isEmpty {
                guard let value = Int(parts[1]) else { return nil }
                decimal = value
            }
        }
        let tenths = whole * 10 + decimal
        return supportedComponents.contains(tenths) ? tenths : nil
    }

    static func text(for tenths: Int) -> String {
        tenths.isMultiple(of: 10) ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a
        var b = b
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return a
    }
}

/// Pixel-aligned crop calculations shared by the preview and the exported image.
/// Both ratio components are reduced together without rounding their quotient.
enum CropGeometry {
    static let minimumScale: CGFloat = 0.15

    /// Largest rectangle made of whole-pixel multiples of the reduced ratio.
    static func maxCropSize(imageSize: CGSize, ratio: CropRatio) -> CGSize? {
        guard valid(imageSize) else { return nil }
        let unitWidth = CGFloat(ratio.unitWidth)
        let unitHeight = CGFloat(ratio.unitHeight)
        let units = floor(min(floor(imageSize.width) / unitWidth,
                              floor(imageSize.height) / unitHeight))
        guard units >= 1 else { return nil }
        return CGSize(width: units * unitWidth, height: units * unitHeight)
    }

    /// Returns an in-bounds, integer-pixel rectangle whose dimensions have the
    /// requested ratio exactly. No image stretching or approximate ratio is used.
    /// A tiny source that cannot fit one ratio unit returns nil.
    static func pixelCropRect(
        imageSize: CGSize,
        center: CGPoint,
        scale: CGFloat,
        ratio: CropRatio
    ) -> CGRect? {
        guard let maximum = maxCropSize(imageSize: imageSize, ratio: ratio) else {
            return nil
        }
        let unitWidth = CGFloat(ratio.unitWidth)
        let unitHeight = CGFloat(ratio.unitHeight)
        let fraction = scale.isFinite ? min(1, max(minimumScale, scale)) : 1
        let units = max(1, floor(maximum.width / unitWidth * fraction))
        let size = CGSize(width: units * unitWidth, height: units * unitHeight)
        let bounds = CGSize(width: floor(imageSize.width), height: floor(imageSize.height))
        // Clamp the pixel origin directly. Clamping a normalized center first
        // can lose a pixel at the far edge through floating-point subtraction.
        let normalizedCenter = CGPoint(
            x: center.x.isFinite ? min(1, max(0, center.x)) : 0.5,
            y: center.y.isFinite ? min(1, max(0, center.y)) : 0.5
        )
        let x = min(bounds.width - size.width,
                    max(0, floor(normalizedCenter.x * bounds.width - size.width / 2)))
        let y = min(bounds.height - size.height,
                    max(0, floor(normalizedCenter.y * bounds.height - size.height / 2)))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Clamps a normalized center so the entire crop stays inside the image.
    static func clampedCenter(
        _ center: CGPoint,
        cropSize: CGSize,
        imageSize: CGSize
    ) -> CGPoint {
        guard valid(imageSize), valid(cropSize) else { return CGPoint(x: 0.5, y: 0.5) }
        let halfWidth = min(0.5, cropSize.width / imageSize.width / 2)
        let halfHeight = min(0.5, cropSize.height / imageSize.height / 2)
        let x = center.x.isFinite ? center.x : 0.5
        let y = center.y.isFinite ? center.y : 0.5
        return CGPoint(x: min(1 - halfWidth, max(halfWidth, x)),
                       y: min(1 - halfHeight, max(halfHeight, y)))
    }

    /// Position and size of the full source image when fitted into a preview.
    static func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard valid(imageSize), valid(bounds.size),
              bounds.origin.x.isFinite, bounds.origin.y.isFinite else { return .zero }
        let factor = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * factor, height: imageSize.height * factor)
        return CGRect(x: bounds.midX - size.width / 2,
                      y: bounds.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }

    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

}

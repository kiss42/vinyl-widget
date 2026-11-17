import AppKit
import CoreGraphics

/// A small, local artwork sampler. This is our own palette, not Spotify's algorithm.
enum ArtworkPalette {
    private struct Bucket {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0
    }

    static func theme(for image: CGImage) -> Theme? {
        let side = 48
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var buckets = [Int: Bucket]()
        var total = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[i + 3] >= 240 else { continue }
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            let key = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5)
            var bucket = buckets[key, default: Bucket()]
            bucket.count += 1; bucket.red += r; bucket.green += g; bucket.blue += b
            buckets[key] = bucket
            total += 1
        }
        guard total > 0 else { return nil }

        var bestScore = -Double.infinity
        var bestHue: CGFloat = 0
        var bestSaturation: CGFloat = 0
        // Ignore tiny specks; prefer visible saturated colors while retaining a
        // neutral result for genuinely black-and-white artwork.
        for key in buckets.keys.sorted() {
            guard let bucket = buckets[key], bucket.count >= max(2, total / 200) else { continue }
            let n = CGFloat(bucket.count) * 255
            let color = NSColor(srgbRed: CGFloat(bucket.red) / n,
                                green: CGFloat(bucket.green) / n,
                                blue: CGFloat(bucket.blue) / n, alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let score = sqrt(Double(bucket.count)) * (0.20 + Double(saturation) * 2.0)
                * (0.35 + Double(brightness) * 0.65)
            if score > bestScore {
                bestScore = score; bestHue = hue; bestSaturation = saturation
            }
        }
        guard bestScore.isFinite else { return nil }
        let s = bestSaturation < 0.08 ? 0 : min(max(bestSaturation, 0.28), 0.85)
        func hex(_ saturation: CGFloat, _ brightness: CGFloat) -> String {
            let rgb = NSColor(calibratedHue: bestHue, saturation: saturation,
                              brightness: brightness, alpha: 1).usingColorSpace(.sRGB)!
            return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                          Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
        }
        // Keep the control card dark and its text light regardless of the cover.
        return Theme(name: "Artwork", cardTop: hex(s * 0.55, 0.78),
                     cardBottom: hex(s * 0.80, 0.56), vinyl: hex(s * 0.50, 0.10),
                     panel: hex(s * 0.45, 0.12), knob: hex(s * 0.45, 0.22),
                     accent: hex(s * 0.65, 0.95), text: "#FFFDF9",
                     arm: hex(s * 0.20, 0.90))
    }
}

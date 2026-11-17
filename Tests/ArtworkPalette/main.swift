import AppKit
import CoreGraphics

func image(background: NSColor, accent: NSColor? = nil) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8,
                        bytesPerRow: 48 * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                            CGBitmapInfo.byteOrder32Big.rawValue)!
    ctx.setFillColor(background.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
    if let accent {
        ctx.setFillColor(accent.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 12, height: 48))
    }
    return ctx.makeImage()!
}

func rgb(_ hex: String) -> (Double, Double, Double) {
    let value = Int(hex.dropFirst(), radix: 16)!
    return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255,
            Double(value & 255) / 255)
}

func luminance(_ hex: String) -> Double {
    let (r, g, b) = rgb(hex)
    func linear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

let red = ArtworkPalette.theme(for: image(background: .red))!
let blue = ArtworkPalette.theme(for: image(background: .white, accent: .blue))!
let gray = ArtworkPalette.theme(for: image(background: .black))!
let (rr, rg, rb) = rgb(red.cardTop)
let (br, bg, bb) = rgb(blue.cardTop)
let (gr, gg, gb) = rgb(gray.cardTop)
precondition(rr > rg && rr > rb, "Red artwork should produce a red theme")
precondition(bb > br && bb > bg, "A prominent blue accent should survive a white background")
precondition(abs(gr - gg) < 0.02 && abs(gg - gb) < 0.02, "Black artwork should stay neutral")
precondition(ArtworkPalette.theme(for: image(background: .clear)) == nil, "Transparent art has no palette")
precondition(red == ArtworkPalette.theme(for: image(background: .red)), "Extraction should be deterministic")
for theme in [red, blue, gray] {
    let contrast = (luminance(theme.text) + 0.05) / (luminance(theme.panel) + 0.05)
    precondition(contrast >= 4.5, "Panel text needs sufficient contrast")
}
print("Artwork palette checks passed")

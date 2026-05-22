import Foundation
import UIKit

/// Tools for trimming the heavy whitespace margin that Nano Banana puts around
/// its subject. We need this both at generation time (to store a tight blob)
/// and at display time (to fix images that were saved with whitespace before
/// this code existed).
enum IconCropping {
    /// In-memory cache of (data identity → cropped UIImage). Keyed by an
    /// inexpensive hash of the raw bytes so we don't re-crop every render.
    private static var cache: [Int: UIImage] = [:]

    /// Returns the cropped UIImage for some PNG/JPEG bytes — using the cache
    /// when we've seen these bytes before.
    static func cropped(_ data: Data) -> UIImage? {
        let key = data.count.hashValue ^ data.prefix(16).hashValue
        if let cached = cache[key] { return cached }
        guard let original = UIImage(data: data) else { return nil }
        let trimmed = original.croppedToContent() ?? original
        cache[key] = trimmed
        return trimmed
    }

    /// Same idea, but returns PNG bytes — used by IconGenerator to store a
    /// tight blob so future renders skip the crop step entirely.
    static func croppedPNGData(_ data: Data) -> Data? {
        guard let img = UIImage(data: data),
              let trimmed = img.croppedToContent() else { return data }
        return trimmed.pngData() ?? data
    }
}

extension UIImage {
    /// Finds the bounding box of all "non-near-white" pixels and returns a
    /// new UIImage cropped to that box (with 4% padding). Returns nil if the
    /// image is empty / all white.
    ///
    /// "Near-white" means any channel with brightness ≥ threshold (default
    /// 240/255 ≈ 0.94). That keeps the soft anti-aliased halo around lines
    /// from being mistaken for content.
    func croppedToContent(threshold: UInt8 = 240) -> UIImage? {
        guard let cg = cgImage else { return nil }
        let w = cg.width
        let h = cg.height
        let bytesPerRow = cg.bytesPerRow
        let bytesPerPixel = max(1, cg.bitsPerPixel / 8)

        guard let provider = cg.dataProvider,
              let pixelData = provider.data,
              let bytes = CFDataGetBytePtr(pixelData) else { return nil }

        var minX = w, minY = h, maxX = -1, maxY = -1

        // Sample every other row/column — plenty of resolution for finding
        // the bounding box and 4× faster than full scan.
        let step = 2
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                let off = y * bytesPerRow + x * bytesPerPixel
                let r = bytes[off]
                let g = bytes[off + 1]
                let b = bytes[off + 2]
                if r < threshold || g < threshold || b < threshold {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard maxX > minX, maxY > minY else { return nil }

        // 4% padding so strokes don't touch the edge.
        let pad = Int(Double(max(w, h)) * 0.04)
        let x0 = max(0, minX - pad)
        let y0 = max(0, minY - pad)
        let x1 = min(w, maxX + pad)
        let y1 = min(h, maxY + pad)

        // Force square aspect so the icon doesn't look stretched in a square
        // frame. Take the longer edge and center on the bbox midpoint.
        let cropW = x1 - x0
        let cropH = y1 - y0
        let side = max(cropW, cropH)
        let cx = (x0 + x1) / 2
        let cy = (y0 + y1) / 2
        let sx = max(0, min(w - side, cx - side / 2))
        let sy = max(0, min(h - side, cy - side / 2))

        let rect = CGRect(x: sx, y: sy, width: side, height: side)
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}

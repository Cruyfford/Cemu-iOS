import UIKit

/// Minimal TGA decoder for Wii U icons (iconTex.tga): truecolor 24/32 bpp, raw or RLE.
enum TGAImage {
    private static let cache = NSCache<NSURL, UIImage>()

    static func load(_ url: URL) -> UIImage? {
        if let img = cache.object(forKey: url as NSURL) { return img }
        guard let data = try? Data(contentsOf: url), let img = decode(data) else { return nil }
        cache.setObject(img, forKey: url as NSURL)
        return img
    }

    static func decode(_ data: Data) -> UIImage? {
        let b = [UInt8](data)
        guard b.count > 18 else { return nil }
        let idLength = Int(b[0])
        let colorMapType = b[1]
        let imageType = b[2]
        let width = Int(b[12]) | Int(b[13]) << 8
        let height = Int(b[14]) | Int(b[15]) << 8
        let bpp = Int(b[16])
        let descriptor = b[17]
        guard colorMapType == 0, imageType == 2 || imageType == 10,
              bpp == 24 || bpp == 32, width > 0, height > 0, width <= 4096, height <= 4096 else { return nil }
        let bytesPerPixel = bpp / 8
        var src = 18 + idLength
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let pixelCount = width * height

        func put(_ index: Int, _ p: Int) {
            rgba[index * 4 + 0] = b[p + 2]
            rgba[index * 4 + 1] = b[p + 1]
            rgba[index * 4 + 2] = b[p + 0]
            rgba[index * 4 + 3] = bytesPerPixel == 4 ? b[p + 3] : 255
        }

        if imageType == 2 {
            guard b.count >= src + pixelCount * bytesPerPixel else { return nil }
            for i in 0..<pixelCount { put(i, src + i * bytesPerPixel) }
        } else {
            var i = 0
            while i < pixelCount {
                guard src < b.count else { return nil }
                let header = Int(b[src]); src += 1
                let count = (header & 0x7F) + 1
                if header & 0x80 != 0 {
                    guard src + bytesPerPixel <= b.count else { return nil }
                    for _ in 0..<count where i < pixelCount { put(i, src); i += 1 }
                    src += bytesPerPixel
                } else {
                    for _ in 0..<count where i < pixelCount {
                        guard src + bytesPerPixel <= b.count else { return nil }
                        put(i, src); i += 1; src += bytesPerPixel
                    }
                }
            }
        }

        // TGA origin is bottom-left unless bit 5 of the descriptor is set
        if descriptor & 0x20 == 0 {
            let row = width * 4
            for y in 0..<(height / 2) {
                let a = y * row, c = (height - 1 - y) * row
                for x in 0..<row { rgba.swapAt(a + x, c + x) }
            }
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}

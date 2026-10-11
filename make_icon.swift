#!/usr/bin/env swift
// Usage: swift make_icon.swift <source_logo.png> <output_dir>
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: make_icon.swift <source_logo.png> <output_dir>")
    exit(1)
}
let sourcePath = args[1]
let outDir = args[2]

guard let srcImage = NSImage(contentsOfFile: sourcePath),
      let srcTiff = srcImage.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: srcTiff) else {
    print("failed to load source: \(sourcePath)"); exit(1)
}

// Crop the source to its opaque bounding box so centred placement works even
// when the artwork is off-centre in a lot of transparent padding.
func opaqueBounds(of rep: NSBitmapImageRep) -> CGRect {
    let w = rep.pixelsWide, h = rep.pixelsHigh
    var minX = w, minY = h, maxX = 0, maxY = 0
    guard let data = rep.bitmapData else { return CGRect(x: 0, y: 0, width: w, height: h) }
    let bpr = rep.bytesPerRow
    let spp = rep.samplesPerPixel
    for y in 0..<h {
        for x in 0..<w {
            let a = data[y * bpr + x * spp + (spp - 1)]
            if a > 10 {
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
            }
        }
    }
    if minX > maxX || minY > maxY { return CGRect(x: 0, y: 0, width: w, height: h) }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let bounds = opaqueBounds(of: srcRep)
print("source: \(srcRep.pixelsWide)x\(srcRep.pixelsHigh), opaque bounds: \(bounds)")

// Pre-cropped CGImage for fast re-use.
let srcCG: CGImage = {
    let full = srcRep.cgImage!
    return full.cropping(to: bounds) ?? full
}()

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocusFlipped(false)
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.22

    // 1. Rounded-square clip.
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    bgPath.addClip()

    // 2. Diagonal background gradient — pale cream → warm pale orange,
    //    chosen to complement the orange circuit traces in the logo.
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let topLeft    = CGColor(srgbRed: 1.00, green: 0.99, blue: 0.96, alpha: 1)
    let bottomRight = CGColor(srgbRed: 1.00, green: 0.85, blue: 0.62, alpha: 1)
    let bg = CGGradient(colorsSpace: colorSpace,
                        colors: [topLeft, bottomRight] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0),
                           options: [])

    // 3. Subtle top-highlight for depth.
    let hi = CGGradient(colorsSpace: colorSpace,
                        colors: [CGColor(gray: 1, alpha: 0.35),
                                 CGColor(gray: 1, alpha: 0)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(hi,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: 0, y: size * 0.55),
                           options: [])

    // 4. Composite the cropped logo centred, scaled to fit with ~12% padding.
    let padding = size * 0.12
    let avail = size - padding * 2
    let srcAspect = CGFloat(srcCG.width) / CGFloat(srcCG.height)
    let targetW: CGFloat
    let targetH: CGFloat
    if srcAspect >= 1 {
        targetW = avail
        targetH = avail / srcAspect
    } else {
        targetH = avail
        targetW = avail * srcAspect
    }
    let drawRect = CGRect(
        x: (size - targetW) / 2,
        y: (size - targetH) / 2,
        width: targetW,
        height: targetH
    )

    // Soft shadow under the artwork.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.03,
                  color: CGColor(gray: 0, alpha: 0.25))
    ctx.draw(srcCG, in: drawRect)
    ctx.restoreGState()

    return image
}

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        print("encode failed \(path)"); return
    }
    // Lock pixel size (NSImage.tiffRepresentation uses points, not pixels).
    rep.size = image.size
    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("png encode failed \(path)"); return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let outputs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in outputs {
    let img = renderIcon(size: size)
    writePNG(img, to: "\(outDir)/\(name)")
}

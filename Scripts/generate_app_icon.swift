import AppKit

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent("DiskCheck/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sizes: [Int] = [16, 32, 128, 256, 512, 1024]

for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let background = NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08))
        NSColor(calibratedRed: 0.12, green: 0.52, blue: 0.98, alpha: 1).setFill()
        background.fill()

        let inner = NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22))
        NSColor(calibratedWhite: 1, alpha: 0.92).setStroke()
        inner.lineWidth = max(1, CGFloat(size) * 0.05)
        inner.stroke()

        let segmentCount = 6
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let outerRadius = rect.width * 0.34
        let innerRadius = rect.width * 0.18
        for index in 0..<segmentCount {
            let start = CGFloat(index) / CGFloat(segmentCount) * .pi * 2 - .pi / 2
            let end = CGFloat(index + 1) / CGFloat(segmentCount) * .pi * 2 - .pi / 2
            let path = NSBezierPath()
            path.appendArc(
                withCenter: center,
                radius: outerRadius,
                startAngle: start * 180 / .pi,
                endAngle: end * 180 / .pi
            )
            path.appendArc(
                withCenter: center,
                radius: innerRadius,
                startAngle: end * 180 / .pi,
                endAngle: start * 180 / .pi,
                clockwise: true
            )
            path.close()
            let colors: [NSColor] = [
                .systemOrange, .systemGreen, .systemBlue, .systemPurple, .systemTeal, .systemPink,
            ]
            colors[index % colors.count].withAlphaComponent(0.95).setFill()
            path.fill()
        }

        let title = "DC"
        let font = NSFont.systemFont(ofSize: CGFloat(size) * 0.18, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let text = NSString(string: title)
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2 - rect.height * 0.02,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)

        return true
    }

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        fputs("Failed to render icon size \(size)\n", stderr)
        exit(1)
    }

    let filename = "icon_\(size).png"
    try png.write(to: outputDirectory.appendingPathComponent(filename))
    print("Wrote \(filename)")
}

let contents = """
{
  "images" : [
    { "filename" : "icon_16.png",  "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png",  "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_1024.png","idiom" : "mac", "scale" : "2x", "size" : "256x256" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""

try contents.write(
    to: outputDirectory.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)

print("App icon set generated at \(outputDirectory.path)")

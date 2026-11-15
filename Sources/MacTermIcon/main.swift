import AppKit
import Foundation

/// 使用 AppKit CoreGraphics 在云端生成标准 macOS ICNS 多尺寸图标。
enum MacTermIcon {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw IconError.outputDirectory }
        let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        let variants: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
        ]
        for (name, size) in variants { try draw(size: size).writePNG(to: iconset.appendingPathComponent(name)) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["--convert", "icns", "--output", resources.appendingPathComponent("AppIcon.icns").path,
                             iconset.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw IconError.conversion }
        try FileManager.default.removeItem(at: iconset)
    }

    private static func draw(size: Int) -> NSBitmapImageRep {
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: representation)!
        NSGraphicsContext.current = context
        context.imageInterpolation = NSImageInterpolation.high
        let scale = CGFloat(size) / 1024
        context.cgContext.scaleBy(x: scale, y: scale)

        let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 214, yRadius: 214)
        NSGradient(colors: [NSColor(calibratedRed: 0.07, green: 0.17, blue: 0.31, alpha: 1),
                            NSColor(calibratedRed: 0.025, green: 0.075, blue: 0.16, alpha: 1)])!
            .draw(in: background, angle: -45)
        NSColor(calibratedRed: 0.18, green: 0.92, blue: 0.80, alpha: 0.13).setStroke()
        background.lineWidth = 14
        background.stroke()

        let terminal = NSBezierPath(roundedRect: NSRect(x: 142, y: 234, width: 740, height: 536), xRadius: 78, yRadius: 78)
        NSColor(calibratedRed: 0.025, green: 0.09, blue: 0.17, alpha: 0.92).setFill()
        terminal.fill()
        NSColor(calibratedRed: 0.25, green: 0.88, blue: 0.81, alpha: 0.76).setStroke()
        terminal.lineWidth = 12
        terminal.stroke()

        let prompt = NSBezierPath()
        prompt.lineCapStyle = .round
        prompt.lineJoinStyle = .round
        prompt.lineWidth = 54
        prompt.move(to: NSPoint(x: 290, y: 585))
        prompt.line(to: NSPoint(x: 416, y: 500))
        prompt.line(to: NSPoint(x: 290, y: 415))
        NSColor(calibratedRed: 0.31, green: 0.96, blue: 0.82, alpha: 1).setStroke()
        prompt.stroke()
        let cursor = NSBezierPath(roundedRect: NSRect(x: 474, y: 386, width: 176, height: 30), xRadius: 15, yRadius: 15)
        NSColor(calibratedRed: 0.35, green: 0.71, blue: 1, alpha: 1).setFill()
        cursor.fill()

        for (center, radius, color) in [
            (NSPoint(x: 310, y: 832), CGFloat(30), NSColor(calibratedRed: 0.35, green: 0.96, blue: 0.83, alpha: 1)),
            (NSPoint(x: 512, y: 872), CGFloat(24), NSColor(calibratedRed: 0.34, green: 0.70, blue: 1, alpha: 1)),
            (NSPoint(x: 714, y: 832), CGFloat(30), NSColor(calibratedRed: 0.35, green: 0.96, blue: 0.83, alpha: 1))
        ] {
            let node = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                  width: radius * 2, height: radius * 2))
            color.setFill()
            node.fill()
        }
        let connector = NSBezierPath()
        connector.lineWidth = 12
        connector.lineCapStyle = .round
        connector.move(to: NSPoint(x: 346, y: 844))
        connector.line(to: NSPoint(x: 476, y: 870))
        connector.move(to: NSPoint(x: 548, y: 870))
        connector.line(to: NSPoint(x: 678, y: 844))
        NSColor(calibratedRed: 0.39, green: 0.69, blue: 0.94, alpha: 0.9).setStroke()
        connector.stroke()

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }
}

private enum IconError: Error { case outputDirectory, conversion }

extension NSBitmapImageRep {
    func writePNG(to destination: URL) throws {
        guard let data = representation(using: .png, properties: [:]) else { throw IconError.conversion }
        try data.write(to: destination, options: .atomic)
    }
}

try MacTermIcon.main()

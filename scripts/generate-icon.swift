#!/usr/bin/env swift

import AppKit
import Foundation

// Icon sizes for macOS app
let iconSizes: [(size: Int, scale: Int, suffix: String)] = [
    (16, 1, "16x16"),
    (16, 2, "16x16@2x"),
    (32, 1, "32x32"),
    (32, 2, "32x32@2x"),
    (128, 1, "128x128"),
    (128, 2, "128x128@2x"),
    (256, 1, "256x256"),
    (256, 2, "256x256@2x"),
    (512, 1, "512x512"),
    (512, 2, "512x512@2x"),
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.2
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Background gradient (blue to purple)
    let gradient = NSGradient(colors: [
        NSColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1.0),
        NSColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 1.0)
    ])!
    gradient.draw(in: path, angle: -45)

    // Film frame icon
    let filmRect = NSRect(
        x: size * 0.15,
        y: size * 0.25,
        width: size * 0.45,
        height: size * 0.5
    )

    // Film background
    NSColor.white.withAlphaComponent(0.95).setFill()
    let filmPath = NSBezierPath(roundedRect: filmRect, xRadius: size * 0.03, yRadius: size * 0.03)
    filmPath.fill()

    // Film sprocket holes
    NSColor(white: 0.2, alpha: 1.0).setFill()
    let holeWidth = size * 0.04
    let holeHeight = size * 0.06
    let holeSpacing = size * 0.1

    for i in 0..<4 {
        let y = filmRect.minY + size * 0.08 + CGFloat(i) * holeSpacing
        // Left holes
        let leftHole = NSRect(x: filmRect.minX + size * 0.02, y: y, width: holeWidth, height: holeHeight)
        NSBezierPath(roundedRect: leftHole, xRadius: size * 0.01, yRadius: size * 0.01).fill()
        // Right holes
        let rightHole = NSRect(x: filmRect.maxX - size * 0.06, y: y, width: holeWidth, height: holeHeight)
        NSBezierPath(roundedRect: rightHole, xRadius: size * 0.01, yRadius: size * 0.01).fill()
    }

    // Sound wave icon (right side)
    NSColor.white.setStroke()
    let waveX = size * 0.68
    let waveY = size * 0.5
    let lineWidth = size * 0.035

    for i in 0..<3 {
        let amplitude = size * (0.08 + CGFloat(i) * 0.06)
        let wavePath = NSBezierPath()
        wavePath.lineWidth = lineWidth
        wavePath.lineCapStyle = .round

        let xOffset = CGFloat(i) * size * 0.08
        wavePath.move(to: NSPoint(x: waveX + xOffset, y: waveY - amplitude))
        wavePath.line(to: NSPoint(x: waveX + xOffset, y: waveY + amplitude))
        wavePath.stroke()
    }

    // Arrow (swap indicator)
    let arrowPath = NSBezierPath()
    arrowPath.lineWidth = size * 0.04
    arrowPath.lineCapStyle = .round
    arrowPath.lineJoinStyle = .round

    NSColor.white.setStroke()

    // Arrow body
    let arrowStartX = size * 0.55
    let arrowEndX = size * 0.62
    let arrowY = size * 0.5

    arrowPath.move(to: NSPoint(x: arrowStartX, y: arrowY))
    arrowPath.line(to: NSPoint(x: arrowEndX, y: arrowY))

    // Arrow head
    let arrowHeadSize = size * 0.05
    arrowPath.move(to: NSPoint(x: arrowEndX - arrowHeadSize, y: arrowY + arrowHeadSize))
    arrowPath.line(to: NSPoint(x: arrowEndX, y: arrowY))
    arrowPath.line(to: NSPoint(x: arrowEndX - arrowHeadSize, y: arrowY - arrowHeadSize))

    arrowPath.stroke()

    image.unlockFocus()

    return image
}

func saveIcon(image: NSImage, to url: URL, pixelSize: Int) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        print("Failed to create bitmap for \(url.lastPathComponent)")
        return
    }

    // Create a new bitmap with the exact pixel size
    guard let resizedBitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("Failed to create resized bitmap")
        return
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resizedBitmap)
    NSGraphicsContext.current?.imageInterpolation = .high

    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = resizedBitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data for \(url.lastPathComponent)")
        return
    }

    do {
        try pngData.write(to: url)
        print("Created: \(url.lastPathComponent)")
    } catch {
        print("Failed to write \(url.lastPathComponent): \(error)")
    }
}

// Main
let scriptPath = URL(fileURLWithPath: CommandLine.arguments[0])
let projectRoot = scriptPath.deletingLastPathComponent().deletingLastPathComponent()
let iconsetPath = projectRoot.appendingPathComponent("MP4SoundReplacer/Resources/AppIcon.iconset")

// Create iconset directory
let fileManager = FileManager.default
try? fileManager.removeItem(at: iconsetPath)
try! fileManager.createDirectory(at: iconsetPath, withIntermediateDirectories: true)

print("Generating app icon...")

// Generate master image at 1024x1024
let masterImage = drawIcon(size: 1024)

// Generate all sizes
for iconSize in iconSizes {
    let pixelSize = iconSize.size * iconSize.scale
    let filename = "icon_\(iconSize.suffix).png"
    let filePath = iconsetPath.appendingPathComponent(filename)
    saveIcon(image: masterImage, to: filePath, pixelSize: pixelSize)
}

print("\nConverting to icns...")

// Convert iconset to icns
let icnsPath = projectRoot.appendingPathComponent("MP4SoundReplacer/Resources/AppIcon.icns")

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", icnsPath.path, iconsetPath.path]

try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Successfully created: AppIcon.icns")
    // Clean up iconset
    try? fileManager.removeItem(at: iconsetPath)
} else {
    print("Failed to create icns file")
}

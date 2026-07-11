#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-app-icon.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("failed to create icon canvas\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()

let tileRect = NSRect(x: 64, y: 64, width: 896, height: 896)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 190, yRadius: 190)
NSColor(srgbRed: 49 / 255, green: 130 / 255, blue: 246 / 255, alpha: 1).setFill()
tile.fill()

let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 430, weight: .bold)
    .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MacCleaner"),
   let configured = symbol.withSymbolConfiguration(symbolConfiguration) {
    configured.draw(
        in: NSRect(x: 256, y: 256, width: 512, height: 512),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL, options: .atomic)

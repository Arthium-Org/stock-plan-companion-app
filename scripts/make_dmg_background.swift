#!/usr/bin/env swift

import Cocoa

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: make_dmg_background.swift <output.png>\n".data(using: .utf8)!)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let width: CGFloat = 600
let height: CGFloat = 500

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

let gradient = NSGradient(starting: NSColor(white: 0.98, alpha: 1.0),
                          ending: NSColor(white: 0.90, alpha: 1.0))!
gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

func drawCentered(_ s: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (s as NSString).size(withAttributes: attrs)
    (s as NSString).draw(at: NSPoint(x: (width - size.width) / 2, y: y), withAttributes: attrs)
}

let titleColor = NSColor(white: 0.20, alpha: 1.0)
let bodyColor  = NSColor(white: 0.35, alpha: 1.0)
let accentColor = NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1.0)

drawCentered("Install Stock Plan Manager",
             y: 455, font: NSFont.systemFont(ofSize: 20, weight: .semibold), color: titleColor)
drawCentered("1.  Drag StockPlanCompanion into the Applications folder",
             y: 410, font: NSFont.systemFont(ofSize: 13, weight: .medium), color: bodyColor)

accentColor.setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
let startX: CGFloat = 230, endX: CGFloat = 370, arrowY: CGFloat = 330
arrow.move(to: NSPoint(x: startX, y: arrowY))
arrow.line(to: NSPoint(x: endX, y: arrowY))
arrow.move(to: NSPoint(x: endX, y: arrowY))
arrow.line(to: NSPoint(x: endX - 18, y: arrowY + 12))
arrow.move(to: NSPoint(x: endX, y: arrowY))
arrow.line(to: NSPoint(x: endX - 18, y: arrowY - 12))
arrow.stroke()

drawCentered("2.  Open Applications and double-click StockPlanCompanion",
             y: 200, font: NSFont.systemFont(ofSize: 13, weight: .medium), color: bodyColor)
drawCentered("3.  If macOS blocks it:  System Settings → Privacy & Security → Open Anyway",
             y: 170, font: NSFont.systemFont(ofSize: 12, weight: .regular), color: bodyColor)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote: \(outputPath)")

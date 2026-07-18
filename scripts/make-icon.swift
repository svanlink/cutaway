#!/usr/bin/env swift
// Renders the Cutaway app icon (Liquid Glass style) at 1024pt with CoreGraphics.
// Usage: swift make-icon.swift <output.png>

import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

// --- macOS icon grid: content squircle is 824pt centered in 1024 canvas ---
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)
let corner: CGFloat = rect.width * 0.225   // Apple squircle approximation
let squircle = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

// Drop shadow behind the tile
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 44, color: color(0, 0, 0, 0.45))
ctx.addPath(squircle)
ctx.setFillColor(color(16, 16, 19))
ctx.fillPath()
ctx.restoreGState()

// --- Dark glass background gradient ---
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let bg = CGGradient(colorsSpace: nil, colors: [
    color(38, 38, 44), color(16, 16, 19), color(8, 8, 10),
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: size/2, y: size - inset), end: CGPoint(x: size/2, y: inset), options: [])

// Subtle radial warm glow behind the ring (light reflecting inside glass)
let warm = CGGradient(colorsSpace: nil, colors: [
    color(255, 107, 26, 0.16), color(255, 107, 26, 0.0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(warm, startCenter: CGPoint(x: size/2, y: size/2), startRadius: 0,
                       endCenter: CGPoint(x: size/2, y: size/2), endRadius: rect.width * 0.55, options: [])

// --- The ring (58% arc, round caps — the app's hero motif) ---
let center = CGPoint(x: size/2, y: size/2)
let radius: CGFloat = rect.width * 0.30
let lineWidth: CGFloat = rect.width * 0.085

// track
ctx.setStrokeColor(color(255, 255, 255, 0.10))
ctx.setLineWidth(lineWidth)
ctx.setLineCap(.round)
ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
ctx.strokePath()

// orange arc with glow: start at 12 o'clock, sweep 58% clockwise
let startAngle: CGFloat = .pi / 2
let sweep: CGFloat = 2 * .pi * 0.58
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: color(255, 107, 26, 0.75))
ctx.setStrokeColor(color(255, 107, 26))
ctx.setLineWidth(lineWidth)
ctx.setLineCap(.round)
ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle - sweep, clockwise: true)
ctx.strokePath()
ctx.restoreGState()

// brighter core pass on the arc (glassy depth)
ctx.setStrokeColor(color(255, 138, 61, 0.9))
ctx.setLineWidth(lineWidth * 0.45)
ctx.setLineCap(.round)
ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle - sweep, clockwise: true)
ctx.strokePath()

// --- Glass sheen: soft diagonal highlight across the top ---
ctx.saveGState()
let sheenPath = CGMutablePath()
sheenPath.move(to: CGPoint(x: inset, y: size - inset))
sheenPath.addLine(to: CGPoint(x: size - inset, y: size - inset))
sheenPath.addLine(to: CGPoint(x: size - inset, y: size * 0.66))
sheenPath.addCurve(to: CGPoint(x: inset, y: size * 0.56),
                   control1: CGPoint(x: size * 0.7, y: size * 0.56),
                   control2: CGPoint(x: size * 0.36, y: size * 0.62))
sheenPath.closeSubpath()
ctx.addPath(sheenPath)
ctx.clip()
let sheen = CGGradient(colorsSpace: nil, colors: [
    color(255, 255, 255, 0.09), color(255, 255, 255, 0.0),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: size/2, y: size - inset), end: CGPoint(x: size/2, y: size * 0.52), options: [])
ctx.restoreGState()

// --- Inner rim light (top edge catches light; bottom edge subtle) ---
ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerWidth: corner - 3, cornerHeight: corner - 3, transform: nil))
ctx.setStrokeColor(color(255, 255, 255, 0.10))
ctx.setLineWidth(6)
ctx.strokePath()

ctx.restoreGState()

// --- Write PNG ---
let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

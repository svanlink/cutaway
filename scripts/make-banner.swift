#!/usr/bin/env swift
// Renders the repo hero banner: dark, ring mark, wordmark, tagline.
import AppKit
import CoreGraphics

let W: CGFloat = 1600, H: CGFloat = 420
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "banner.png"
let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}
// bg
let bg = CGGradient(colorsSpace: nil, colors: [c(24, 24, 28), c(10, 10, 12)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: W/2, y: H), end: CGPoint(x: W/2, y: 0), options: [])
// warm glow left
let warm = CGGradient(colorsSpace: nil, colors: [c(255, 107, 26, 0.14), c(255, 107, 26, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(warm, startCenter: CGPoint(x: 330, y: H/2), startRadius: 0,
                       endCenter: CGPoint(x: 330, y: H/2), endRadius: 380, options: [])
// ring mark
let center = CGPoint(x: 330, y: H/2), radius: CGFloat = 110, lw: CGFloat = 30
ctx.setStrokeColor(c(255, 255, 255, 0.09)); ctx.setLineWidth(lw); ctx.setLineCap(.round)
ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false); ctx.strokePath()
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 46, color: c(255, 107, 26, 0.7))
ctx.setStrokeColor(c(255, 107, 26)); ctx.setLineWidth(lw); ctx.setLineCap(.round)
ctx.addArc(center: center, radius: radius, startAngle: .pi/2, endAngle: .pi/2 - 2 * .pi * 0.58, clockwise: true)
ctx.strokePath(); ctx.restoreGState()
ctx.setStrokeColor(c(255, 138, 61, 0.9)); ctx.setLineWidth(lw * 0.42); ctx.setLineCap(.round)
ctx.addArc(center: center, radius: radius, startAngle: .pi/2, endAngle: .pi/2 - 2 * .pi * 0.58, clockwise: true)
ctx.strokePath()
// text
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let title = NSAttributedString(string: "Cutaway", attributes: [
    .font: NSFont.systemFont(ofSize: 118, weight: .bold),
    .foregroundColor: NSColor(srgbRed: 245/255, green: 245/255, blue: 247/255, alpha: 1),
    .kern: -1.5,
])
title.draw(at: NSPoint(x: 560, y: H/2 - 30))
let tag = NSAttributedString(string: "Automatic time tracking for DaVinci Resolve editors.", attributes: [
    .font: NSFont.systemFont(ofSize: 34, weight: .medium),
    .foregroundColor: NSColor(srgbRed: 245/255, green: 245/255, blue: 247/255, alpha: 0.55),
])
tag.draw(at: NSPoint(x: 564, y: H/2 - 88))
NSGraphicsContext.restoreGraphicsState()
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

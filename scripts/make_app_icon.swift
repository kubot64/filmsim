// Draws the app icon: a 3:2 frame whose inside turns from gray (the RAW) into color
// (the developed look), with the yellow accent the camera screen uses.
// Run: swift scripts/make_app_icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
// The design is laid out on a 120-unit grid; the system applies the rounded mask.
let unit = CGFloat(size) / 120

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Flip to a top-left origin so the numbers match the SVG the design was drawn in.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: unit, y: -unit)

ctx.setFillColor(color(0x0b0b0b))
ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 120))

// Frame.
ctx.setStrokeColor(color(0xffffff))
ctx.setLineWidth(2.5)
ctx.addPath(CGPath(roundedRect: CGRect(x: 21, y: 39, width: 78, height: 52),
                   cornerWidth: 3, cornerHeight: 3, transform: nil))
ctx.strokePath()

// Gray side (RAW).
ctx.setFillColor(color(0x6b6b68))
ctx.fill(CGRect(x: 25, y: 43, width: 70, height: 44))

// Colored side, split from the gray on a diagonal.
ctx.saveGState()
ctx.move(to: CGPoint(x: 60, y: 43))
ctx.addLine(to: CGPoint(x: 95, y: 43))
ctx.addLine(to: CGPoint(x: 95, y: 87))
ctx.addLine(to: CGPoint(x: 45, y: 87))
ctx.closePath()
ctx.clip()
let gradient = CGGradient(colorsSpace: space, colors: [color(0xe9b36a), color(0xc9624a)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 43), end: CGPoint(x: 0, y: 87), options: [])
ctx.restoreGState()

// Accent dot.
ctx.setFillColor(color(0xf5c518))
ctx.fillEllipse(in: CGRect(x: 94 - 3.5, y: 30 - 3.5, width: 7, height: 7))

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }

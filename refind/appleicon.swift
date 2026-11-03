// Renders the Apple logo (U+F8FF in the system font) in gray on a transparent square PNG.
//   appleicon <size> <out.png>
// Uses the glyph's outline (CTFontCreatePathForGlyph) so it can be centered exactly.
import AppKit
let size = CGFloat(Int(CommandLine.arguments[1])!), outPath = CommandLine.arguments[2]
let font = CTFontCreateUIFontForLanguage(.system, 100, nil)!
var ch: UniChar = 0xF8FF, glyph: CGGlyph = 0
guard CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1), let path = CTFontCreatePathForGlyph(font, glyph, nil) else { fatalError("no Apple glyph") }
let box = path.boundingBoxOfPath
let k = size * 0.75 / max(box.width, box.height)          // logo spans 75% of the canvas
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: size / 2, y: size / 2)
ctx.scaleBy(x: k, y: k)
ctx.translateBy(x: -box.midX, y: -box.midY)
ctx.addPath(path)
ctx.setFillColor(CGColor(red: 0xB2 / 255.0, green: 0xB2 / 255.0, blue: 0xB2 / 255.0, alpha: 1))
ctx.fillPath()
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("glyph box \(box) scale \(k) -> \(outPath)")

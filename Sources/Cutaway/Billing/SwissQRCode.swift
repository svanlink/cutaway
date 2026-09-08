import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

/// The QR code itself: CoreImage generates it, and the Swiss cross goes on
/// top. No dependency — the system has both halves.
enum SwissQRCode {

    /// The scheme fixes error correction at M and the finished size at
    /// 46 × 46 mm, with a 7 × 7 mm cross centred on it.
    static let sideMM: CGFloat = 46
    static let crossMM: CGFloat = 7

    /// Points per module, given the generator's output width.
    ///
    /// CoreImage bakes a one-module quiet zone into its output, so an
    /// N-module image carries N-2 modules of actual code. Scaling all N into
    /// 46 mm printed the CODE at about 44.3 mm — 3.6% undersized, and §6.4
    /// is not a recommendation: "The measurements of the Swiss QR Code for
    /// printing must always be 46 x 46 mm (without surrounding quiet space)
    /// regardless of the Swiss QR Code version." The quiet zone is the
    /// layout's job — the 5 mm unprinted border around the code — not
    /// something to fold into the 46 mm.
    static func modulePoints(extentWidth: CGFloat, sidePoints: CGFloat) -> CGFloat {
        let codeModules = max(extentWidth - 2, 1)
        return sidePoints / codeModules
    }

    static func image(payload: String, sidePoints: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        // M — required by the specification, not a quality preference.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let modules = readModules(output) else { return nil }

        let step = modulePoints(extentWidth: CGFloat(modules.side), sidePoints: sidePoints)
        let side = NSSize(width: sidePoints, height: sidePoints)
        let result = NSImage(size: side)
        result.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: side).fill()
        NSColor.black.setFill()
        // Drawn as rectangles, not as a scaled bitmap. §6.4 asks for a vector
        // graphic, and blowing a 55 px bitmap up 2.4x with nearest-neighbour
        // is a plausible cause of the validator's "@qrversion could not be
        // determined" rejection, which its FAQ attributes to image size and
        // resolution. One rect per dark module resamples nothing.
        //
        // The one-module quiet zone is dropped, so index 1 lands at 0 and the
        // 46 mm box holds exactly the code.
        for row in 1..<(modules.side - 1) {
            for column in 1..<(modules.side - 1) where modules.isDark(column, row) {
                // CoreImage's origin is bottom-left, and so is this context.
                NSRect(x: CGFloat(column - 1) * step,
                       y: CGFloat(modules.side - 1 - row - 1) * step,
                       width: step, height: step).fill()
            }
        }
        drawSwissCross(in: NSRect(origin: .zero, size: side))
        result.unlockFocus()
        return result
    }

    /// The generator's output as a module grid, read once.
    struct Modules {
        let side: Int
        private let dark: [Bool]
        init(side: Int, dark: [Bool]) { self.side = side; self.dark = dark }
        func isDark(_ x: Int, _ y: Int) -> Bool { dark[y * side + x] }
    }

    static func readModules(_ output: CIImage) -> Modules? {
        let side = Int(output.extent.width.rounded())
        guard side > 2,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let bitmap = CGContext(data: &pixels, width: side, height: side,
                                     bitsPerComponent: 8, bytesPerRow: side * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        bitmap.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var dark = [Bool](repeating: false, count: side * side)
        for index in 0..<(side * side) { dark[index] = pixels[index * 4] < 128 }
        return Modules(side: side, dark: dark)
    }

    /// A black square with a white cross, centred, 7/46 of the code's side.
    private static func drawSwissCross(in rect: NSRect) {
        let crossSide = rect.width * crossMM / sideMM
        let box = NSRect(x: rect.midX - crossSide / 2, y: rect.midY - crossSide / 2,
                         width: crossSide, height: crossSide)
        NSColor.white.setFill()
        box.insetBy(dx: -crossSide * 0.06, dy: -crossSide * 0.06).fill()
        NSColor.black.setFill()
        box.fill()

        // The arms: 3/5 long, 1/5 thick, which is the proportion on the flag.
        NSColor.white.setFill()
        let thickness = crossSide * 0.2
        let length = crossSide * 0.6
        NSRect(x: box.midX - thickness / 2, y: box.midY - length / 2,
               width: thickness, height: length).fill()
        NSRect(x: box.midX - length / 2, y: box.midY - thickness / 2,
               width: length, height: thickness).fill()
    }
}

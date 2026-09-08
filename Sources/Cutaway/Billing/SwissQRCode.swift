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

    static func image(payload: String, sidePoints: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        // M — required by the specification, not a quality preference.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scale = sidePoints / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        let side = NSSize(width: sidePoints, height: sidePoints)
        let result = NSImage(size: side)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: cgImage, size: side).draw(in: NSRect(origin: .zero, size: side))
        drawSwissCross(in: NSRect(origin: .zero, size: side))
        result.unlockFocus()
        return result
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

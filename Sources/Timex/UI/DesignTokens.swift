import SwiftUI

/// 1:1 mirror of the Figma "02 Foundations" variables and the HTML :root
/// tokens. Change values HERE only — never inline in views.
enum DT {
    // surfaces
    static let window = Color(red: windowRGB.r, green: windowRGB.g, blue: windowRGB.b)
    static let card = Color(red: cardRGB.r, green: cardRGB.g, blue: cardRGB.b)
    static let card2 = Color(red: 28/255, green: 28/255, blue: 32/255)
    static let popover = Color(red: 32/255, green: 32/255, blue: 36/255)
    static let strokeSubtle = Color.white.opacity(0.07)
    static let strokeWindow = Color.white.opacity(0.09)

    // text — raw components exposed so ContrastTests can verify WCAG AA
    // (4.5:1) mathematically against the surface tokens.
    static let baseTextRGB = (r: 245.0 / 255, g: 245.0 / 255, b: 247.0 / 255)
    static let cardRGB = (r: 23.0 / 255, g: 23.0 / 255, b: 26.0 / 255)
    static let windowRGB = (r: 13.0 / 255, g: 13.0 / 255, b: 15.0 / 255)
    static let text2Alpha = 0.62
    static let text3Alpha = 0.55
    static let text = Color(red: baseTextRGB.r, green: baseTextRGB.g, blue: baseTextRGB.b)
    static let text2 = Color(red: baseTextRGB.r, green: baseTextRGB.g, blue: baseTextRGB.b).opacity(text2Alpha)
    static let text3 = Color(red: baseTextRGB.r, green: baseTextRGB.g, blue: baseTextRGB.b).opacity(text3Alpha)

    // accent + states
    static let orange = Color(red: 1, green: 107/255, blue: 26/255)
    static let orangeSoft = Color(red: 1, green: 107/255, blue: 26/255).opacity(0.14)
    static let onOrange = Color(red: 20/255, green: 10/255, blue: 4/255)
    static let green = Color(red: 52/255, green: 199/255, blue: 89/255)
    static let amber = Color(red: 254/255, green: 188/255, blue: 46/255)
    static let red = Color(red: 1, green: 69/255, blue: 58/255)
    static let ringTrack = Color.white.opacity(0.07)
    static let ringPaused = Color.white.opacity(0.22)

    // spacing (4pt grid)
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12
    static let s4: CGFloat = 16, s5: CGFloat = 24, s6: CGFloat = 32
    /// Documented exception to the 4pt grid: horizontal inset for list rows
    /// and cards (14pt reads tighter than 16 against the 480pt canvas —
    /// audit #3 ruling).
    static let rowInset: CGFloat = 14

    // radius
    static let rSm: CGFloat = 6, rMd: CGFloat = 8, rLg: CGFloat = 12

    // type
    static let hero = Font.system(size: 48, weight: .thin)
    static let heroSec = Font.system(size: 25, weight: .light)
    static let money = Font.system(size: 17, weight: .semibold)
    static let statValue = Font.system(size: 16, weight: .semibold)
    static let title = Font.system(size: 16, weight: .bold)
    static let body = Font.system(size: 13, weight: .medium)
    static let bodyBold = Font.system(size: 13, weight: .bold)
    static let small = Font.system(size: 12, weight: .medium)
    static let smallSemibold = Font.system(size: 12, weight: .semibold)
    static let caption = Font.system(size: 11, weight: .semibold)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let tag = Font.system(size: 10.5, weight: .semibold)

    // canvas
    static let windowSize = CGSize(width: 480, height: 660)
}

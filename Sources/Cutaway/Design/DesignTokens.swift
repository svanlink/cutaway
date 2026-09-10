import SwiftUI
import AppKit

/// 1:1 mirror of the Figma "02 Foundations" variables and the HTML :root
/// tokens. Change values HERE only — never inline in views.
enum DT {
    // ── Surfaces ──────────────────────────────────────────────────────
    // A five-step ramp ~5 L* apart, lifted off pure black. The old system
    // fit window/card/card2/popover inside L* 3.7–12.4 — card against window
    // was 1.085:1, so on a second display beside a grading suite the app was
    // a black rectangle with hairlines drawn on it. Resolve's own panels sit
    // at L* 17–20; these now share that register without matching its hue.
    static let sunken: Color = hex(0x0E0F11)    // L*  4.3 — wells, insets
    static let base: Color = hex(0x18191C)      // L*  8.8 — window ground
    static let raised: Color = hex(0x232428)    // L* 14.2 — cards, rows
    static let overlay: Color = hex(0x2D2F33)   // L* 19.4 — popovers, sheets
    static let float: Color = hex(0x383A3F)     // L* 24.4 — menus, tooltips

    // ── Text ──────────────────────────────────────────────────────────
    // Solid, not alpha over a surface. The old ladder was alpha-composited,
    // which is how text2 and text3 drifted to 6 L* apart — one colour
    // wearing two names, and why Stats had no reading order.
    static let textPrimary: Color = hex(0xF2F3F5)     // L* 95.8
    static let textSecondary: Color = hex(0xAAAEB6)   // L* 71.0  (gap 24.8)
    static let textTertiary: Color = hex(0x8A8F98)    // L* 59.3  (gap 11.7)

    // ── Money ─────────────────────────────────────────────────────────
    // Currency is ALWAYS this and never an accent. Warm off-white: reads as
    // ledger paper, and stops the app implying a judgement about a figure by
    // colouring it.
    static let money: Color = hex(0xF4F1EA)

    // ── Signal ────────────────────────────────────────────────────────
    // Instrument cyan, deliberately not orange. #FF6B1A sits inside
    // Resolve's own warm accent family (its "effect enabled" red-orange is
    // #D54451), so an orange Cutaway read as a worse Resolve panel. Cyan
    // reads as scope and graticule, and leaves the whole warm half of the
    // wheel to mean money and warning exclusively.
    static let signal: Color = hex(0x3FD0E0)
    static let signalSoft: Color = hex(0x3FD0E0).opacity(0.14)
    static let onSignal: Color = hex(0x081417)

    // ── State ─────────────────────────────────────────────────────────
    // Hue is the SECOND encoding everywhere; shape carries it first.
    static let recording: Color = hex(0x5AD18C)
    static let held: Color = hex(0xE8B14C)
    static let alarm: Color = hex(0xF06A5E)
    static let idle: Color = hex(0x6E747E)

    // ── Menu bar ──────────────────────────────────────────────────────
    // The one surface NOT inside a window forced to dark: the status bar
    // follows the SYSTEM appearance. Apple's own systemGreen/Orange/Red are
    // tuned as fills and measure 1.8–2.9:1 as a 1pt border on a light bar,
    // so these carry the dark hues and drop to deeper variants in light.
    static let barText: Color = .primary
    static let barText2: Color = .secondary
    static let barGreen: Color = barAdaptive(dark: (90, 209, 140), light: (30, 110, 50))
    static let barAmber: Color = barAdaptive(dark: (232, 177, 76), light: (150, 86, 0))
    static let barRed: Color = barAdaptive(dark: (240, 106, 94), light: (190, 30, 25))

    static func barAdaptive(dark: (Int, Int, Int), light: (Int, Int, Int)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                           blue: CGFloat(b) / 255, alpha: 1)
        })
    }

    // ── System accessibility settings ─────────────────────────────────
    // The app read none of these. Increase Contrast strengthens borders and
    // reduces transparency system-wide; every control here is
    // .buttonStyle(.plain) with hand-drawn chrome, so the app opted out of
    // all of it — a hairline at 1.2:1 stayed a hairline at 1.2:1 no matter
    // what the user asked the OS for.
    //
    // High contrast is a real NSAppearance, so a dynamic colour can answer it
    // the same way it answers light-vs-dark.
    static func contrastAware(normal: Double, increased: Double) -> Color {
        Color(nsColor: contrastAwareNS(normal: normal, increased: increased))
    }

    /// The dynamic colour itself. Exposed because converting a SwiftUI `Color`
    /// back to `NSColor` resolves it against whatever appearance is current at
    /// that moment — the dynamism is lost in the round trip, so a test that
    /// goes through `Color` cannot see it. SwiftUI renders the NSColor, so
    /// this is the thing worth asserting on.
    static func contrastAwareNS(normal: Double, increased: Double) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(white: 1, alpha: CGFloat(contrastAlpha(normal: normal,
                                                           increased: increased,
                                                           highContrast: isHighContrast(appearance))))
        }
    }

    /// The decision itself, as a pure function.
    ///
    /// Which alpha to use is testable; whether AppKit hands the provider a
    /// high-contrast appearance is not — `NSAppearance(named:)` will not
    /// report a high-contrast name back unless the system setting is actually
    /// on, so a unit test cannot construct the case. That binding is verified
    /// by hand; see docs/ACCESSIBILITY-MANUAL.md.
    static func contrastAlpha(normal: Double, increased: Double, highContrast: Bool) -> Double {
        highContrast ? increased : normal
    }

    // The alphas the tokens are built from, so a test can name what it checks.
    static let strokeSubtleAlphas = (normal: 0.08, increased: 0.30)
    static let strokeWindowAlphas = (normal: 0.12, increased: 0.38)
    static let ringTrackAlphas = (normal: 0.10, increased: 0.26)
    static let ringPausedAlphas = (normal: 0.30, increased: 0.55)

    /// Increase Contrast is NOT an NSAppearance on macOS.
    ///
    /// This was implemented twice before it worked. `bestMatch(from:)`
    /// normalises a high-contrast appearance back to plain aqua, so the first
    /// version reported false for the very appearance it was handed. Matching
    /// `appearance.name` directly failed too — and the reason is the point:
    ///
    ///     NSAppearance(named: .accessibilityHighContrastDarkAqua)?.name
    ///       -> NSAppearanceNameDarkAqua
    ///
    /// The system collapses those names. Apps are told about this setting
    /// through NSWorkspace, not through their appearance, so that is what the
    /// tokens ask. The appearance check stays as a second source in case a
    /// future macOS does propagate it, but the workspace flag is the one that
    /// answers today.
    static var systemPrefersIncreasedContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    static func isHighContrast(_ appearance: NSAppearance) -> Bool {
        if systemPrefersIncreasedContrast { return true }
        switch appearance.name {
        case .accessibilityHighContrastAqua,
             .accessibilityHighContrastDarkAqua,
             .accessibilityHighContrastVibrantLight,
             .accessibilityHighContrastVibrantDark:
            return true
        default:
            return false
        }
    }

    static func hex(_ value: Int) -> Color {
        let r: Double = Double((value >> 16) & 0xFF)
        let g: Double = Double((value >> 8) & 0xFF)
        let b: Double = Double(value & 0xFF)
        return Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
    }

    // ── Compatibility ─────────────────────────────────────────────────
    // The old names, re-pointed. Kept so the repaint lands everywhere at
    // once rather than through a hundred hand-edits; the orange sites are
    // split explicitly at their call sites, because orange was doing six
    // unrelated jobs and only one of them is the accent.
    static let window: Color = base
    static let card: Color = raised
    static let card2: Color = raised
    static let popover: Color = overlay
    static let text: Color = textPrimary
    static let text2: Color = textSecondary
    static let text3: Color = textTertiary
    static let green: Color = recording
    static let amber: Color = held
    static let red: Color = alarm
    static let strokeSubtle: Color = contrastAware(normal: strokeSubtleAlphas.normal,
                                                   increased: strokeSubtleAlphas.increased)
    static let strokeWindow: Color = contrastAware(normal: strokeWindowAlphas.normal,
                                                   increased: strokeWindowAlphas.increased)
    static let ringTrack: Color = contrastAware(normal: ringTrackAlphas.normal,
                                                increased: ringTrackAlphas.increased)
    /// The paused ring is a status indicator, so it wants 3:1 even normally —
    /// 0.30 gets it there, and Increase Contrast takes it further.
    static let ringPaused: Color = contrastAware(normal: ringPausedAlphas.normal,
                                                 increased: ringPausedAlphas.increased)

    // ── Space ─────────────────────────────────────────────────────────
    //
    // Apple's HIG, macOS layout: 20pt window margins, 8pt between related
    // controls, 20pt between groups. The ratio is the point — a group reads
    // as a group because the gap around it is two and a half times the gap
    // inside it.
    //
    // The views used thirteen different values: 1, 2, 3, 4, 5, 6, 7, 8, 9,
    // 10, 12, 14, 20. With 2 inside a group and 3 around it, nothing was
    // grouped, and "too many elements stacked into very little space" is
    // exactly what that looks like. These six are the whole vocabulary.
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12
    static let s4: CGFloat = 16, s5: CGFloat = 24, s6: CGFloat = 32

    /// Inside a group: a label and the value it belongs to, a row and the
    /// row under it. HIG's "between related controls".
    static let within: CGFloat = s2
    /// Between groups: one card and the next, the header and the content.
    /// HIG's "between groups" — 2.5x `within`, which is what makes the
    /// grouping legible without a single line or box being drawn.
    static let between: CGFloat = 20
    /// The window's own margin. HIG: 20pt.
    static let margin: CGFloat = 20
    /// Horizontal inset for list rows and cards. On the grid now: 14 was a
    /// documented exception, and an exception that appears seven times is
    /// not an exception, it is a second scale.
    static let rowInset: CGFloat = s4

    // radius
    static let rSm: CGFloat = 6, rMd: CGFloat = 8, rLg: CGFloat = 12

    // type
    // Apple's HIG, Typography → Ensuring legibility: "avoid Ultralight, Thin
    // and Light font weights". The hero readout — the number the whole app
    // exists to show — was 48pt Thin, which renders as hairlines in a dark
    // room and is the standard tell of a design that reached for elegant.
    // ── Type ──────────────────────────────────────────────────────────
    //
    // ONE ladder, eight steps, no fractions. There were sixteen distinct
    // sizes here — 8, 9, 10, 10.5, 11, 11.5, 12, 12.5, 13, 15, 16, 17, 19,
    // 20, 25, 36 — three of them fractional, which is the tell of sizes
    // nudged until something fit rather than chosen.
    //
    // Sixteen sizes is why the app read as busy. Hierarchy is carried by
    // CONSISTENT difference: when 12 and 12.5 both appear, neither says
    // anything, and the eye gives up and reads the whole panel as one mass.
    // Every step below is a size macOS itself uses (HIG Typography, macOS
    // type sizes), so the app sits in the same rhythm as the menus around it.
    enum Step {
        /// Asked, not assumed. These were hand-typed numbers that happened to
        /// match; reading them from the system means the app moves when macOS
        /// moves, and it is honest about where they came from.
        private static func system(_ style: NSFont.TextStyle) -> CGFloat {
            NSFont.preferredFont(forTextStyle: style).pointSize
        }

        /// The hero clock — the one number the app exists to show, and the
        /// only step deliberately above the system's largest text style.
        static let display: CGFloat = 36
        /// The lead figure on a card. macOS Large Title (26).
        static let xl = system(.largeTitle)
        /// Section titles, money, the seconds beside the hero. Title 2 (17).
        static let l = system(.title2)
        /// A project name — a proper noun, a step above running text.
        /// Title 3 (15).
        static let m = system(.title3)
        /// Body and Headline share this size on macOS; weight separates
        /// them, which is the platform's own answer to emphasis (13).
        static let base = system(.body)
        /// Dense rows and secondary controls. Callout (12).
        static let s = system(.callout)
        /// Labels above values, metadata. Subheadline (11).
        static let xs = system(.subheadline)
        /// Glyphs, tags, column headers. Footnote and Caption, which are the
        /// same size on macOS (10).
        static let xxs = system(.footnote)
    }

    /// Currency figures. Monospaced: a money column that shifts as digits
    /// change is the tell of a timer, not a ledger.
    static let moneyFont = Font.system(size: Step.l, weight: .semibold).monospacedDigit()
    /// Supporting figures — one step DOWN from the lead, so size and weight
    /// say the same thing instead of cancelling.
    static let statValue = Font.system(size: Step.m, weight: .medium)
    /// The lead figure in Stats: the money.
    static let statLead = Font.system(size: Step.xl, weight: .semibold)
    static let title = Font.system(size: Step.l, weight: .bold)
    static let body = Font.system(size: Step.base, weight: .medium)
    static let bodyBold = Font.system(size: Step.base, weight: .bold)
    static let small = Font.system(size: Step.s, weight: .medium)
    static let smallSemibold = Font.system(size: Step.s, weight: .semibold)
    static let caption = Font.system(size: Step.xs, weight: .semibold)
    static let captionMedium = Font.system(size: Step.xs, weight: .medium)
    static let tag = Font.system(size: Step.xxs, weight: .semibold)
    /// Inline leading glyph (checkmark, hourglass) — punctuation, not a
    /// second voice.
    static let glyph = Font.system(size: Step.xxs, weight: .bold)
    /// Unweighted glyph — a chevron or a play triangle, where bold would
    /// read as emphasis the mark does not carry.
    static let glyphLight = Font.system(size: Step.xxs)
    static let glyphTiny = Font.system(size: Step.xxs)
    /// Leading icon inside a compact button (Export CSV).
    static let buttonGlyph = Font.system(size: Step.xxs, weight: .bold)
    static let smallBold = Font.system(size: Step.s, weight: .bold)

    // menu-bar pill — read at a glance, at menu-bar scale. 13 is the size
    // the system's own menu bar uses, so the pill sits level with it.
    static let pillTime = Font.system(size: Step.base, weight: .bold)
    /// Banked confirmation and the forgotten-pause hint, which replace the
    /// time readout rather than sitting beside it.
    static let pillMessage = Font.system(size: Step.s, weight: .bold)

    // menu-bar panel — the same ladder, not a private one. It used to run
    // 10.5 / 11.5 / 12.5 / 15 / 19 / 36, a parallel scale that shared no
    // step with the window it opens.
    static let panelHero = Font.system(size: Step.display, weight: .medium)
    static let panelHeroSeconds = Font.system(size: Step.l, weight: .regular)
    static let panelClient = Font.system(size: Step.xs, weight: .bold)
    static let panelProject = Font.system(size: Step.m, weight: .semibold)
    static let panelRowActive = Font.system(size: Step.base, weight: .semibold)
    static let panelTotal = Font.system(size: Step.base, weight: .semibold)
    static let panelTotalActive = Font.system(size: Step.base, weight: .bold)
    static let panelChip = Font.system(size: Step.xs, weight: .bold)

    // canvas
    /// What the window opens at, and the smallest it may become.
    ///
    /// One value did both, which is why the window could not be made smaller
    /// than its opening size — and why it opened a third taller than a
    /// typical week of content, leaving a void inside the day list. Apple's
    /// layout guidance is "extend content to fill the window"; the card does,
    /// so the calibration belongs to the OPENING SIZE, not to the layout.
    ///
    /// 580 fits a week with today's strip open. More days scroll, and the
    /// window is freely resizable — macOS remembers the frame either way.
    static let windowSize = CGSize(width: 480, height: 580)
    /// Small enough to be useful on a laptop beside a full-screen Resolve.
    static let windowMinSize = CGSize(width: 420, height: 380)

    /// The invoice page.
    ///
    /// A separate scale on purpose: this is the one surface that leaves the
    /// Mac, measured in points on A4 and following business-document
    /// conventions rather than the app's dark instrument styling. It lives
    /// here anyway, because "sizes are named for the role they play, in one
    /// place" is the rule — not "the app has exactly one scale".
    enum Page {
        static let title = Font.system(size: 20, weight: .semibold)
        static let number = Font.system(size: 11, weight: .medium)
        static let totalLead = Font.system(size: 11, weight: .semibold)
        static let party = Font.system(size: 10)
        static let row = Font.system(size: 9)
        static let meta = Font.system(size: 9)
        static let columnHeader = Font.system(size: 8, weight: .semibold)
        static let note = Font.system(size: 8)
    }

    /// The QR-bill's type is not a design choice — it is specified.
    ///
    /// IG v2.3 §3.4: "Only the sans-serif fonts Arial, Frutiger, Helvetica
    /// and Liberation Sans are permitted in black." SF Pro, which
    /// `Font.system` resolves to, is not on that list. §3.5.1 and §3.6.1 fix
    /// the title at 11 pt bold; the payment part's headings are 8 pt bold
    /// with 10 pt values, and the receipt's are 6 pt bold with 8 pt values.
    enum QRBill {
        private static let face = "Helvetica"
        private static let bold = "Helvetica-Bold"

        static let title = Font.custom(bold, fixedSize: 11)
        static let paymentHeading = Font.custom(bold, fixedSize: 8)
        static let paymentValue = Font.custom(face, fixedSize: 10)
        static let receiptHeading = Font.custom(bold, fixedSize: 6)
        static let receiptValue = Font.custom(face, fixedSize: 8)
        /// The instruction above the separation line, outside the bill.
        static let separationNote = Font.custom(face, fixedSize: 7)
    }
}

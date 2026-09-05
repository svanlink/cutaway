# macOS design language for a premium menu-bar app

*Generated 2026-09-05 | Sources: 45 | Confidence: High on Apple guidance and APIs (primary docs, WWDC25); Medium on "premium app" patterns (reverse-engineered from write-ups, not vendor design docs); Medium-Low on Tahoe menu-bar edge cases (single-source developer reports).*

## Executive summary

- **Liquid Glass changes the chrome, not the content.** Apple wants glass only on the floating navigation layer (toolbars, sidebars, popover shells, menus), never in content, and never glass-on-glass [[HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)] [[Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)]. A menu-bar panel gets the new popover/menu shell for free when built against the 26 SDK; the custom "instrument" content inside is fine and expected.
- **Cutaway's Tahoe risks are structural, not visual:** custom backgrounds over popover shells [[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)], hard-coded control heights (controls got taller) [[WWDC25 310](https://developer.apple.com/videos/play/wwdc2025/310/)], a legacy `.icns` icon ("icon jail") [[Successful Software](https://successfulsoftware.net/2025/09/26/updating-application-icons-for-macos-26-tahoe-and-liquid-glass/)], and the transparent menu bar making non-template status icons unreliable [[Apple Newsroom](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)].
- **Premium Mac utilities share five traits:** one typeface at 2–3 weights, colour reserved for meaning, hairline depth, sub-500 ms motion with sound only at "reward" moments, and AppKit-exact behaviour (no hover highlights, native popovers, ⌘, settings) [[Raycast](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast)] [[Things 3](https://blakecrosley.com/guides/design/things)] [[Coyote Tracks](https://coyotetracks.org/blog/app-feel-on-mac/)].
- **Forced dark is legitimate but must be done at the scene/app level and survive Increase Contrast/Reduce Transparency**; Apple calls it "rare cases" and App Review has rejected inconsistent light modes [[HIG Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)] [[Klarity](https://www.klaritydisk.com/blog/building-liquid-glass-ui-macos)].
- **Keep:** NSStatusItem + NSPopover, template status icon with tally-light colour only for state, native Forms for Settings, the contrast test suite, and the accessibility-setting handling. **Add:** Icon Composer icon, `performAccessibilityAudit` in UI tests, a scene-level appearance decision, and a 26-SDK build audit.

## 1. Liquid Glass and what it means for Cutaway

**What changed (macOS 26).** Toolbars float on glass with automatic grouping; sidebars are floating glass; larger window corner radii; a scroll-edge effect replaces hard dividers; menus adopt glass and lead with SF Symbols; mini/small/medium controls got taller, an extra-large size appeared, and only large controls become capsules [[WWDC25 310](https://developer.apple.com/videos/play/wwdc2025/310/)] [[WWDC25 356](https://developer.apple.com/videos/play/wwdc2025/356/)]. Popovers, sheets and menus adopt the material automatically; Apple tells you to *remove* any visual-effect view behind popover content [[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)]. The menu bar itself is fully transparent by default; users can add a background in Settings [[Apple Newsroom](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)]. 26.1 added a user-facing Clear/Tinted toggle, and 26.3 fixed Reduce Transparency not applying to title bars and toolbars [[theodorehq](https://www.theodorehq.com/solace/blog/posts/macos-tahoe-dark-mode-guide)].

**HIG rules that bind Cutaway.** Glass is for the navigation layer, never content; custom glass sparingly, on the most important functional elements only; *regular* variant except over media [[HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)]. Tint only to convey meaning, never branding [[WWDC25 323](https://developer.apple.com/videos/play/wwdc2025/323/)]. Menu bar guidance is unchanged: prefer a symbol/template image, "Display a menu — not a popover" unless the functionality is too complex for a menu, and never rely on the extra being visible [[HIG The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)].

**APIs.** SwiftUI: `.glassEffect(_:in:)` (`.tint`, `.interactive()`), `GlassEffectContainer` (mandatory for adjacent glass), `.glassEffectID` morphing, `.buttonStyle(.glass/.glassProminent)`, `ToolbarSpacer`, macOS-only `windowResizeAnchor` [[WWDC25 323](https://developer.apple.com/videos/play/wwdc2025/323/)] [[WWDCNotes 256](https://wwdcnotes.com/documentation/wwdc25-256-whats-new-in-swiftui/)]. AppKit: `NSGlassEffectView`/`NSGlassEffectContainerView`, `NSView.LayoutRegion` for corner avoidance, `NSToolbarItem.style`, `NSItemBadge` [[WWDC25 310](https://developer.apple.com/videos/play/wwdc2025/310/)].

**What still applies on 14–15.** Nothing above renders on Sonoma/Sequoia; the same binary keeps the legacy look, gated on the 26 SDK. Layout must tolerate both control metrics; isolate `@available(macOS 26)` in small components [[WWDC25 310](https://developer.apple.com/videos/play/wwdc2025/310/)] [[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)].

**For Cutaway:** the 340 pt panel is content, so the instrument look is compliant *provided* the popover shell is system-drawn with no `NSVisualEffectView` behind it. The footer is the one on-doctrine spot for a `GlassEffectContainer`; a glass hero is not.

## 2. Patterns from premium Mac apps

Study set: ADA 2023–2025 Mac-eligible honourees (Flighty, Universe, Copilot Money, Crouton, Play, iA Writer, Mela) [[ADA 2023](https://developer.apple.com/design/awards/2023/)] [[ADA 2024](https://developer.apple.com/design/awards/2024/)] [[ADA 2025](https://developer.apple.com/design/awards/2025/)], plus Raycast, Things 3, CleanShot X, Klack, Bartender/Ice.

- **Typography.** One family, 2–3 weights. Raycast: Inter 400–600 (never 700), +0.2 px tracking, 12–14 px captions [[shadcn.io/design/raycast](https://www.shadcn.io/design/raycast)]. Apple's macOS floor: 13 pt default, 10 pt minimum, no Ultralight/Thin/Light [[HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)]. SF is the expected UI face; anything else reads "not Mac" [[Coyote Tracks](https://coyotetracks.org/blog/app-feel-on-mac/)].
- **Spacing rhythm.** 4/8-pt base with 8, 12, 16, 24 as the workhorse steps; radii cluster at 6–10 pt for controls and 12–16 pt for panels [[shadcn.io/design/raycast](https://www.shadcn.io/design/raycast)].
- **Colour restraint.** Things 3 is ~95 % neutral; colour is semantic only (yellow=Today, red=Deadline) [[Things 3](https://blakecrosley.com/guides/design/things)]. Raycast's CTA is white; red appears once per surface [[shadcn.io/design/raycast](https://www.shadcn.io/design/raycast)]. Apple: tint only for meaning [[WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/)].
- **Depth.** Hairline 1 px borders at 6–16 % white, a four-step surface ladder, no drop shadows [[shadcn.io/design/raycast](https://www.shadcn.io/design/raycast)].
- **Iconography.** SF Symbols in menus and toolbars, monochrome, one symbol per action group, standard glyphs for standard actions [[WWDC25 356](https://developer.apple.com/videos/play/wwdc2025/356/)].
- **Motion.** Brief, precise, cancellable, avoided on frequent interactions [[HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)]. Things' completion: 200 ms fill → spring(0.3, damping 0.5) check → 150 ms settle, ~500 ms total, reserved for the *reward* moment [[Things 3](https://blakecrosley.com/guides/design/things)].
- **Sound.** Reward or state confirmation only (Things' "plink"); Klack is sound-led but ships per-output routing, independent volume and a mute hotkey [[Things 3](https://blakecrosley.com/guides/design/things)] [[Klack](https://apps.apple.com/us/app/klack/id6446206067?mt=12)].
- **Onboarding/empty states.** Teach by doing, prefer contextual tips (TipKit) to a flow, postpone setup, ship defaults [[HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)]. CleanShot's praised trait: "no setup process" [[TheSweetBits](https://thesweetbits.com/tools/cleanshot-review/)].
- **Settings.** A separate native window on ⌘, — never a tab or panel [[Coyote Tracks](https://coyotetracks.org/blog/app-feel-on-mac/)] [[Raycast](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast)].
- **Behaviour is the premium tell.** Raycast: no hover highlights on most controls, popovers as real windows, zero flicker, Liquid Glass on day one [[Raycast](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast)].
- **App icon.** Layered background + foreground in Icon Composer; system applies specular/refraction; annotate default, dark and mono (clear/tinted derive from mono); max four groups; keep source flat [[HIG App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)] [[WWDC25 361](https://developer.apple.com/videos/play/wwdc2025/361/)]. Xcode derives the 14–15 `.icns` from the same file; a legacy-only icon is shrunk onto a grey squircle on 26 [[Creating your app icon](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)] [[Successful Software](https://successfulsoftware.net/2025/09/26/updating-application-icons-for-macos-26-tahoe-and-liquid-glass/)].

## 3. Menu bar item and panel: the current best practice

**MenuBarExtra vs NSStatusItem + NSPopover.** `MenuBarExtra(.window)` is the right default for simple utilities [[Fazm](https://fazm.ai/blog/swiftui-menu-bar-app-floating-window-best-practices)], but has documented walls: resize timing is not exposed (flicker on collapse) [[Irrlicht #189](https://github.com/ingo-eichhorst/Irrlicht/issues/189)]; it ties icon existence to the scene, so macOS 26's "Allow in Menu Bar" toggle can leave the app unable to launch, whereas `NSStatusItem` just reports `isVisible == false` [[akring](https://blog.akring.com/posts/a-strange-bug-caused-by-swiftui--macos-26/)]; no right-click or dynamic sizing [[techconcepts](https://techconcepts.org/blog/macos-menu-bar-guide)]. NSStatusItem + NSPopover is the mainstream choice for a rich panel; traps: `contentSize` silently clips, environment does not cross `.sheet()` windows, use `.applicationDefined` while a sheet is up [[techconcepts](https://techconcepts.org/blog/macos-menu-bar-guide)].

**Popover vs floating panel.** Popover: anchored, outside-click dismiss, feels attached; NSPanel (`.nonactivatingPanel`, `becomesKeyOnlyIfNeeded`, `.floating`) only when it must persist while the user works elsewhere [[Fazm](https://fazm.ai/blog/swiftui-menu-bar-app-floating-window-best-practices)]. Apple's popover rules: few related tasks, one at a time, nothing over it but an alert, animate size changes [[HIG Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers)].

**Status item width and colour.** Working area 22 pt; ~16 pt glyph matches system weight; template images preferred (AppKit tints for light/dark/selected/inactive); 35 % opacity expresses disabled state [[Bjango](https://bjango.com/articles/designingmenubarextras/)] [[HIG The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)]. On Tahoe's transparent bar, block-drawn images are not tinted reliably and `contentTintColor` disables template tinting; the working pattern is a bitmap-backed template glyph for idle plus pre-coloured non-template copies for states, `labelColor` for text [[NOTCHYLIMIT #14](https://github.com/I-N-SILVA/NOTCHYLIMIT/pull/14)]. Variable-width SwiftUI-sized items work via `NSHostingView` in the status button [[Multi](https://multi.app/blog/pushing-the-limits-nsstatusitem)]. Tahoe hosts third-party items in ControlCenter with a TCC ledger; scratch builds launched by other apps can get your bundle ID blocked [[Superposed](https://superposed.app/blogs/menu-bar-icon-blocked-macos-tahoe)]. Bartender 5 broke outright on Tahoe; Ice needed a beta for icon colours [[TheSweetBits](https://thesweetbits.com/tools/bartender-review/)] [[9to5Mac](https://9to5mac.com/2026/01/27/a-decade-with-bartender-showed-me-how-overdue-this-macos-feature-is/)].

## 4. Appearance: forced dark vs system

Apple: no app-specific appearance setting; "In rare cases, consider using only a dark appearance" (Stocks) [[HIG Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)]. The sanctioned mechanism is `NSApp.appearance = NSAppearance(named: .darkAqua)` (or per-window/popover), for designs where chrome should recede [[AppKit: Choosing a specific appearance](https://developer.apple.com/documentation/appkit/choosing-a-specific-appearance-for-your-macos-app)]. Raycast and Klarity ship dark-first; Klarity was rejected for light-mode inconsistencies and found `.preferredColorScheme(.dark)` must be set per scene, not per view [[Klarity](https://www.klaritydisk.com/blog/building-liquid-glass-ui-macos)] [[shadcn.io/design/raycast](https://www.shadcn.io/design/raycast)].

**Risks of forced dark on 26.** (1) Small glass elements flip light/dark with content beneath; a forced-dark panel over a light desktop is a dark island [[WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/)]. (2) Increase Contrast makes glass black/white with borders; Reduce Transparency frosts it — surfaces must hold 4.5:1 under both, separately and together [[WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/)] [[HIG Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)]. (3) Users can now pick Clear/Tinted glass in 26.1; custom glass must look right under both [[theodorehq](https://www.theodorehq.com/solace/blog/posts/macos-tahoe-dark-mode-guide)]. (4) Native Forms inherit the app appearance, so Settings goes dark on a light system — consistent, but deliberate.

## 5. Accessibility bar

Apple's audit expects: descriptive labels (identifiers, not labels, for test IDs), valid parent/child hierarchy and actions, hit regions, no clipped text, WCAG AA contrast — 4.5:1 up to 17 pt, 3:1 at 18 pt or bold [[Performing accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)] [[HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)]. `XCUIApplication.performAccessibilityAudit()` runs the same checks in UI tests; one screen per audit, so add one per state and filter accepted issues individually [[WWDC23 10035](https://developer.apple.com/videos/play/wwdc2023/10035/)]. Also: convey state with more than colour (the tally light needs a shape or text twin), motion optional, text enlargeable to 200 % [[HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)] [[HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)]. App Store Accessibility Nutrition Labels make support a visible premium signal [[HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)]. Audits do not replace VoiceOver passes [[WWDC23 10035](https://developer.apple.com/videos/play/wwdc2023/10035/)].

## Recommendations for Cutaway (ranked)

**KEEP:** NSStatusItem + NSPopover; template status glyph with green/amber/red only as state; custom-drawn panel *content*; native Forms for Settings and sheets; font tokens; contrast test suite; accessibility-setting handling.

1. **Build with the 26 SDK; audit the popover shell (S).** Remove any visual-effect view behind popover content; check for hard-coded control heights. Why: Apple's adoption checklist; taller controls clip [[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)] [[WWDC25 310](https://developer.apple.com/videos/play/wwdc2025/310/)].
2. **Rebuild the app icon in Icon Composer (M).** Why: legacy `.icns` lands in "icon jail" on 26; Xcode derives the 14–15 icon from the same file [[Creating your app icon](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)] [[Successful Software](https://successfulsoftware.net/2025/09/26/updating-application-icons-for-macos-26-tahoe-and-liquid-glass/)].
3. **Decide appearance at app level, not per view (S).** If dark-only stays: `NSApp.appearance = .darkAqua`, document it as a media-instrument exception, verify Increase Contrast × Reduce Transparency and 26.1 Clear/Tinted. Otherwise ship a light token set. Why: HIG "rare cases"; App Review rejects half-done light modes [[HIG Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)] [[Klarity](https://www.klaritydisk.com/blog/building-liquid-glass-ui-macos)].
4. **Harden the status glyph for the transparent menu bar (S).** Bitmap-backed template for idle, pre-coloured non-template copies for tally states, never `contentTintColor`. Why: Tahoe tinting failures [[NOTCHYLIMIT #14](https://github.com/I-N-SILVA/NOTCHYLIMIT/pull/14)] [[Bjango](https://bjango.com/articles/designingmenubarextras/)].
5. **Add `performAccessibilityAudit()` per panel state (S).** Why: Apple's audit definition; feeds the Nutrition Label [[WWDC23 10035](https://developer.apple.com/videos/play/wwdc2023/10035/)] [[HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)].
6. **Tally light: add a non-colour twin (S).** SF Symbol or label alongside the border colour. Why: "more than color alone" [[HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)].
7. **Restrain the cyan (S).** Signal colour only for state and primary action; hairlines over shadows. Why: Things/Raycast pattern and Apple's tint rule [[Things 3](https://blakecrosley.com/guides/design/things)] [[WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/)].
8. **Motion budget (S).** Transitions ≤ 250 ms; one ~500 ms spring + optional sound for start/stop; gated on Reduce Motion. Why: HIG motion guidance; Things' reward pattern [[HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)] [[Things 3](https://blakecrosley.com/guides/design/things)].
9. **Optional 26-only footer glass (M).** One `GlassEffectContainer` around the footer behind `@available(macOS 26)`; none in hero or rows. Why: on-doctrine; adjacent glass needs a container [[WWDC25 323](https://developer.apple.com/videos/play/wwdc2025/323/)] [[HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)].
10. **Dev hygiene (S).** Throwaway bundle IDs for test builds; a hotkey fallback entry point. Why: ControlCenter ledger; "Allow in Menu Bar" [[Superposed](https://superposed.app/blogs/menu-bar-icon-blocked-macos-tahoe)] [[akring](https://blog.akring.com/posts/a-strange-bug-caused-by-swiftui--macos-26/)].

## Sources

1. https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
2. https://developer.apple.com/videos/play/wwdc2025/310/
3. https://developer.apple.com/videos/play/wwdc2025/323/
4. https://developer.apple.com/videos/play/wwdc2025/356/
5. https://developer.apple.com/videos/play/wwdc2025/219/
6. https://developer.apple.com/videos/play/wwdc2025/361/
7. https://developer.apple.com/videos/play/wwdc2023/10035/
8. https://wwdcnotes.com/documentation/wwdc25-256-whats-new-in-swiftui/
9. https://developer.apple.com/design/human-interface-guidelines/materials
10. https://developer.apple.com/design/human-interface-guidelines/the-menu-bar
11. https://developer.apple.com/design/human-interface-guidelines/popovers
12. https://developer.apple.com/design/human-interface-guidelines/dark-mode
13. https://developer.apple.com/design/human-interface-guidelines/motion
14. https://developer.apple.com/design/human-interface-guidelines/accessibility
15. https://developer.apple.com/design/human-interface-guidelines/typography
16. https://developer.apple.com/design/human-interface-guidelines/onboarding
17. https://developer.apple.com/design/human-interface-guidelines/app-icons
18. https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
19. https://developer.apple.com/icon-composer/
20. https://developer.apple.com/documentation/appkit/choosing-a-specific-appearance-for-your-macos-app
21. https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app
22. https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/
23. https://developer.apple.com/design/awards/2025/
24. https://developer.apple.com/design/awards/2024/
25. https://developer.apple.com/design/awards/2023/
26. https://www.apple.com/newsroom/2025/06/apple-unveils-winners-and-finalists-of-the-2025-apple-design-awards/
27. https://www.macrumors.com/2026/04/06/apple-liquid-glass-design-gallery-update/
28. https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast
29. https://www.shadcn.io/design/raycast
30. https://blakecrosley.com/guides/design/things
31. https://apps.apple.com/us/app/klack/id6446206067?mt=12
32. https://www.pocket-lint.com/klack-mechanical-keyboard-app/
33. https://thesweetbits.com/tools/cleanshot-review/
34. https://coyotetracks.org/blog/app-feel-on-mac/
35. https://bjango.com/articles/designingmenubarextras/
36. https://fazm.ai/blog/swiftui-menu-bar-app-floating-window-best-practices
37. https://techconcepts.org/blog/macos-menu-bar-guide
38. https://github.com/ingo-eichhorst/Irrlicht/issues/189
39. https://blog.akring.com/posts/a-strange-bug-caused-by-swiftui--macos-26/
40. https://superposed.app/blogs/menu-bar-icon-blocked-macos-tahoe
41. https://github.com/I-N-SILVA/NOTCHYLIMIT/pull/14
42. https://multi.app/blog/pushing-the-limits-nsstatusitem
43. https://www.klaritydisk.com/blog/building-liquid-glass-ui-macos
44. https://www.theodorehq.com/solace/blog/posts/macos-tahoe-dark-mode-guide
45. https://thesweetbits.com/tools/bartender-review/ and https://9to5mac.com/2026/01/27/a-decade-with-bartender-showed-me-how-overdue-this-macos-feature-is/
46. https://successfulsoftware.net/2025/09/26/updating-application-icons-for-macos-26-tahoe-and-liquid-glass/

## Methodology

Searched with Exa (semantic) across Apple developer documentation, WWDC 2025/2023 transcripts, Apple Newsroom, ADA pages and developer write-ups; fetched full HIG pages for menu bar, materials, dark mode, motion, accessibility, typography, onboarding, popovers and app icons. Apple sources treated as authoritative; third-party sources restricted to ≤18 months where possible (exceptions: Bjango 2022 and Multi 2023, retained because no newer equivalent exists and both concern stable AppKit behaviour). Premium-app "patterns" are inferred from published reverse-engineered token sets and reviews, not from vendor design documentation; treat numeric values there as indicative. Single-source Tahoe bug reports (ControlCenter ledger, MenuBarExtra launch failure, template tinting) were not independently reproduced.

# Accessibility — what has to be checked by hand

Most of this app's accessibility is asserted by tests: contrast is computed
from the tokens, spoken labels are pure functions with unit tests, and the
XCUITest accessibility audit runs five audit types over the main window.

What follows cannot be automated, either because macOS has no audit type for
it or because driving it through XCUITest measures event delivery rather than
the app. Run it before a release. It takes a few minutes.

## 1. Keyboard, end to end

Preconditions: **System Settings → Keyboard → Keyboard navigation ON**, and
all Cutaway windows closed so the app is in accessory mode.

| # | Do this | Expect |
|---|---------|--------|
| 1 | Press **Ctrl-F8** | A focus ring appears on a menu bar extra |
| 2 | Arrow to Cutaway, press **Return** | The panel opens |
| 3 | Press **Escape** | The panel closes, and focus returns to the status item |
| 4 | Return, then **Cmd-Q** | The app quits |
| 5 | Relaunch, **right-click** the pill | Menu: Open Cutaway · Settings… · Pause/Resume · Quit Cutaway |

Steps 3, 4 and 5 are also covered by `MenuBarKeyboardTests`, so this is a
belt-and-braces check rather than the only guard. Step 3 is WCAG 2.1.2 (No
Keyboard Trap): if Escape does not close the panel, that is a defect, not a
nuisance.

If those UI tests ever fail, read the failure text before believing the
result. "Timed out while enabling automation mode" means the test runner did
not start — usually a stale Cutaway process from an earlier run — and says
nothing about the app. `pkill -f Cutaway.app` and run again.

## 2. Light appearance

The status bar follows the **system** appearance, not the app's forced dark
scheme, so the pill is the one surface that can be illegible for a
Light-mode user.

1. System Settings → Appearance → **Light**
2. Look at the pill: the time must be plainly readable, and the coloured
   border must be visible against the bar.
3. Switch to **Dark** and repeat.

Contrast is asserted numerically against both appearances in
`MenuBarContrastTests`, but only against approximated bar colours — the real
bar is translucent over the wallpaper. This step is the check that the
approximation holds.

## 3. Colour vision

Xcode → Open Developer Tool → **Accessibility Inspector** → Color Filters,
or System Settings → Accessibility → Display → Color Filters.

With **Deuteranopia** on, confirm each is still distinguishable:

- The pill's three states — recording, paused, no project. They are
  shape-coded (filled dot · two bars · empty) as well as hued, so this should
  hold on shape alone.
- The project switcher's current-project marker (filled disc vs ring).
- The budget bar's warning levels — backed by a numeric "% used".

macOS has **no `.trait` accessibility audit** (it is iOS-only), so nothing
automated will ever catch a missing selected-state or a colour-only cue.

## 4. Increase Contrast and Reduce Transparency

System Settings → Accessibility → Display.

The app reads `NSWorkspace.accessibilityDisplayShouldIncreaseContrast`, not
the appearance. That distinction matters and cost a broken release once:
macOS collapses the accessibility appearance names, so

    NSAppearance(named: .accessibilityHighContrastDarkAqua)?.name
      == NSAppearanceNameDarkAqua

and any implementation that matches on the appearance name silently never
fires. `SystemSettingsTests` pins that platform fact.

To check the whole path by hand:

1. Turn **Increase Contrast** on. Card outlines, the ring track and the
   dividers in Settings should all visibly strengthen. The alphas roughly
   triple: 0.08 → 0.30 for card edges.
2. Turn **Reduce Transparency** on and open the menu-bar panel. It should
   become opaque instead of showing the desktop through it.
3. Turn **Reduce Motion** on. The panel should appear without its scale-in
   animation, and the pause button should not scale on hover or press.

## 5. VoiceOver spot check

`Cmd-F5`. Then:

- Focus the pill. It should say the state, the duration in words, and the
  project — **once**. It must not repeat every second.
- Open the panel. The hero must announce the time and the project, not just
  "Open Cutaway".
- Go to Stats. Each day row must state its date, hours and amount. If every
  row says the same thing, the container label has swallowed its children
  again.
- Force a project auto-switch (open a different project in Resolve). It
  should be announced.

## Appearance

Cutaway is dark-only as an instrument exception, decided once at the app
level (`NSApp.appearance` in `AppDelegate`), never per view. The manual
checks above for Increase Contrast and Reduce Transparency apply to it
unchanged — those settings are honoured by the tokens, not by the scheme.

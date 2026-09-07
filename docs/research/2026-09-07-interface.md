# Interface: what to delete, what to make editable, and the day timeline

*2026-09-07 · INTERFACE · reads: the 2026-09-05 design-language and premium-audit reports, spec 2026-09-04 Part 4, and the code.*

Evidence: `defaults read com.vaneickelen.cutaway` holds eight keys — three window
frames, `accessibilityOfferDismissed`, `didMigrateFromResolveTimer`,
`didShowPermissionsPrimer`, `lastBackupAt`, `manuallyPaused`. Not one preference.
The nine-row Settings the spec called for is fifteen controls, all at default.

## 1. Deletions — `Settings/SettingsView.swift` unless noted

| Delete | Right default that replaces it |
|---|---|
| **Idle threshold** picker | Fixed 120 s. Key stays read for anyone who set it. |
| **After a manual pause** picker | Fixed `ask`. The decision already lives on the card; add "Not today" to its *No*, which is what a mode picker was standing in for. |
| **Menu bar shows** picker | Fixed `today`. The panel already itemises session and project total one click away. |
| **Workflow apps** + **Research & comms** rows, and `Settings/AppListEditor.swift` (62 lines) | The per-project `AppPickerView` in `ProjectSheet` is the editor, and its "Choose app…" is the escape hatch. Globals become constants in `DetectionInput`; both pref keys stay read. |
| **Default hourly rate** + **Default currency** | Seed a new project from the most recently created project instead (`Projects/ProjectsModel.swift`). Zero knobs, better answer — the owner sets rate per job anyway. |
| **Back up now**, **Reveal backups…**, Diagnostics **Reveal…** | Backups run daily/launch/quit and Restore's `NSOpenPanel` already opens that folder. Keep the last-backup line, **Restore…**, **Copy report**. |
| **Permissions…** row and the whole `permissions` window scene (`App/CutawayApp.swift`) | Fold `PermissionsView`'s two rows and its never-does statement into a Settings "Permissions" section. This is a *fourth window* today, against the charter. |

**Keep:** the render exemption (an opt-in consent to bill unattended time, not a
preference), Launch at login, the Resolve status line, the hotkey-taken line.
Result: 8 rows, 2 of them toggles, 3 surfaces.

## 2. Editability, end to end

**Correctable today:** project name / client / mode / rate / budget / currency /
per-project apps (`ProjectSheet`); a day's **total** as hours or money
(`Stats/EditDaySheet.swift`); adding a missing day; deleting a project with
session reassignment.

**Not correctable:** one session's start or end · one session's deletion · moving
a session or day to another project · splitting a day across two projects ·
anything at all from the panel · **undo, anywhere**.

Three defects found while reading:

- **A (money-losing).** `App/CutawayApp.swift:96` builds `EditDaySheet` from
  `model.selectedProject`, but `DayEditTarget` carries only a `Date`. Detection
  auto-switches projects; if it switches while the sheet is open, the sheet keeps
  project A's prefilled figures and Save writes them to project B. Fix:
  `DayEditTarget` carries the project's `PersistentIdentifier`, and the sheet
  titles itself with that project's name.
- **B.** `WorkSession` stamps `hourlyRate` but not currency (`Projects/Models.swift`).
  Changing a project CHF→EUR silently re-denominates invoiced history. Stamp
  `currencyRaw` the same way; a project spanning two currencies shows two subtotals.
- **C.** `SessionStore.setActiveSeconds` *deletes* real sessions when a day shrinks —
  permanently, silently, unconfirmed.

**Should become editable.** `Stats/SessionEditSheet.swift` (new) replaces
`EditDaySheet`: native Form — Project (picker over all projects, so changing it
*moves* the session) · Day · Start · End · Active time (defaults to the span,
editable down; upward is flagged) · a line "3.2 h of a 3.5 h span — 18 min idle
excluded" · destructive **Delete session** on the left · Cancel / Save. Split
lives on the block (below), and splitting a day across two projects is
"select blocks → Assign to ▸", not its own feature.

**Undo** — `Projects/EditHistory.swift` (new). Every mutating `SessionStore` call
returns its inverse; `AppModel` owns an `UndoManager`; ⌘Z works in Stats *and* in
the panel. Depth 20, cleared at quit. This is what makes deletion and trimming
one click instead of a confirmation dialog, and it is the fix for defect C.

**Honesty.** `isAdjusted` already reaches `DayTotal.adjustedSeconds` → CSV
`adjusted_hours` → the Stats pencil. Extend it exactly: a typed start/end/amount
sets it; a *reassign* or a *split* does not (nothing was invented); a delete
leaves nothing to flag. The invoice prints the per-day marker and a footer,
"2.5 h of 41.0 h entered by hand".

## 3. The day timeline — `Stats/DayTimelineView.swift` (new)

Replaces `StatsView.sessionDetail`. Clicking a day row still unfolds it; what
unfolds is a strip. It is the removed reclaim prompt's replacement: the gap is
*visible*, and dragging an edge over it is how you claim it.

**Layout.** One strip, row width minus the 14 pt insets, 44 pt tall, `DT.card2`,
`DT.rMd`. Domain runs from the hour containing the day's first start to the hour
containing its last end — minimum 4 h, never 00:00–24:00: an editor's day is six
hours wide and a calendar axis turns every session into a sliver. Hour ticks:
1 pt `DT.strokeSubtle` + a 10 pt `DT.text3` label each hour up to 8 h, every two
hours beyond, dropped before they collide.

**Blocks.** One per `WorkSession`, `DT.recording.opacity(0.8)`, 3 pt radius,
**6 pt minimum width** — a 90-second session must stay grabbable; the strip is a
control, not a chart. `isAdjusted` sessions (including today's zero-span typed
adjustments) draw hatched at a fixed 24 pt with a pencil, plus a caption
"＋2:00 entered by hand" — typed time has no span and must not pretend to one.
The live session pulses its trailing edge and is not draggable. A gap over
20 minutes shows a centred "—" with its length in the tooltip.

**Mouse.** Hover lifts to full opacity and shows "09:12–11:40 · 2.4 h · CHF 240".
Click selects (1.5 pt `DT.signal` outline); the track deselects. Drag the body:
moves start and end together, snapping to 5 min (⌥ for 1 min) — active seconds
unchanged, because a move corrects *when*, never *how much*. Drag an edge: trims;
active seconds scale with the span; flagged only when dragged outward. Blocks
never overlap — a neighbour yields. Double-click opens `SessionEditSheet`; the
strip is for the gesture, the sheet is for the number. Right-click: **Split
here…** (at the click's time, distributing active seconds by wall-clock fraction
via the existing `DaySplitter` rule) · **Assign to ▸** · **Delete**. ⌘Z undoes
each.

**Keyboard.** Tab reaches the strip. ←/→ move selection between blocks, Home/End
to the ends. ⌥←/→ move the block 5 min; ⇧⌥←/→ trim the end; ⌃⌥←/→ trim the start.
Return edits, ⌘K splits at the midpoint, ⌫ deletes, ⌘Z undoes. VoiceOver: each
block is an element — "09:12 to 11:40, 2 hours 28 minutes, 248 francs, tracked" —
carrying custom actions Edit, Split, Assign to…, Delete. Nothing on the strip is
mouse-only.

**Empty day** (reached via ＋ Add, or after deleting everything): track and ticks
over 09:00–17:00, one centred line "No sessions on this day", one button "Add a
session…" prefilled 09:00–17:00 for that day's project.

**Fourteen sessions.** A 10 h day of 14 sessions averages 35 min each. At the
Stats window's 480 pt minimum the strip is ~440 pt, so an hour is ~44 pt and a
35 min block ~26 pt — comfortable; the 2-minute check-in draws at its 6 pt floor.
No zoom, no scroll, no stacking: the whole day fits because the domain is the
working day. Caption beneath: "14 sessions · 9:40 tracked · 1:10 in gaps". Past
14 h of domain the strip wraps to two rows split at the median gap — one wrap,
never more.

## 4. The invoice quarter, inside three surfaces

Deleting the permissions window (§1) buys the budget back.

- **Client + tax** → a third section in `Projects/ProjectSheet.swift`: client name
  (promoted), address, tax mode picker (CH 8.1 % + UID · below threshold · EU
  reverse charge · other), UID shown only for the first. No Clients window: one
  client per project, and a second project offers "Copy from…".
- **Billing status per day** → a fourth column in the Daily Breakdown
  (`Stats/StatsView.swift`): 6 pt dot + `DT.text3` label — unbilled (no dot),
  invoiced (amber), paid (green). Set by ⇧-selecting rows → "Mark as ▸". Invoiced
  days lock: blocks at 0.6 opacity, edits refused with "Days on INV-2026-0007 are
  locked. Unlock the invoice to edit." New `Billing/BillingStatus.swift`;
  `WorkSession.invoiceID: String?` in `Models.swift`.
- **Invoice preview + export** → `CSVExportButton` becomes an "Export ▾" menu with
  **Invoice PDF…** above the CSV periods. It pushes a full-window preview *inside*
  the Stats window — back chevron, invoice number, period picker, Export / Cancel
  bottom bar. `Billing/InvoiceView.swift`, `ImageRenderer` to PDF. Stats is the
  document surface; the invoice is a view of the same document.
- **Unbilled total** → one footer line in `MenuBar/MenuBarPanel.swift`,
  "CHF 4,280 unbilled · 3 projects", `DT.captionMedium` / `DT.text3`, click opens
  Stats. A ninth case in `PanelBlock`, shown only when non-zero — the only block
  worth adding to that enum.

## 5. The forgotten states

| State | Verdict |
|---|---|
| No project | Red pill, empty ring, zero-state card, pause disabled. Correct. |
| First run | Permissions window fires before the panel is ever opened. After §1 it is a Settings section; the zero-state card carries first run. |
| 14-hour day | Pill `14:23:45`, width synced. Fine. |
| 60-char name | Truncates in the panel hero (~216 pt), the panel row and the Stats header. **Add `.help(project.name)`** at all three — the full name is currently unreachable. |
| German | `MenuBarPanel.resumeBanner` — "Sieht aus, als würdest du arbeiten" has no `lineLimit`/`minimumScaleFactor` and shares a 340 pt row with a button. It will squeeze the button. Fix there; the footer and `PromptCard` (400 pt) hold. |
| VoiceOver | Pill, hero, rows, day rows are done. `sessionLine` reads as three loose elements — the timeline's per-block element fixes it. Budget bar needs an `accessibilityValue`; `heroRing` needs `accessibilityHidden`. |
| Increase Contrast | `AccessibilityAuditTests` filters contrast issues on "intentionally-muted tertiary text". That filter is hiding the one check that matters — route `DT.text3` through the existing contrast escalation instead. |
| Reduce Transparency | Handled (`.ultraThinMaterial` → `DT.overlay`). Correct. |
| Second display | `MenuBar/PromptPanel.swift` positions on `NSScreen.main` at `visibleFrame.maxY − h − 12`. Under a full-screen Resolve the menu bar auto-hides, so the card can land under it. Clamp to `screen.frame.maxY − 34`. |

## 6. Where the conventions stand

macOS 26 guidance for menu-bar extras is unchanged from 2026-09-05: prefer a
menu, popover only when a menu cannot carry it, template imagery, never assume
the item is visible
([HIG](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar),
[Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers)).
The live risk is Tahoe's Control Center hand-off: a status item can register in
AppKit and never render
([CodexBar #802](https://github.com/steipete/CodexBar/issues/802)) — which is why
⌥⌘P and Dock reopen must stay as non-menu-bar entry points. `NSPopover.contentSize`
still clips silently ([2026 guide](https://techconcepts.org/blog/macos-menu-bar-guide)).
Do not chase Tahoe's menu-item icons: they were criticised on arrival
([Daring Fireball](https://daringfireball.net/2026/03/what_to_do_about_those_menu_item_icons_in_macos_26_tahoe))
and macOS 27 reverses them ([MacRumors](https://www.macrumors.com/2026/06/11/macos-27-golden-gate-menu-items/)).

Inline correction in the paid field: Timing creates an entry by dragging a range
on the timeline — which *splits* whatever it lands on — deletes via right-click,
and reassigns by dragging entries onto a project
([docs](https://timingapp.com/help/time-entries)). Timemator's daily view is
explicitly "like the Calendar app" ([timemator.com](https://timemator.com/)).
Klokki Slim carries billing *states* on sessions ([klokki.com](https://www.klokki.com/)).
The strip is not the differentiator — everyone has one. The trace is.

*Confidence: high on the code and prefs evidence; medium on the HIG citations
(thin fetches; conventions carried from 2026-09-05).*

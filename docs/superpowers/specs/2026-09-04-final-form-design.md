# Cutaway — final form: merge, per-project apps, reorganize

Date: 2026-09-04. Decisions from a grilled design session; nothing here is
a guess.

## Positioning (unchanged)

Cutaway stays a Resolve-first tool for editors. Resolve project detection
is the differentiator. Other apps are anchors a video project may use;
the README pitch, cask description and zero-state copy do not change.

## Part 1 — Merge the worktree branch

Source: `claude/time-tracking-edit-auto-resume-592ba4` (one commit,
670af20, based on stale `main`). Target: `autoresearch/aug20`. Seven
files conflict; both sides are kept everywhere.

| File | Resolution |
|---|---|
| DetectionEngine | worktree `autoResume` (off/ask/auto, 45 s anchor signal, 15 min ask cooldown) + this branch's pause persistence, `pausedLong`, idle warning, bridge-idle fix. Reclaim is merged as-is here and removed in Part 4. Auto-resume lifts the pause through `togglePause()` so `manualPauseStart` persistence stays correct. |
| NewProjectSheet / ProjectManageSheets | worktree `ProjectSheet` (create + edit) replaces NewProjectSheet and RenameProjectSheet; this branch's delete-with-reassignment sheet stays. |
| StatsView | worktree editable day rows + "＋ Add" on top of this branch's hierarchy pass and session detail rows. |
| MenuBarPanel / StatusItemController | worktree resume banner and pill hint on top of this branch's receipt line, research-window line, a11y. |
| SettingsView | worktree "After a manual pause" picker added to this branch's grouped sections. |
| GOALS.md / LOOP_JOURNAL.md | union. |

Honesty rules for the merged features:

- **Edits leave a trace.** `WorkSession.isAdjusted: Bool = false`. Sessions
  written by `setActiveSeconds(on:for:)` (growth adjustments) are
  `isAdjusted = true`. `DayTotal.adjustedSeconds` sums them. CSV gains an
  `adjusted_hours` column after `active_hours`. A Stats day row with
  adjustments shows a small pencil glyph with an accessibility label
  "includes manual adjustment". Trimming a day (shrinking) deletes real
  sessions and is not flagged — nothing was invented.
- **Forgotten-pause resume.** Modes off / ask / auto, default **ask**.
  README wording: a manual pause is sacred backwards — time before a
  resume is never billed — and the app may ask, or with the auto opt-in
  resume, forwards from the moment of live anchor input.

After the merge: `main` fast-forwards to the result and is pushed; the
worktree and its branch are deleted. No tag, no release.

## Part 2 — Per-project apps

### Semantics

- `Project.appBundleIDs: [String]` (SwiftData, default `[]`). Stored as
  bundle-id prefixes, same shape as the global `workApps` pref.
- **Gate, not memo.** While a project is selected, its list *replaces* the
  global anchor list. An empty list means "use the global list" (legacy
  projects, and the fallback).
- **Pre-ticked.** The create sheet starts with every entry of the current
  global anchor list ticked. Auto-created Resolve projects are created
  with the global list as their `appBundleIDs`. The normal case needs
  zero clicks; a narrow job (an InDesign-only template) is an untick.
- Everything ticked is an anchor. Satellites stay global and unchanged.
  Auto-switch is unchanged.
- Sheet hint under the picker: "Only these apps count toward this
  project."
- `AnchorSet.resolve(project: [String], global: [String]) -> [String]` is
  the single pure function that decides; `AppModel.select` and project
  creation push its result into `engine.workAppPrefixes`. Editing a
  project's list while it is selected pushes immediately.

### Catalog (`AppCatalog.swift`, pure data)

Groups → entries `(name, prefix)`:

- **DaVinci Resolve**: Resolve, Resolve Studio (the three known ids).
- **Adobe**: Premiere Pro, After Effects, Photoshop, Illustrator,
  Audition, Lightroom Classic, InDesign, Media Encoder.
- **Microsoft Office**: Word, Excel, PowerPoint, Outlook, OneNote.
- **Also**: Final Cut Pro, Motion, Compressor, Logic Pro, Blender,
  Affinity Photo, Affinity Designer, Figma, Notion.
- **Other…**: every `.app` in `/Applications` and `~/Applications`, name
  and `CFBundleIdentifier` read from `Info.plist`, sorted by name,
  excluding ids already in the catalog. Scan runs once per sheet open,
  off the main thread.

Test: no two catalog prefixes are equal or prefix one another.

### Icons

`NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` →
`NSWorkspace.shared.icon(forFile:)`. Cached per bundle id in a small
`AppIconCache` (NSCache). Not installed → SF Symbol `app.dashed` at 50 %
opacity, tooltip "Not installed". No third-party artwork is shipped.

### UI

- `AppPickerView`: grouped grid of toggle tiles (icon + name), search
  field filtering across groups, "Other…" disclosure at the bottom. Tiles
  are buttons with `accessibilityValue` on/off; keyboard reachable.
- Lives in `ProjectSheet` (create and edit).
- Project icon row: up to four icons then "+N", on each project row in
  the menu-bar panel and in the Stats header. Icons are decorative
  (`accessibilityHidden`); the row's label already names the project.

### Migration

Added properties with defaults (`appBundleIDs`, `isAdjusted`) are
SwiftData lightweight migrations. DisasterRecoveryTests gains a case that
opens a pre-change store fixture and reads a project.

### Tests

- `AnchorSet.resolve`: empty → global; non-empty → project list verbatim.
- Engine: an Excel-only project records under `com.microsoft.Excel`, not
  under Resolve; switching to a project with an empty list restores the
  global anchors.
- Catalog uniqueness; `/Applications` scan skips non-bundles and reads a
  known id (Finder is not in /Applications — use the test host's own
  bundle).
- Pre-tick: a new project's `appBundleIDs` equals the global list at the
  time of creation.
- CSV: `adjusted_hours` column present, zero for untouched days, equal to
  the adjustment on an edited day; totals still reconcile.

## Part 3 — Reorganize and finish the rename

Done last, on a green tree, one commit per move, tests untouched (same
module).

- Product, folder, project and targets become **Cutaway**:
  `Sources/Cutaway`, `Cutaway.xcodeproj` (via `project.yml`),
  `CutawayTests`, `CutawayUITests`. Env vars `TIMEX_*` → `CUTAWAY_*`
  (`scenario`, `data dir`, `demo`). `scripts/smoke.sh` and
  `scripts/release.sh` paths updated (DerivedData glob `Cutaway-*`).
- **Not renamed**: the on-disk store files (`default.store`,
  `timex.store` in scenario dirs) and the `Prefs` suite — renaming them
  strands existing users' data.
- Feature folders under `Sources/Cutaway/`:
  `App/` (CutawayApp, AppModel, Prefs, HotKey, ScenarioDriver),
  `Detection/`, `Projects/` (Models, SessionStore, DaySplitter,
  StoreBackup, ProjectSheet, delete sheet, AppCatalog, AppPickerView,
  AppIconCache, AnchorSet), `Billing/` (BillingEngine, CSVExporter,
  CSVExportButton), `Timer/`, `Stats/` (StatsView, EditDaySheet),
  `MenuBar/` (MenuBarPanel, StatusItemController, IdleWarningPanel,
  ReclaimPanel, ResumeNotifier), `Settings/` (SettingsView,
  AppListEditor), `Design/` (DesignTokens, Components, RingView).
- `AppModel` split: project selection, creation, switching, rename and
  delete move to `ProjectsModel`; live figures, announcements, zero
  state, accessibility offer stay in `AppModel`. Public surface used by
  views is preserved by forwarding where a rename would touch many
  views.
- graphify: `graphify update .` after the merge (the map guides the
  split) and again after the reorg; `graphify-out/` committed.

## Part 4 — UI: fit to the owner's day, as little as possible

Decided surface by surface. "Minimal" means fewer surfaces and fewer
knobs, not fewer pixels.

### Surfaces

- **Menu-bar-first.** The pill and its panel are the app. The main
  window's *Timer* tab is removed; the main window becomes the **Stats**
  window (no tabs, `MainTab` enum deleted). The zero-state copy and the
  one-time Accessibility offer move into the panel, where they were
  needed anyway (the panel is what a new user opens first).
- **Settings** stays a window. **Stats** stays a window. Four windows
  become three (pill/panel, Stats, Settings).

### Removed outright

- **Daily-goal ring** and the `dailyGoalHours` setting: `RingView`,
  `BillingEngine.goalProgress`, `GoalProgress`, their tests and tokens.
  The hero shows today's time and money; "enough today?" is a Stats
  question. The pref key is left unread (no migration needed).
- **Reclaim offer**: `ReclaimOffer`, `ReclaimPanel`, `reclaimGapStart`,
  `acceptReclaim`/`declineReclaim`, `ReclaimOfferTests`, and the
  reclaim half of the bridge-idle fix (the session-close half stays —
  that was the bug). Away time beyond the bridge is gone; the day editor
  covers the rare case, and with a trace.
- **Settings rows** for bridge grace and research window. Both keep
  their pref keys and defaults (180 s, 1200 s) so anyone who set them is
  unaffected; the rows are simply not shown.

### Settings, final list

Idle threshold · After a manual pause (off / ask / auto) · Render
exemption (opt-in) · Work apps · Support apps · Default currency ·
Default rate · Menu bar shows (today / session / total) · Accessibility
status. Nine rows, grouped as now.

### Interruptions

Two cards: *"Still working?"* (idle warning) and *"Are you working?"*
(forgotten-pause resume). One shared `PromptCard` component. Invariant,
tested: never two on screen — the resume prompt does not fire while an
idle warning is showing, and vice versa (they cannot coincide by state,
manual-paused vs recording, but the test pins it).

### Look

- **Native where nobody looks twice.** Settings, `ProjectSheet`, the
  delete sheet and `EditDaySheet` become standard SwiftUI `Form` with
  `.formStyle(.grouped)` and system controls (`TextField`, `Picker`,
  `Toggle`). The app picker is native too: a `LazyVGrid` of `Toggle`
  buttons with the app icon as label. No custom field chrome, no custom
  segmented control, no bespoke contrast proofs for these.
- **Custom stays** on the pill, the panel and Stats — that is where the
  identity lives. `DesignTokens` and `Components` shrink to what those
  three still use; `ContrastTests`/`DesignTokenGuardTests` shrink with
  them. Increase Contrast / Reduce Transparency handling stays for the
  custom surfaces only.
- `AppListEditor` (bundle-id popover) stays as the escape hatch behind
  Work apps / Support apps, rebuilt on `Form`.

### Tests

- Panel shows the zero-state title when there is no project.
- Panel shows the Accessibility offer exactly under the policy that
  used to gate it on the Timer tab (policy unchanged, tests re-pointed).
- Two-cards-never invariant.
- Removed features take their tests with them; nothing is left
  `XCTSkip`ped.

## Order and gates

merge → graphify → per-project apps → UI (Part 4) → reorganize + rename → graphify.
Every step ends with the unit suite green, `scripts/smoke.sh "" 3` ALL
PASS, and the accessibility UI test green for anything visual. Journal
and results ledger updated per step, as the loop does.

`main` is pushed after the merge step and again at the end. No tag, no
release: the human runs `scripts/release.sh 1.2.0` after a day of use.

## Out of scope

Per-project satellites. Auto-switch by app. Detection of Adobe project
names. Bundled logos. Any change to billing arithmetic. Restyling the
pill, panel or Stats.

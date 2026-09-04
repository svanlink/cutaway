# Graph Report - cutaway  (2026-09-04)

## Corpus Check
- 100 files · ~150,852 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1529 nodes · 3339 edges · 85 communities (77 shown, 7 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 350 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `c1a84a91`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- BillingEngine
- XCTest
- Cutaway Loop Journal
- DT
- XCTestCase
- AccessibilityOfferTests
- AppModel
- RecordingSource
- .export
- DetectionFollower
- String
- InvoicePeriodTests
- DetectionEngine
- EngineClockTests
- View
- SessionLogger
- DetectionStateTests
- SessionStoreTests
- ReclaimOfferTests
- .tick
- Cutaway — final form: merge, per-project apps, reorganize
- .update
- IdleWarningTests
- .record
- RenderExemptionTests
- BackupCostTests
- SwitcherList
- DisasterRecoveryTests
- .survivors
- SessionStore
- PillBody
- BackupWALTests
- ContrastTests
- FullScreenSuppressionTests
- AppDelegate
- Foundation
- SystemProbing
- MoneyDefaultsTests
- .project
- .togglePause
- EditDaySheet
- PausePersistenceTests
- .backUp
- .init
- RecordingSourceTests
- Project
- Global Constraints
- StatusItemController
- LastSessionReceiptTests
- SessionDetailTests
- SettingsView
- InstalledApp
- IdleWarningController
- ProjectSheet
- .label
- TimerView
- README.md
- SwiftUI
- SpokenContentTests
- Accessibility — what has to be checked by hand
- .earnings
- AnchorSetTests
- TimexCurrency
- SessionAccumulator
- FakeProbes
- Cutaway — Improvement Loop Backlog
- smoke.sh
- .render
- MenuBarKeyboardTests
- loop.sh
- release.sh
- SessionRecord
- FakeProbes
- CoreGraphics
- PauseReason
- Double
- RingView
- AppIconView
- .forecast
- Global Constraints
- SwiftData
- ReclaimView
- .restoredStart
- DesignTokenGuardTests

## God Nodes (most connected - your core abstractions)
1. `AppModel` - 98 edges
2. `Cutaway Loop Journal` - 69 edges
3. `DetectionEngine` - 64 edges
4. `Project` - 54 edges
5. `SessionStore` - 50 edges
6. `XCTest` - 47 edges
7. `DetectionInput` - 45 edges
8. `Cutaway` - 45 edges
9. `SessionRecord` - 40 edges
10. `DetectionEngineTests` - 28 edges

## Surprising Connections (you probably didn't know these)
- `.resolveIsUp` --references--> `DetectionInput`  [EXTRACTED]
  Tests/TimexTests/Tier1LiveTests.swift → Sources/Timex/Detection/DetectionState.swift
- `.hero` --references--> `AppModel`  [INFERRED]
  Sources/Timex/UI/MenuBarPanel.swift → Sources/Timex/AppModel.swift
- `.accessibilityOffer` --references--> `AppModel`  [INFERRED]
  Sources/Timex/UI/TimerView.swift → Sources/Timex/AppModel.swift
- `DetectionEngineTests` --references--> `DetectionEngine`  [EXTRACTED]
  Tests/TimexTests/DetectionEngineTests.swift → Sources/Timex/Detection/DetectionEngine.swift
- `AutoResumeTests` --references--> `DetectionEngine`  [EXTRACTED]
  Tests/TimexTests/EditAndAutoResumeTests.swift → Sources/Timex/Detection/DetectionEngine.swift

## Import Cycles
- None detected.

## Communities (85 total, 7 thin omitted)

### Community 0 - "BillingEngine"
Cohesion: 0.15
Nodes (15): Equatable, BillingEngine, BudgetForecast, beyondHorizon, days, paceUnknown, BudgetStatus, BudgetWarning (+7 more)

### Community 2 - "Cutaway Loop Journal"
Cohesion: 0.03
Nodes (69): 2026-07-19 ~01:50 — [stability] Rename/delete projects — KEPT (210003c), 2026-07-19 ~02:15 — [stability] Editable app lists — KEPT (d01dcc4), 2026-07-19 ~02:15 — [stability] Editable app lists — KEPT (d01dcc4), 2026-07-19 ~02:30 — [design] Settings grouped sections — KEPT (96571c6), 2026-07-19 ~02:30 — [design] Settings grouped sections — KEPT (96571c6), 2026-07-19 ~02:50 — loop upgraded to autoresearch mechanics, 2026-07-19 ~02:50 — loop upgraded to autoresearch mechanics, 2026-07-19 ~03:05 — [ship] R-INSTALL — KEPT (+61 more)

### Community 3 - "DT"
Cohesion: 0.07
Nodes (34): NSAppearance, DT, .systemPrefersIncreasedContrast, Bool, CGFloat, Color, Double, Int (+26 more)

### Community 4 - "XCTestCase"
Cohesion: 0.20
Nodes (6): LongPauseHintTests, DetectionWiringTests, .appModelSource, String, DemoSeedGuardTests, XCTestCase

### Community 5 - "AccessibilityOfferTests"
Cohesion: 0.11
Nodes (11): AccessibilityOfferPolicy, Bool, String, TimeInterval, ZeroState, noProject, nothingTrackedYet, ZeroStatePolicy (+3 more)

### Community 6 - "AppModel"
Cohesion: 0.11
Nodes (18): AppModel, .accessibilityOfferDismissed, .dailyGoalHours, .goalProgress, .isPausedVisual, .lastSessionLine, .projects, .researchWindowIsClosing (+10 more)

### Community 7 - "RecordingSource"
Cohesion: 0.17
Nodes (13): DetectionState, paused, recording, IdleWarning, ReclaimOffer, .seconds, RecordingSource, anchor (+5 more)

### Community 8 - ".export"
Cohesion: 0.12
Nodes (14): CSVExporter, Double, CSVExporterTests, .cal, .sampleDays, Calendar, Date, Int (+6 more)

### Community 9 - "DetectionFollower"
Cohesion: 0.17
Nodes (8): DetectionFollower, ManualIntent, ProjectName, Bool, String, DetectionFollowerTests, ManualIntentTests, Token

### Community 10 - "String"
Cohesion: 0.09
Nodes (17): ApplicationServices, .detectLine, .zeroState, DetectionTier, manual, scriptingAPI, windowTitle, ProjectDetector (+9 more)

### Community 11 - "InvoicePeriodTests"
Cohesion: 0.11
Nodes (17): InvoicePeriod, allTime, lastMonth, thisMonth, thisYear, Calendar, Date, CSVExportButton (+9 more)

### Community 12 - "DetectionEngine"
Cohesion: 0.13
Nodes (11): DetectionEngine, .manuallyPaused, Bool, Date, Double, String, TimeInterval, UInt64 (+3 more)

### Community 13 - "EngineClockTests"
Cohesion: 0.19
Nodes (8): EngineClockTests, FakeProbes, Calendar, Date, Int, String, TimeInterval, UserDefaults

### Community 14 - "View"
Cohesion: 0.20
Nodes (13): DayEditTarget, DayTotal, .effectiveRate, Int, StatsView, .body, .project, Bool (+5 more)

### Community 15 - "SessionLogger"
Cohesion: 0.12
Nodes (12): SessionLogger, .logPath, Bool, Int, String, URL, SessionLoggerTests, .fm (+4 more)

### Community 16 - "DetectionStateTests"
Cohesion: 0.20
Nodes (4): DetectionStateTests, Bool, String, TimeInterval

### Community 17 - "SessionStoreTests"
Cohesion: 0.13
Nodes (7): SessionStoreTests, StoreBackupTests, Calendar, Date, Int, TimeInterval, URL

### Community 18 - "ReclaimOfferTests"
Cohesion: 0.22
Nodes (5): FakeProbes, ReclaimOfferTests, Date, String, TimeInterval

### Community 19 - ".tick"
Cohesion: 0.23
Nodes (8): DetectionInput, .frontmostIsAnchor, .frontmostIsSatellite, .isWorkContext, DetectionEngineTests, Date, Int, UserDefaults

### Community 20 - "Cutaway — final form: merge, per-project apps, reorganize"
Cohesion: 0.10
Nodes (20): Catalog (`AppCatalog.swift`, pure data), Cutaway — final form: merge, per-project apps, reorganize, Icons, Interruptions, Look, Migration, Order and gates, Out of scope (+12 more)

### Community 22 - "IdleWarningTests"
Cohesion: 0.18
Nodes (5): FakeProbes, IdleWarningTests, Date, String, TimeInterval

### Community 23 - ".record"
Cohesion: 0.25
Nodes (5): .pillSeconds, Calendar, TimeInterval, DayEditTests, Calendar

### Community 24 - "RenderExemptionTests"
Cohesion: 0.18
Nodes (7): FakeProbes, RenderExemptionTests, Date, Double, String, TimeInterval, UInt64

### Community 25 - "BackupCostTests"
Cohesion: 0.18
Nodes (9): BackupCostTests, .fm, Date, FileManager, Int, String, TimeInterval, URL (+1 more)

### Community 26 - "SwitcherList"
Cohesion: 0.20
Nodes (13): ModeTag, .body, ProjectPill, .body, Bool, PersistentIdentifier, Void, SwitcherList (+5 more)

### Community 27 - "DisasterRecoveryTests"
Cohesion: 0.18
Nodes (9): DisasterRecoveryTests, .fm, Calendar, Date, Double, FileManager, Int, TimeInterval (+1 more)

### Community 28 - ".survivors"
Cohesion: 0.24
Nodes (8): Date, Set, BackupRotationTests, .cal, Calendar, Date, Int, String

### Community 29 - "SessionStore"
Cohesion: 0.12
Nodes (15): ModelContainer, ModelContext, SessionStore, .context, Bool, Date, Double, PersistentIdentifier (+7 more)

### Community 30 - "PillBody"
Cohesion: 0.13
Nodes (16): .heroLabel, PillBody, .body, .miniRing, PillView, .accent, .body, .goalReached (+8 more)

### Community 31 - "BackupWALTests"
Cohesion: 0.21
Nodes (7): BackupWALTests, .fm, Date, FileManager, String, TimeInterval, URL

### Community 32 - "ContrastTests"
Cohesion: 0.27
Nodes (3): ContrastTests, Color, Double

### Community 33 - "FullScreenSuppressionTests"
Cohesion: 0.19
Nodes (6): FakeProbes, FullScreenSuppressionTests, Bool, Date, String, TimeInterval

### Community 34 - "AppDelegate"
Cohesion: 0.07
Nodes (24): Carbon.HIToolbox, EventHandlerRef, EventHotKeyRef, MainActor, Notification, NSApplication, NSApplicationDelegate, NSObject (+16 more)

### Community 35 - "Foundation"
Cohesion: 0.08
Nodes (18): Darwin, Foundation, os, PrefsMigration, ScenarioMode, .dataDir, .isActive, .scenarioPath (+10 more)

### Community 36 - "SystemProbing"
Cohesion: 0.22
Nodes (6): Bool, String, TimeInterval, UInt64, SystemProbes, SystemProbing

### Community 37 - "MoneyDefaultsTests"
Cohesion: 0.17
Nodes (5): .defaultCurrency, Locale, MoneyDefaultsTests, Locale, String

### Community 38 - ".project"
Cohesion: 0.32
Nodes (6): .todaySeconds, Calendar, Date, Int, String, TodayCacheTests

### Community 39 - ".togglePause"
Cohesion: 0.21
Nodes (5): AutoResumeTests, Date, Int, String, TimeInterval

### Community 40 - "EditDaySheet"
Cohesion: 0.22
Nodes (11): EditDaySheet, .body, .dayLabel, .isAdding, .seconds, Field, amount, hours (+3 more)

### Community 41 - "PausePersistenceTests"
Cohesion: 0.22
Nodes (6): FakeProbes, PausePersistenceTests, Date, String, TimeInterval, UserDefaults

### Community 42 - ".backUp"
Cohesion: 0.36
Nodes (6): FileFacts, StoreBackup, Bool, Int, String, URL

### Community 43 - ".init"
Cohesion: 0.39
Nodes (4): NSHostingView, ReclaimController, Bool, NSPanel

### Community 44 - "RecordingSourceTests"
Cohesion: 0.23
Nodes (5): RecordingSourceTests, Bool, Date, String, TimeInterval

### Community 45 - "Project"
Cohesion: 0.14
Nodes (17): Sendable, BillingMode, budget, hourly, Project, .mode, Bool, Date (+9 more)

### Community 46 - "Global Constraints"
Cohesion: 0.17
Nodes (11): Global Constraints, Plan 1 — Merge the worktree branch Implementation Plan, Task 1: Start the merge; resolve the two documentation conflicts, Task 2: DetectionEngine — both pause features, one engine, Task 3: ProjectSheet replaces NewProjectSheet + RenameProjectSheet, Task 4: StatsView — edit rows on top of session-detail rows, Task 5: Panel banner and pill hint, Task 6: Settings row "After a manual pause" (+3 more)

### Community 47 - "StatusItemController"
Cohesion: 0.22
Nodes (3): NSStatusItem, StatusItemController, Any

### Community 48 - "LastSessionReceiptTests"
Cohesion: 0.26
Nodes (4): LastSessionReceiptTests, Calendar, Date, Int

### Community 49 - "SessionDetailTests"
Cohesion: 0.38
Nodes (4): SessionDetailTests, Calendar, Date, Int

### Community 50 - "SettingsView"
Cohesion: 0.24
Nodes (9): App, Scene, TimexApp, .body, SettingsView, .body, .divider, Double (+1 more)

### Community 51 - "InstalledApp"
Cohesion: 0.07
Nodes (29): Hashable, Identifiable, AppCatalog, Entry, .id, Group, .id, String (+21 more)

### Community 52 - "IdleWarningController"
Cohesion: 0.22
Nodes (8): IdleWarningController, IdleWarningView, .body, Bool, NSPanel, String, TimeInterval, Void

### Community 53 - "ProjectSheet"
Cohesion: 0.18
Nodes (9): .defaultHourlyRate, Double, ProjectSheet, .body, .isDuplicate, Bool, Set, String (+1 more)

### Community 54 - ".label"
Cohesion: 0.31
Nodes (4): PillAccessibilityTests, Bool, String, TimeInterval

### Community 55 - "TimerView"
Cohesion: 0.13
Nodes (15): ButtonStyle, Configuration, MainWindowView, .body, MainTab, stats, timer, SegmentedTabs (+7 more)

### Community 56 - "README.md"
Cohesion: 0.20
Nodes (9): Billing, Building from source, FAQ, How Cutaway thinks, Install, License, Privacy, What it looks like (+1 more)

### Community 57 - "SwiftUI"
Cohesion: 0.13
Nodes (5): AppKit, Combine, Observation, ServiceManagement, SwiftUI

### Community 58 - "SpokenContentTests"
Cohesion: 0.24
Nodes (4): SpokenContentTests, Calendar, Date, Int

### Community 59 - "Accessibility — what has to be checked by hand"
Cohesion: 0.29
Nodes (6): 1. Keyboard, end to end, 2. Light appearance, 3. Colour vision, 4. Increase Contrast and Reduce Transparency, 5. VoiceOver spot check, Accessibility — what has to be checked by hand

### Community 61 - "AnchorSetTests"
Cohesion: 0.13
Nodes (8): .globalWorkApps, AnchorSet, String, AppListEditor, .body, String, Void, AnchorSetTests

### Community 62 - "TimexCurrency"
Cohesion: 0.13
Nodes (15): CaseIterable, Int, TimexCurrency, chf, cop, .decimals, eur, .groupingSeparator (+7 more)

### Community 63 - "SessionAccumulator"
Cohesion: 0.30
Nodes (4): SessionAccumulator, Date, BridgeCreditTests, SessionAccumulatorTests

### Community 64 - "FakeProbes"
Cohesion: 0.38
Nodes (3): FakeProbes, String, TimeInterval

### Community 65 - "Cutaway — Improvement Loop Backlog"
Cohesion: 0.33
Nodes (5): Cutaway — Improvement Loop Backlog, Done, Later (post-deadline polish), Open, Production push — deadline 06:00 today

### Community 66 - "smoke.sh"
Cohesion: 0.70
Nodes (4): assert(), q(), run_scenario(), smoke.sh script

### Community 67 - ".render"
Cohesion: 0.50
Nodes (3): PillRenderTests, String, URL

### Community 68 - "MenuBarKeyboardTests"
Cohesion: 0.23
Nodes (3): AccessibilityAuditTests, MenuBarKeyboardTests, XCUIApplication

### Community 72 - "SessionRecord"
Cohesion: 0.26
Nodes (7): SessionRecord, Calendar, DaySplitterTests, .cal, Calendar, Date, Int

### Community 73 - "FakeProbes"
Cohesion: 0.24
Nodes (6): EngineTickFanoutTests, FakeProbes, StatusItemTimerTests, .source, String, TimeInterval

### Community 74 - "CoreGraphics"
Cohesion: 0.22
Nodes (7): CoreGraphics, c(), CGColor, CGFloat, color(), CGColor, CGFloat

### Community 75 - "PauseReason"
Cohesion: 0.29
Nodes (7): Codable, PauseReason, inputIdle, manual, noProject, notFrontmost, systemSleep

### Community 76 - "Double"
Cohesion: 0.23
Nodes (4): Double, String, CurrencyFormatterTests, CurrencyLocaleInvarianceTests

### Community 77 - "RingView"
Cohesion: 0.19
Nodes (10): RingView, .body, .elapsedText, .goalLine, .ringColor, Bool, Color, Double (+2 more)

### Community 78 - "AppIconView"
Cohesion: 0.20
Nodes (7): NSImage, AppIcon, AppIconView, .body, CGFloat, String, AppIconTests

### Community 80 - "Global Constraints"
Cohesion: 0.20
Nodes (9): Global Constraints, Plan 2 — Per-project apps Implementation Plan, Task 1: `AnchorSet.resolve` and `Project.appBundleIDs`, Task 2: The engine honours a narrowed list; AppModel pushes it, Task 3: `AppCatalog` and `InstalledApps`, Task 4: `AppIcon` — the real icon, or an honest placeholder, Task 5: `AppPickerView` in the project sheet, pre-ticked, Task 6: Icons on the project — panel row and Stats header (+1 more)

### Community 82 - "ReclaimView"
Cohesion: 0.38
Nodes (5): ReclaimView, .body, String, TimeInterval, Void

### Community 83 - ".restoredStart"
Cohesion: 0.47
Nodes (3): PauseState, Date, UserDefaults

### Community 84 - "DesignTokenGuardTests"
Cohesion: 0.33
Nodes (3): DesignTokenGuardTests, .uiSources, URL

## Knowledge Gaps
- **228 isolated node(s):** `.accessibilityOfferDismissed`, `.dailyGoalHours`, `.goalProgress`, `.isPausedVisual`, `.shouldOfferAccessibility` (+223 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 429 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppModel` connect `AppModel` to `BillingEngine`, `DT`, `AccessibilityOfferTests`, `DetectionFollower`, `String`, `InvoicePeriodTests`, `DetectionEngine`, `View`, `.record`, `SwitcherList`, `SessionStore`, `PillBody`, `AppDelegate`, `Foundation`, `MoneyDefaultsTests`, `.project`, `EditDaySheet`, `.init`, `Project`, `StatusItemController`, `SettingsView`, `InstalledApp`, `IdleWarningController`, `ProjectSheet`, `TimerView`, `SwiftUI`, `.earnings`, `AnchorSetTests`, `TimexCurrency`, `SessionRecord`?**
  _High betweenness centrality (0.203) - this node is a cross-community bridge._
- **Why does `DetectionEngine` connect `DetectionEngine` to `AppModel`, `RecordingSource`, `EngineClockTests`, `SessionLogger`, `ReclaimOfferTests`, `.tick`, `IdleWarningTests`, `RenderExemptionTests`, `FullScreenSuppressionTests`, `SystemProbing`, `.togglePause`, `PausePersistenceTests`, `Project`, `SwiftUI`, `TimexCurrency`, `SessionAccumulator`, `FakeProbes`, `SessionRecord`, `FakeProbes`?**
  _High betweenness centrality (0.114) - this node is a cross-community bridge._
- **Why does `Project` connect `Project` to `DT`, `AppModel`, `.project`, `EditDaySheet`, `String`, `View`, `LastSessionReceiptTests`, `SessionDetailTests`, `ProjectSheet`, `.update`, `.record`, `SwitcherList`, `SessionStore`, `TimexCurrency`?**
  _High betweenness centrality (0.057) - this node is a cross-community bridge._
- **Are the 18 inferred relationships involving `AppModel` (e.g. with `DetectionFollower` and `ManualIntent`) actually correct?**
  _`AppModel` has 18 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `DetectionEngine` (e.g. with `SessionAccumulator` and `.testAnExcelOnlyListRecordsInExcelAndNotInResolve()`) actually correct?**
  _`DetectionEngine` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Project` (e.g. with `.switchOrCreate()` and `.body`) actually correct?**
  _`Project` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.accessibilityOfferDismissed`, `.dailyGoalHours`, `.goalProgress` to the rest of the system?**
  _228 weakly-connected nodes found - possible documentation gaps or missing edges._
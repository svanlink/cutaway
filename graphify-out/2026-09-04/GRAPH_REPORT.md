# Graph Report - cutaway  (2026-09-04)

## Corpus Check
- 88 files · ~142,527 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1434 nodes · 3132 edges · 72 communities (68 shown, 3 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 330 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `c8b65fcf`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- TimexCurrency
- XCTest
- Cutaway Loop Journal
- DT
- XCTestCase
- RingView
- AppModel
- DetectionInput
- .export
- DetectionFollower
- String
- InvoicePeriodTests
- DetectionEngine
- EngineClockTests
- Project
- SessionLogger
- DetectionStateTests
- SessionStoreTests
- ReclaimOfferTests
- .tick
- Cutaway — final form: merge, per-project apps, reorganize
- SessionStore
- IdleWarningTests
- SessionRecord
- RenderExemptionTests
- BackupCostTests
- Components.swift
- DisasterRecoveryTests
- .survivors
- .createProject
- PillBody
- BackupWALTests
- ContrastTests
- FullScreenSuppressionTests
- Delegate
- .migrate
- SystemProbing
- MoneyDefaultsTests
- .project
- .togglePause
- EditDaySheet
- PausePersistenceTests
- .backUp
- ReclaimController
- RecordingSourceTests
- BillingMode
- Global Constraints
- StatusItemController
- LastSessionReceiptTests
- SessionDetailTests
- DeleteProjectSheet
- AppDelegate
- .init
- .update
- .label
- TimerView
- README.md
- ProjectSheet
- SpokenContentTests
- Accessibility — what has to be checked by hand
- ScenarioProbes
- AppListEditor
- IdleWarningView
- SettingsView
- FakeProbes
- Cutaway — Improvement Loop Backlog
- smoke.sh
- .render
- BankedFlashTests
- loop.sh
- release.sh

## God Nodes (most connected - your core abstractions)
1. `AppModel` - 94 edges
2. `Cutaway Loop Journal` - 68 edges
3. `DetectionEngine` - 63 edges
4. `Project` - 54 edges
5. `SessionStore` - 49 edges
6. `DetectionInput` - 42 edges
7. `XCTest` - 42 edges
8. `SessionRecord` - 40 edges
9. `Cutaway` - 40 edges
10. `TimexCurrency` - 27 edges

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

## Communities (72 total, 3 thin omitted)

### Community 0 - "TimexCurrency"
Cohesion: 0.05
Nodes (33): Equatable, Foundation, .todayMoney, BillingEngine, BudgetForecast, beyondHorizon, days, paceUnknown (+25 more)

### Community 1 - "XCTest"
Cohesion: 0.05
Nodes (16): AppKit, Carbon.HIToolbox, Combine, CoreGraphics, Cutaway, Observation, c(), CGColor (+8 more)

### Community 2 - "Cutaway Loop Journal"
Cohesion: 0.03
Nodes (68): 2026-07-19 ~01:50 — [stability] Rename/delete projects — KEPT (210003c), 2026-07-19 ~02:15 — [stability] Editable app lists — KEPT (d01dcc4), 2026-07-19 ~02:15 — [stability] Editable app lists — KEPT (d01dcc4), 2026-07-19 ~02:30 — [design] Settings grouped sections — KEPT (96571c6), 2026-07-19 ~02:30 — [design] Settings grouped sections — KEPT (96571c6), 2026-07-19 ~02:50 — loop upgraded to autoresearch mechanics, 2026-07-19 ~02:50 — loop upgraded to autoresearch mechanics, 2026-07-19 ~03:05 — [ship] R-INSTALL — KEPT (+60 more)

### Community 3 - "DT"
Cohesion: 0.06
Nodes (35): NSAppearance, DT, .systemPrefersIncreasedContrast, Bool, CGFloat, Color, Double, Int (+27 more)

### Community 4 - "XCTestCase"
Cohesion: 0.06
Nodes (22): SessionAccumulator, Date, DesignTokenGuardTests, .uiSources, URL, LongPauseHintTests, BridgeCreditTests, SessionAccumulatorTests (+14 more)

### Community 5 - "RingView"
Cohesion: 0.07
Nodes (22): AccessibilityOfferPolicy, Bool, String, TimeInterval, ZeroState, noProject, nothingTrackedYet, ZeroStatePolicy (+14 more)

### Community 6 - "AppModel"
Cohesion: 0.10
Nodes (21): AppModel, .accessibilityOfferDismissed, .dailyGoalHours, .goalProgress, .isPausedVisual, .lastSessionLine, .pillSeconds, .projects (+13 more)

### Community 7 - "DetectionInput"
Cohesion: 0.07
Nodes (30): Codable, EventHandlerRef, EventHotKeyRef, Sendable, DetectionInput, .frontmostIsAnchor, .frontmostIsSatellite, .isWorkContext (+22 more)

### Community 8 - ".export"
Cohesion: 0.11
Nodes (15): CSVExporter, Double, CSVExporterTests, .cal, .sampleDays, Calendar, Date, Int (+7 more)

### Community 9 - "DetectionFollower"
Cohesion: 0.13
Nodes (11): DetectionFollower, ManualIntent, PauseState, ProjectName, Bool, Date, String, UserDefaults (+3 more)

### Community 10 - "String"
Cohesion: 0.09
Nodes (17): ApplicationServices, .detectLine, .zeroState, DetectionTier, manual, scriptingAPI, windowTitle, ProjectDetector (+9 more)

### Community 11 - "InvoicePeriodTests"
Cohesion: 0.11
Nodes (17): InvoicePeriod, allTime, lastMonth, thisMonth, thisYear, Calendar, Date, CSVExportButton (+9 more)

### Community 12 - "DetectionEngine"
Cohesion: 0.10
Nodes (16): CaseIterable, DetectionEngine, .manuallyPaused, Bool, Date, Double, String, TimeInterval (+8 more)

### Community 13 - "EngineClockTests"
Cohesion: 0.10
Nodes (15): DaySplitter, Calendar, DaySplitterTests, .cal, Calendar, Date, Int, EngineClockTests (+7 more)

### Community 14 - "Project"
Cohesion: 0.20
Nodes (15): Identifiable, DayEditTarget, DayTotal, .effectiveRate, Project, Int, StatsView, .body (+7 more)

### Community 15 - "SessionLogger"
Cohesion: 0.11
Nodes (13): os, SessionLogger, .logPath, Bool, Int, String, URL, SessionLoggerTests (+5 more)

### Community 16 - "DetectionStateTests"
Cohesion: 0.21
Nodes (4): DetectionStateTests, Bool, String, TimeInterval

### Community 17 - "SessionStoreTests"
Cohesion: 0.13
Nodes (7): SessionStoreTests, StoreBackupTests, Calendar, Date, Int, TimeInterval, URL

### Community 18 - "ReclaimOfferTests"
Cohesion: 0.21
Nodes (5): FakeProbes, ReclaimOfferTests, Date, String, TimeInterval

### Community 19 - ".tick"
Cohesion: 0.29
Nodes (4): DetectionEngineTests, Date, Int, UserDefaults

### Community 20 - "Cutaway — final form: merge, per-project apps, reorganize"
Cohesion: 0.10
Nodes (20): Catalog (`AppCatalog.swift`, pure data), Cutaway — final form: merge, per-project apps, reorganize, Icons, Interruptions, Look, Migration, Order and gates, Out of scope (+12 more)

### Community 21 - "SessionStore"
Cohesion: 0.12
Nodes (11): ModelContainer, ModelContext, SessionStore, .context, Bool, Date, PersistentIdentifier, String (+3 more)

### Community 22 - "IdleWarningTests"
Cohesion: 0.18
Nodes (5): FakeProbes, IdleWarningTests, Date, String, TimeInterval

### Community 23 - "SessionRecord"
Cohesion: 0.31
Nodes (4): SessionRecord, Calendar, DayEditTests, Calendar

### Community 24 - "RenderExemptionTests"
Cohesion: 0.18
Nodes (7): FakeProbes, RenderExemptionTests, Date, Double, String, TimeInterval, UInt64

### Community 25 - "BackupCostTests"
Cohesion: 0.18
Nodes (9): BackupCostTests, .fm, Date, FileManager, Int, String, TimeInterval, URL (+1 more)

### Community 26 - "Components.swift"
Cohesion: 0.16
Nodes (17): MainTab, stats, timer, ModeTag, .body, ProjectPill, .body, SegmentedTabs (+9 more)

### Community 27 - "DisasterRecoveryTests"
Cohesion: 0.18
Nodes (9): DisasterRecoveryTests, .fm, Calendar, Date, Double, FileManager, Int, TimeInterval (+1 more)

### Community 28 - ".survivors"
Cohesion: 0.24
Nodes (8): Set, Date, BackupRotationTests, .cal, Calendar, Date, Int, String

### Community 29 - ".createProject"
Cohesion: 0.23
Nodes (6): Double, RateHistoryTests, Calendar, Date, Double, Int

### Community 30 - "PillBody"
Cohesion: 0.21
Nodes (14): PillBody, .body, .miniRing, PillView, .accent, .body, .goalReached, .isRecording (+6 more)

### Community 31 - "BackupWALTests"
Cohesion: 0.21
Nodes (7): BackupWALTests, .fm, Date, FileManager, String, TimeInterval, URL

### Community 32 - "ContrastTests"
Cohesion: 0.27
Nodes (3): ContrastTests, Color, Double

### Community 33 - "FullScreenSuppressionTests"
Cohesion: 0.19
Nodes (6): FakeProbes, FullScreenSuppressionTests, Bool, Date, String, TimeInterval

### Community 34 - "Delegate"
Cohesion: 0.17
Nodes (11): MainActor, Delegate, ResumeNotifier, Sendable, Void, UNNotification, UNNotificationPresentationOptions, UNNotificationResponse (+3 more)

### Community 35 - ".migrate"
Cohesion: 0.16
Nodes (10): PrefsMigration, ScenarioMode, .dataDir, .isActive, .scenarioPath, Any, Bool, String (+2 more)

### Community 36 - "SystemProbing"
Cohesion: 0.18
Nodes (7): Darwin, Bool, String, TimeInterval, UInt64, SystemProbes, SystemProbing

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

### Community 43 - "ReclaimController"
Cohesion: 0.22
Nodes (8): ReclaimController, ReclaimView, .body, Bool, NSPanel, String, TimeInterval, Void

### Community 44 - "RecordingSourceTests"
Cohesion: 0.23
Nodes (5): RecordingSourceTests, Bool, Date, String, TimeInterval

### Community 45 - "BillingMode"
Cohesion: 0.23
Nodes (9): BillingMode, budget, hourly, .mode, Bool, Date, Double, TimeInterval (+1 more)

### Community 46 - "Global Constraints"
Cohesion: 0.17
Nodes (11): Global Constraints, Plan 1 — Merge the worktree branch Implementation Plan, Task 1: Start the merge; resolve the two documentation conflicts, Task 2: DetectionEngine — both pause features, one engine, Task 3: ProjectSheet replaces NewProjectSheet + RenameProjectSheet, Task 4: StatsView — edit rows on top of session-detail rows, Task 5: Panel banner and pill hint, Task 6: Settings row "After a manual pause" (+3 more)

### Community 47 - "StatusItemController"
Cohesion: 0.24
Nodes (3): NSStatusItem, StatusItemController, Any

### Community 48 - "LastSessionReceiptTests"
Cohesion: 0.26
Nodes (4): LastSessionReceiptTests, Calendar, Date, Int

### Community 49 - "SessionDetailTests"
Cohesion: 0.38
Nodes (4): SessionDetailTests, Calendar, Date, Int

### Community 50 - "DeleteProjectSheet"
Cohesion: 0.18
Nodes (10): App, Scene, MainWindowView, TimexApp, .body, DeleteProjectSheet, .others, .sessionCount (+2 more)

### Community 51 - "AppDelegate"
Cohesion: 0.24
Nodes (7): Notification, NSApplication, NSApplicationDelegate, NSObject, AppDelegate, Bool, AppLifecycleTests

### Community 52 - ".init"
Cohesion: 0.29
Nodes (4): NSHostingView, IdleWarningController, Bool, NSPanel

### Community 53 - ".update"
Cohesion: 0.22
Nodes (4): .defaultHourlyRate, Double, .body, StupidProofTests

### Community 54 - ".label"
Cohesion: 0.27
Nodes (4): PillAccessibilityTests, Bool, String, TimeInterval

### Community 55 - "TimerView"
Cohesion: 0.22
Nodes (8): ButtonStyle, Configuration, .body, PauseButtonStyle, Bool, TimerView, .accessibilityOffer, .pauseButton

### Community 56 - "README.md"
Cohesion: 0.20
Nodes (9): Billing, Building from source, FAQ, How Cutaway thinks, Install, License, Privacy, What it looks like (+1 more)

### Community 57 - "ProjectSheet"
Cohesion: 0.46
Nodes (4): ProjectSheet, .body, Bool, String

### Community 58 - "SpokenContentTests"
Cohesion: 0.25
Nodes (4): SpokenContentTests, Calendar, Date, Int

### Community 59 - "Accessibility — what has to be checked by hand"
Cohesion: 0.29
Nodes (6): 1. Keyboard, end to end, 2. Light appearance, 3. Colour vision, 4. Increase Contrast and Reduce Transparency, 5. VoiceOver spot check, Accessibility — what has to be checked by hand

### Community 60 - "ScenarioProbes"
Cohesion: 0.43
Nodes (4): ScenarioDriver, ScenarioProbes, String, TimeInterval

### Community 61 - "AppListEditor"
Cohesion: 0.43
Nodes (4): AppListEditor, .body, String, Void

### Community 62 - "IdleWarningView"
Cohesion: 0.38
Nodes (5): IdleWarningView, .body, String, TimeInterval, Void

### Community 63 - "SettingsView"
Cohesion: 0.43
Nodes (5): SettingsView, .body, .divider, Double, String

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

## Knowledge Gaps
- **216 isolated node(s):** `.accessibilityOfferDismissed`, `.dailyGoalHours`, `.goalProgress`, `.isPausedVisual`, `.shouldOfferAccessibility` (+211 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 411 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppModel` connect `AppModel` to `TimexCurrency`, `XCTest`, `DT`, `RingView`, `DetectionFollower`, `String`, `InvoicePeriodTests`, `DetectionEngine`, `Project`, `SessionStore`, `Components.swift`, `PillBody`, `.migrate`, `MoneyDefaultsTests`, `.project`, `EditDaySheet`, `ReclaimController`, `StatusItemController`, `DeleteProjectSheet`, `AppDelegate`, `.init`, `.update`, `TimerView`, `ProjectSheet`, `SettingsView`?**
  _High betweenness centrality (0.213) - this node is a cross-community bridge._
- **Why does `DetectionEngine` connect `DetectionEngine` to `FakeProbes`, `XCTest`, `FullScreenSuppressionTests`, `XCTestCase`, `SystemProbing`, `AppModel`, `DetectionInput`, `.togglePause`, `PausePersistenceTests`, `EngineClockTests`, `SessionLogger`, `ReclaimOfferTests`, `.tick`, `IdleWarningTests`, `SessionRecord`, `RenderExemptionTests`?**
  _High betweenness centrality (0.144) - this node is a cross-community bridge._
- **Why does `Project` connect `Project` to `TimexCurrency`, `DT`, `AppModel`, `.project`, `EditDaySheet`, `String`, `BillingMode`, `LastSessionReceiptTests`, `SessionDetailTests`, `DeleteProjectSheet`, `.update`, `SessionStore`, `SessionRecord`, `ProjectSheet`, `Components.swift`, `.createProject`?**
  _High betweenness centrality (0.076) - this node is a cross-community bridge._
- **Are the 17 inferred relationships involving `AppModel` (e.g. with `DetectionFollower` and `ManualIntent`) actually correct?**
  _`AppModel` has 17 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `DetectionEngine` (e.g. with `SessionAccumulator` and `.testBridgeExpiryClosesSessionWithoutCrediting()`) actually correct?**
  _`DetectionEngine` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Project` (e.g. with `.switchOrCreate()` and `.body`) actually correct?**
  _`Project` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.accessibilityOfferDismissed`, `.dailyGoalHours`, `.goalProgress` to the rest of the system?**
  _216 weakly-connected nodes found - possible documentation gaps or missing edges._
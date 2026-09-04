# Graph Report - cutaway  (2026-09-04)

## Corpus Check
- 88 files · ~142,977 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1434 nodes · 3133 edges · 78 communities (73 shown, 4 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 331 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `3f051625`
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
- Project
- Global Constraints
- StatusItemController
- LastSessionReceiptTests
- SessionDetailTests
- DeleteProjectSheet
- AppDelegate
- IdleWarningController
- ProjectSheet
- .label
- TimerView
- README.md
- SwiftUI
- SpokenContentTests
- Accessibility — what has to be checked by hand
- ScenarioProbes
- AppListEditor
- Sendable
- SessionAccumulator
- FakeProbes
- Cutaway — Improvement Loop Backlog
- smoke.sh
- .render
- MenuBarKeyboardTests
- loop.sh
- release.sh
- .split
- FakeProbes
- CoreGraphics
- PauseReason
- Foundation
- DetectionEngine.swift

## God Nodes (most connected - your core abstractions)
1. `AppModel` - 95 edges
2. `Cutaway Loop Journal` - 69 edges
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

## Communities (78 total, 4 thin omitted)

### Community 0 - "TimexCurrency"
Cohesion: 0.05
Nodes (32): Equatable, .todayMoney, BillingEngine, BudgetForecast, beyondHorizon, days, paceUnknown, BudgetStatus (+24 more)

### Community 1 - "XCTest"
Cohesion: 0.11
Nodes (3): Cutaway, SwiftData, XCTest

### Community 2 - "Cutaway Loop Journal"
Cohesion: 0.03
Nodes (69): 2026-07-19 ~01:50 — [stability] Rename/delete projects — KEPT (210003c), 2026-07-19 ~02:15 — [stability] Editable app lists — KEPT (d01dcc4), 2026-07-19 ~02:15 — [stability] Editable app lists — KEPT (d01dcc4), 2026-07-19 ~02:30 — [design] Settings grouped sections — KEPT (96571c6), 2026-07-19 ~02:30 — [design] Settings grouped sections — KEPT (96571c6), 2026-07-19 ~02:50 — loop upgraded to autoresearch mechanics, 2026-07-19 ~02:50 — loop upgraded to autoresearch mechanics, 2026-07-19 ~03:05 — [ship] R-INSTALL — KEPT (+61 more)

### Community 3 - "DT"
Cohesion: 0.07
Nodes (34): NSAppearance, DT, .systemPrefersIncreasedContrast, Bool, CGFloat, Color, Double, Int (+26 more)

### Community 4 - "XCTestCase"
Cohesion: 0.12
Nodes (9): DesignTokenGuardTests, .uiSources, URL, LongPauseHintTests, DetectionWiringTests, .appModelSource, String, DemoSeedGuardTests (+1 more)

### Community 5 - "RingView"
Cohesion: 0.07
Nodes (22): AccessibilityOfferPolicy, Bool, String, TimeInterval, ZeroState, noProject, nothingTrackedYet, ZeroStatePolicy (+14 more)

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
Cohesion: 0.13
Nodes (11): DetectionFollower, ManualIntent, PauseState, ProjectName, Bool, Date, String, UserDefaults (+3 more)

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
Cohesion: 0.19
Nodes (14): Identifiable, DayEditTarget, DayTotal, .effectiveRate, Int, StatsView, .body, .project (+6 more)

### Community 15 - "SessionLogger"
Cohesion: 0.10
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
Cohesion: 0.21
Nodes (8): DetectionInput, .frontmostIsAnchor, .frontmostIsSatellite, .isWorkContext, DetectionEngineTests, Date, Int, UserDefaults

### Community 20 - "Cutaway — final form: merge, per-project apps, reorganize"
Cohesion: 0.10
Nodes (20): Catalog (`AppCatalog.swift`, pure data), Cutaway — final form: merge, per-project apps, reorganize, Icons, Interruptions, Look, Migration, Order and gates, Out of scope (+12 more)

### Community 21 - "SessionStore"
Cohesion: 0.11
Nodes (11): ModelContainer, ModelContext, .pillSeconds, SessionStore, .context, Bool, PersistentIdentifier, String (+3 more)

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
Cohesion: 0.13
Nodes (20): MainWindowView, .body, MainTab, stats, timer, ModeTag, .body, ProjectPill (+12 more)

### Community 27 - "DisasterRecoveryTests"
Cohesion: 0.18
Nodes (9): DisasterRecoveryTests, .fm, Calendar, Date, Double, FileManager, Int, TimeInterval (+1 more)

### Community 28 - ".survivors"
Cohesion: 0.24
Nodes (8): Set, Date, BackupRotationTests, .cal, Calendar, Date, Int, String

### Community 29 - ".createProject"
Cohesion: 0.28
Nodes (6): Double, RateHistoryTests, Calendar, Date, Double, Int

### Community 30 - "PillBody"
Cohesion: 0.14
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

### Community 34 - "Delegate"
Cohesion: 0.17
Nodes (11): MainActor, Delegate, ResumeNotifier, Sendable, Void, UNNotification, UNNotificationPresentationOptions, UNNotificationResponse (+3 more)

### Community 35 - ".migrate"
Cohesion: 0.17
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
Cohesion: 0.19
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

### Community 45 - "Project"
Cohesion: 0.22
Nodes (11): BillingMode, budget, hourly, Project, .mode, Bool, Date, Double (+3 more)

### Community 46 - "Global Constraints"
Cohesion: 0.17
Nodes (11): Global Constraints, Plan 1 — Merge the worktree branch Implementation Plan, Task 1: Start the merge; resolve the two documentation conflicts, Task 2: DetectionEngine — both pause features, one engine, Task 3: ProjectSheet replaces NewProjectSheet + RenameProjectSheet, Task 4: StatsView — edit rows on top of session-detail rows, Task 5: Panel banner and pill hint, Task 6: Settings row "After a manual pause" (+3 more)

### Community 47 - "StatusItemController"
Cohesion: 0.19
Nodes (4): NSHostingView, NSStatusItem, StatusItemController, Any

### Community 48 - "LastSessionReceiptTests"
Cohesion: 0.26
Nodes (4): LastSessionReceiptTests, Calendar, Date, Int

### Community 49 - "SessionDetailTests"
Cohesion: 0.30
Nodes (5): Date, SessionDetailTests, Calendar, Date, Int

### Community 50 - "DeleteProjectSheet"
Cohesion: 0.14
Nodes (14): App, Scene, TimexApp, .body, DeleteProjectSheet, .others, .sessionCount, Int (+6 more)

### Community 51 - "AppDelegate"
Cohesion: 0.24
Nodes (7): Notification, NSApplication, NSApplicationDelegate, NSObject, AppDelegate, Bool, AppLifecycleTests

### Community 52 - "IdleWarningController"
Cohesion: 0.22
Nodes (8): IdleWarningController, IdleWarningView, .body, Bool, NSPanel, String, TimeInterval, Void

### Community 53 - "ProjectSheet"
Cohesion: 0.18
Nodes (8): .defaultHourlyRate, Double, ProjectSheet, .body, .isDuplicate, Bool, String, StupidProofTests

### Community 54 - ".label"
Cohesion: 0.31
Nodes (4): PillAccessibilityTests, Bool, String, TimeInterval

### Community 55 - "TimerView"
Cohesion: 0.25
Nodes (7): ButtonStyle, Configuration, PauseButtonStyle, Bool, TimerView, .accessibilityOffer, .pauseButton

### Community 56 - "README.md"
Cohesion: 0.20
Nodes (9): Billing, Building from source, FAQ, How Cutaway thinks, Install, License, Privacy, What it looks like (+1 more)

### Community 57 - "SwiftUI"
Cohesion: 0.18
Nodes (3): AppKit, ServiceManagement, SwiftUI

### Community 58 - "SpokenContentTests"
Cohesion: 0.25
Nodes (4): SpokenContentTests, Calendar, Date, Int

### Community 59 - "Accessibility — what has to be checked by hand"
Cohesion: 0.29
Nodes (6): 1. Keyboard, end to end, 2. Light appearance, 3. Colour vision, 4. Increase Contrast and Reduce Transparency, 5. VoiceOver spot check, Accessibility — what has to be checked by hand

### Community 60 - "ScenarioProbes"
Cohesion: 0.53
Nodes (4): ScenarioDriver, ScenarioProbes, String, TimeInterval

### Community 61 - "AppListEditor"
Cohesion: 0.43
Nodes (4): AppListEditor, .body, String, Void

### Community 62 - "Sendable"
Cohesion: 0.14
Nodes (12): Carbon.HIToolbox, CaseIterable, EventHandlerRef, EventHotKeyRef, Sendable, AutoResumeMode, ask, auto (+4 more)

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

### Community 72 - ".split"
Cohesion: 0.27
Nodes (6): Calendar, DaySplitterTests, .cal, Calendar, Date, Int

### Community 73 - "FakeProbes"
Cohesion: 0.24
Nodes (6): EngineTickFanoutTests, FakeProbes, StatusItemTimerTests, .source, String, TimeInterval

### Community 74 - "CoreGraphics"
Cohesion: 0.22
Nodes (7): CoreGraphics, c(), CGColor, CGFloat, color(), CGColor, CGFloat

### Community 75 - "PauseReason"
Cohesion: 0.29
Nodes (7): Codable, PauseReason, inputIdle, manual, noProject, notFrontmost, systemSleep

## Knowledge Gaps
- **217 isolated node(s):** `.accessibilityOfferDismissed`, `.dailyGoalHours`, `.goalProgress`, `.isPausedVisual`, `.shouldOfferAccessibility` (+212 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 411 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppModel` connect `AppModel` to `TimexCurrency`, `DT`, `RingView`, `DetectionFollower`, `String`, `InvoicePeriodTests`, `DetectionEngine`, `View`, `SessionStore`, `Components.swift`, `PillBody`, `MoneyDefaultsTests`, `.project`, `EditDaySheet`, `ReclaimController`, `Project`, `StatusItemController`, `DeleteProjectSheet`, `AppDelegate`, `IdleWarningController`, `ProjectSheet`, `TimerView`, `Foundation`?**
  _High betweenness centrality (0.211) - this node is a cross-community bridge._
- **Why does `DetectionEngine` connect `DetectionEngine` to `FakeProbes`, `FullScreenSuppressionTests`, `SystemProbing`, `AppModel`, `.togglePause`, `RecordingSource`, `PausePersistenceTests`, `FakeProbes`, `DetectionEngine.swift`, `EngineClockTests`, `SessionLogger`, `ReclaimOfferTests`, `.tick`, `IdleWarningTests`, `SessionRecord`, `RenderExemptionTests`, `Sendable`, `SessionAccumulator`?**
  _High betweenness centrality (0.143) - this node is a cross-community bridge._
- **Why does `Project` connect `Project` to `TimexCurrency`, `DT`, `AppModel`, `.project`, `EditDaySheet`, `String`, `View`, `LastSessionReceiptTests`, `SessionDetailTests`, `DeleteProjectSheet`, `ProjectSheet`, `SessionStore`, `SessionRecord`, `Components.swift`, `.createProject`?**
  _High betweenness centrality (0.077) - this node is a cross-community bridge._
- **Are the 18 inferred relationships involving `AppModel` (e.g. with `DetectionFollower` and `ManualIntent`) actually correct?**
  _`AppModel` has 18 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `DetectionEngine` (e.g. with `SessionAccumulator` and `.testBridgeExpiryClosesSessionWithoutCrediting()`) actually correct?**
  _`DetectionEngine` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Project` (e.g. with `.switchOrCreate()` and `.body`) actually correct?**
  _`Project` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.accessibilityOfferDismissed`, `.dailyGoalHours`, `.goalProgress` to the rest of the system?**
  _217 weakly-connected nodes found - possible documentation gaps or missing edges._
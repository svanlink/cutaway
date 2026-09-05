# Graph Report - cutaway  (2026-09-05)

## Corpus Check
- 102 files · ~157,275 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1510 nodes · 3243 edges · 89 communities (81 shown, 7 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 342 edges (avg confidence: 0.82)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `b7078bd4`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Equatable
- XCTest
- Cutaway Loop Journal
- DT
- AccessibilityOfferTests
- AppModel
- .export
- PillBody
- EngineClockTests
- ProjectsModel
- String
- InvoicePeriodTests
- DetectionEngine
- View
- .tick
- DetectionStateTests
- SessionStoreTests
- SessionRecord
- MenuBarPanel
- IdleWarningTests
- Cutaway — final form: merge, per-project apps, reorganize
- RenderExemptionTests
- ProjectSheet
- .backUp
- .survivors
- BackupCostTests
- DisasterRecoveryTests
- Project
- AppPickerModel
- SessionStore
- ContrastTests
- FullScreenSuppressionTests
- .migrate
- SessionAccumulator
- GlobalHotKey
- DeleteProjectSheet
- .createProject
- Foundation
- AppListEditor
- .earnings
- .project
- .format
- MoneyDefaultsTests
- PromptPanel
- AutoResumeTests
- RecordingSourceTests
- Global Constraints
- StatusItemController
- PausePersistenceTests
- SystemProbing
- Global Constraints
- Sendable
- DetectionState
- AppIconView
- EditDaySheet
- PromptCard
- README.md
- SwiftUI
- SwitcherList
- Accessibility — what has to be checked by hand
- .forecast
- SessionLogger
- LastSessionReceiptTests
- SessionDetailTests
- FakeProbes
- Cutaway — Improvement Loop Backlog
- smoke.sh
- BillingCurrency
- MenuBarKeyboardTests
- loop.sh
- release.sh
- AppDelegate
- XCTestCase
- SystemProbes.swift
- StoreBackup
- PanelBlock
- InstalledApp
- .image
- .visible
- Global Constraints
- RecordingSource
- IdleWarningView
- AppCatalogTests
- SpokenContentTests
- Global Constraints
- ScenarioProbes
- FakeProbes
- .restoredStart

## God Nodes (most connected - your core abstractions)
1. `AppModel` - 87 edges
2. `Cutaway Loop Journal` - 72 edges
3. `DetectionEngine` - 61 edges
4. `Project` - 60 edges
5. `SessionStore` - 52 edges
6. `XCTest` - 48 edges
7. `Cutaway` - 46 edges
8. `DetectionInput` - 42 edges
9. `SessionRecord` - 40 edges
10. `ProjectsModel` - 31 edges

## Surprising Connections (you probably didn't know these)
- `.resolveIsUp` --references--> `DetectionInput`  [EXTRACTED]
  Tests/CutawayTests/Tier1LiveTests.swift → Sources/Cutaway/Detection/DetectionState.swift
- `.hero` --references--> `AppModel`  [INFERRED]
  Sources/Cutaway/MenuBar/MenuBarPanel.swift → Sources/Cutaway/App/AppModel.swift
- `.pauseButton` --references--> `AppModel`  [INFERRED]
  Sources/Cutaway/MenuBar/MenuBarPanel.swift → Sources/Cutaway/App/AppModel.swift
- `DetectionEngineTests` --references--> `DetectionEngine`  [EXTRACTED]
  Tests/CutawayTests/DetectionEngineTests.swift → Sources/Cutaway/Detection/DetectionEngine.swift
- `AutoResumeTests` --references--> `DetectionEngine`  [EXTRACTED]
  Tests/CutawayTests/EditAndAutoResumeTests.swift → Sources/Cutaway/Detection/DetectionEngine.swift

## Import Cycles
- None detected.

## Communities (89 total, 7 thin omitted)

### Community 0 - "Equatable"
Cohesion: 0.18
Nodes (13): Equatable, BillingEngine, BudgetForecast, beyondHorizon, days, paceUnknown, BudgetStatus, BudgetWarning (+5 more)

### Community 2 - "Cutaway Loop Journal"
Cohesion: 0.03
Nodes (72): 2026-07-19 ~01:50 — [stability] Rename/delete projects — KEPT (210003c), 2026-07-19 ~02:15 — [stability] Editable app lists — KEPT (d01dcc4), 2026-07-19 ~02:15 — [stability] Editable app lists — KEPT (d01dcc4), 2026-07-19 ~02:30 — [design] Settings grouped sections — KEPT (96571c6), 2026-07-19 ~02:30 — [design] Settings grouped sections — KEPT (96571c6), 2026-07-19 ~02:50 — loop upgraded to autoresearch mechanics, 2026-07-19 ~02:50 — loop upgraded to autoresearch mechanics, 2026-07-19 ~03:05 — [ship] R-INSTALL — KEPT (+64 more)

### Community 3 - "DT"
Cohesion: 0.12
Nodes (16): NSAppearance, DT, .systemPrefersIncreasedContrast, Bool, CGFloat, Color, Double, Int (+8 more)

### Community 4 - "AccessibilityOfferTests"
Cohesion: 0.08
Nodes (19): AccessibilityOfferPolicy, Bool, String, TimeInterval, ZeroState, noProject, nothingTrackedYet, ZeroStatePolicy (+11 more)

### Community 5 - "AppModel"
Cohesion: 0.10
Nodes (19): AppModel, .accessibilityOfferDismissed, .defaultCurrency, .defaultHourlyRate, .globalWorkApps, .lastSessionLine, .pillSeconds, .projects (+11 more)

### Community 6 - ".export"
Cohesion: 0.12
Nodes (14): CSVExporter, Double, CSVExporterTests, .cal, .sampleDays, Calendar, Date, Int (+6 more)

### Community 7 - "PillBody"
Cohesion: 0.09
Nodes (20): .heroLabel, PillBody, .body, .miniRing, PillView, .body, .isRecording, .stateColor (+12 more)

### Community 8 - "EngineClockTests"
Cohesion: 0.10
Nodes (15): DaySplitter, Calendar, DaySplitterTests, .cal, Calendar, Date, Int, EngineClockTests (+7 more)

### Community 9 - "ProjectsModel"
Cohesion: 0.07
Nodes (20): AnchorSet, String, DetectionFollower, ManualIntent, ProjectName, Bool, String, ProjectsModel (+12 more)

### Community 10 - "String"
Cohesion: 0.09
Nodes (17): ApplicationServices, .detectLine, .zeroState, DetectionTier, manual, scriptingAPI, windowTitle, ProjectDetector (+9 more)

### Community 11 - "InvoicePeriodTests"
Cohesion: 0.11
Nodes (18): CaseIterable, CSVExportButton, .body, InvoicePeriod, allTime, lastMonth, thisMonth, thisYear (+10 more)

### Community 12 - "DetectionEngine"
Cohesion: 0.15
Nodes (10): DetectionEngine, .manuallyPaused, Date, Double, String, TimeInterval, UInt64, UserDefaults (+2 more)

### Community 13 - "View"
Cohesion: 0.20
Nodes (13): DayEditTarget, DayTotal, .effectiveRate, Int, StatsView, .body, .project, Bool (+5 more)

### Community 14 - ".tick"
Cohesion: 0.23
Nodes (8): DetectionInput, .frontmostIsAnchor, .frontmostIsSatellite, .isWorkContext, DetectionEngineTests, Date, Int, UserDefaults

### Community 15 - "DetectionStateTests"
Cohesion: 0.20
Nodes (4): DetectionStateTests, Bool, String, TimeInterval

### Community 16 - "SessionStoreTests"
Cohesion: 0.13
Nodes (7): SessionStoreTests, StoreBackupTests, Calendar, Date, Int, TimeInterval, URL

### Community 17 - "SessionRecord"
Cohesion: 0.28
Nodes (5): SessionRecord, Calendar, TimeInterval, DayEditTests, Calendar

### Community 18 - "MenuBarPanel"
Cohesion: 0.14
Nodes (17): MenuBarPanel, .accent, .elapsedText, .footer, .hero, .heroRing, .isRecording, .pauseButton (+9 more)

### Community 19 - "IdleWarningTests"
Cohesion: 0.18
Nodes (5): FakeProbes, IdleWarningTests, Date, String, TimeInterval

### Community 20 - "Cutaway — final form: merge, per-project apps, reorganize"
Cohesion: 0.10
Nodes (20): Catalog (`AppCatalog.swift`, pure data), Cutaway — final form: merge, per-project apps, reorganize, Icons, Interruptions, Look, Migration, Order and gates, Out of scope (+12 more)

### Community 21 - "RenderExemptionTests"
Cohesion: 0.18
Nodes (7): FakeProbes, RenderExemptionTests, Date, Double, String, TimeInterval, UInt64

### Community 22 - "ProjectSheet"
Cohesion: 0.14
Nodes (10): Bool, Double, ProjectSheet, .body, .isDuplicate, Bool, Double, Set (+2 more)

### Community 23 - ".backUp"
Cohesion: 0.22
Nodes (7): BackupWALTests, .fm, Date, FileManager, String, TimeInterval, URL

### Community 24 - ".survivors"
Cohesion: 0.22
Nodes (9): Date, Set, String, BackupRotationTests, .cal, Calendar, Date, Int (+1 more)

### Community 25 - "BackupCostTests"
Cohesion: 0.18
Nodes (9): BackupCostTests, .fm, Date, FileManager, Int, String, TimeInterval, URL (+1 more)

### Community 26 - "DisasterRecoveryTests"
Cohesion: 0.18
Nodes (9): DisasterRecoveryTests, .fm, Calendar, Date, Double, FileManager, Int, TimeInterval (+1 more)

### Community 27 - "Project"
Cohesion: 0.22
Nodes (11): BillingMode, budget, hourly, Project, .mode, Bool, Date, Double (+3 more)

### Community 28 - "AppPickerModel"
Cohesion: 0.24
Nodes (8): AppPickerModel, .q, AppPickerView, .body, .model, Set, String, AppPickerTests

### Community 29 - "SessionStore"
Cohesion: 0.12
Nodes (10): ModelContainer, ModelContext, SessionStore, .context, Bool, Date, PersistentIdentifier, String (+2 more)

### Community 30 - "ContrastTests"
Cohesion: 0.27
Nodes (3): ContrastTests, Color, Double

### Community 31 - "FullScreenSuppressionTests"
Cohesion: 0.19
Nodes (6): FakeProbes, FullScreenSuppressionTests, Bool, Date, String, TimeInterval

### Community 32 - ".migrate"
Cohesion: 0.16
Nodes (10): PrefsMigration, ScenarioMode, .dataDir, .isActive, .scenarioPath, Any, Bool, String (+2 more)

### Community 33 - "SessionAccumulator"
Cohesion: 0.29
Nodes (5): SessionAccumulator, Date, TimeInterval, BridgeCreditTests, SessionAccumulatorTests

### Community 34 - "GlobalHotKey"
Cohesion: 0.18
Nodes (7): Carbon.HIToolbox, EventHandlerRef, EventHotKeyRef, Notification, GlobalHotKey, Void, UInt32

### Community 35 - "DeleteProjectSheet"
Cohesion: 0.17
Nodes (11): App, Scene, CutawayApp, .body, MainWindowView, .body, DeleteProjectSheet, .others (+3 more)

### Community 36 - ".createProject"
Cohesion: 0.25
Nodes (6): Double, RateHistoryTests, Calendar, Date, Double, Int

### Community 38 - "AppListEditor"
Cohesion: 0.17
Nodes (9): ServiceManagement, AppListEditor, .body, String, Void, SettingsView, .body, Double (+1 more)

### Community 40 - ".project"
Cohesion: 0.32
Nodes (6): .todaySeconds, Calendar, Date, Int, String, TodayCacheTests

### Community 41 - ".format"
Cohesion: 0.23
Nodes (4): Double, String, CurrencyFormatterTests, CurrencyLocaleInvarianceTests

### Community 42 - "MoneyDefaultsTests"
Cohesion: 0.17
Nodes (5): Locale, .defaultCurrency, MoneyDefaultsTests, Locale, String

### Community 43 - "PromptPanel"
Cohesion: 0.24
Nodes (8): AnyView, NSPanel, Prompt, idle, resume, PromptPanel, Bool, TimeInterval

### Community 44 - "AutoResumeTests"
Cohesion: 0.21
Nodes (5): AutoResumeTests, Date, Int, String, TimeInterval

### Community 45 - "RecordingSourceTests"
Cohesion: 0.22
Nodes (5): RecordingSourceTests, Bool, Date, String, TimeInterval

### Community 46 - "Global Constraints"
Cohesion: 0.17
Nodes (11): Global Constraints, Plan 1 — Merge the worktree branch Implementation Plan, Task 1: Start the merge; resolve the two documentation conflicts, Task 2: DetectionEngine — both pause features, one engine, Task 3: ProjectSheet replaces NewProjectSheet + RenameProjectSheet, Task 4: StatsView — edit rows on top of session-detail rows, Task 5: Panel banner and pill hint, Task 6: Settings row "After a manual pause" (+3 more)

### Community 47 - "StatusItemController"
Cohesion: 0.19
Nodes (4): NSHostingView, NSStatusItem, StatusItemController, Any

### Community 48 - "PausePersistenceTests"
Cohesion: 0.22
Nodes (6): FakeProbes, PausePersistenceTests, Date, String, TimeInterval, UserDefaults

### Community 49 - "SystemProbing"
Cohesion: 0.19
Nodes (7): Bool, Bool, String, TimeInterval, UInt64, SystemProbes, SystemProbing

### Community 50 - "Global Constraints"
Cohesion: 0.20
Nodes (9): Global Constraints, Plan 3 — UI: menu-bar-first, minimal Implementation Plan, Task 1: Remove the reclaim offer, Task 2: Remove the daily-goal ring, Task 3: Menu-bar-first — the Timer tab moves into the panel, Task 4: Two prompts, one card, one panel host, never both, Task 5: Settings on `Form`, Task 6: Sheets on `Form` (+1 more)

### Community 51 - "Sendable"
Cohesion: 0.36
Nodes (8): Hashable, Identifiable, Sendable, Entry, .id, Group, .id, String

### Community 52 - "DetectionState"
Cohesion: 0.15
Nodes (13): AutoResumeMode, ask, auto, off, DetectionState, paused, recording, PauseReason (+5 more)

### Community 53 - "AppIconView"
Cohesion: 0.18
Nodes (10): AppIconView, CGFloat, String, AppIconRow, .body, AppIconRowPolicy, CGFloat, Int (+2 more)

### Community 54 - "EditDaySheet"
Cohesion: 0.21
Nodes (11): EditDaySheet, .body, .dayLabel, .isAdding, .seconds, Field, amount, hours (+3 more)

### Community 55 - "PromptCard"
Cohesion: 0.25
Nodes (8): Actions, PromptCard, .body, ResumePromptView, .body, Color, String, Void

### Community 56 - "README.md"
Cohesion: 0.20
Nodes (9): Billing, Building from source, FAQ, How Cutaway thinks, Install, License, Privacy, What it looks like (+1 more)

### Community 57 - "SwiftUI"
Cohesion: 0.15
Nodes (4): AppKit, Combine, Observation, SwiftUI

### Community 58 - "SwitcherList"
Cohesion: 0.21
Nodes (10): ModeTag, .body, Bool, PersistentIdentifier, Void, SwitcherList, .body, SwitcherRow (+2 more)

### Community 59 - "Accessibility — what has to be checked by hand"
Cohesion: 0.29
Nodes (6): 1. Keyboard, end to end, 2. Light appearance, 3. Colour vision, 4. Increase Contrast and Reduce Transparency, 5. VoiceOver spot check, Accessibility — what has to be checked by hand

### Community 61 - "SessionLogger"
Cohesion: 0.11
Nodes (13): os, SessionLogger, .logPath, Bool, Int, String, URL, SessionLoggerTests (+5 more)

### Community 62 - "LastSessionReceiptTests"
Cohesion: 0.26
Nodes (4): LastSessionReceiptTests, Calendar, Date, Int

### Community 63 - "SessionDetailTests"
Cohesion: 0.38
Nodes (4): SessionDetailTests, Calendar, Date, Int

### Community 64 - "FakeProbes"
Cohesion: 0.24
Nodes (6): EngineTickFanoutTests, FakeProbes, StatusItemTimerTests, .source, String, TimeInterval

### Community 65 - "Cutaway — Improvement Loop Backlog"
Cohesion: 0.33
Nodes (5): Cutaway — Improvement Loop Backlog, Done, Later (post-deadline polish), Open, Production push — deadline 06:00 today

### Community 66 - "smoke.sh"
Cohesion: 0.60
Nodes (5): assert(), derived_app(), q(), run_scenario(), smoke.sh script

### Community 67 - "BillingCurrency"
Cohesion: 0.20
Nodes (10): BillingCurrency, chf, cop, .decimals, eur, .groupingSeparator, .symbol, usd (+2 more)

### Community 68 - "MenuBarKeyboardTests"
Cohesion: 0.23
Nodes (3): AccessibilityAuditTests, MenuBarKeyboardTests, XCUIApplication

### Community 72 - "AppDelegate"
Cohesion: 0.31
Nodes (6): NSApplication, NSApplicationDelegate, NSObject, AppDelegate, Bool, AppLifecycleTests

### Community 73 - "XCTestCase"
Cohesion: 0.14
Nodes (8): DesignTokenGuardTests, .uiSources, URL, LongPauseHintTests, DetectionWiringTests, .appModelSource, String, XCTestCase

### Community 74 - "SystemProbes.swift"
Cohesion: 0.17
Nodes (8): CoreGraphics, Darwin, c(), CGColor, CGFloat, color(), CGColor, CGFloat

### Community 75 - "StoreBackup"
Cohesion: 0.35
Nodes (6): Codable, FileFacts, StoreBackup, Bool, Int, URL

### Community 76 - "PanelBlock"
Cohesion: 0.22
Nodes (9): PanelBlock, accessibilityOffer, footer, hero, projects, receipt, researchWindow, resumeBanner (+1 more)

### Community 77 - "InstalledApp"
Cohesion: 0.39
Nodes (5): InstalledApp, .id, InstalledApps, String, URL

### Community 78 - ".image"
Cohesion: 0.33
Nodes (4): NSImage, AppIcon, .body, AppIconTests

### Community 79 - ".visible"
Cohesion: 0.43
Nodes (3): IdleWarning, PromptArbiter, PromptArbiterTests

### Community 80 - "Global Constraints"
Cohesion: 0.20
Nodes (9): Global Constraints, Plan 2 — Per-project apps Implementation Plan, Task 1: `AnchorSet.resolve` and `Project.appBundleIDs`, Task 2: The engine honours a narrowed list; AppModel pushes it, Task 3: `AppCatalog` and `InstalledApps`, Task 4: `AppIcon` — the real icon, or an honest placeholder, Task 5: `AppPickerView` in the project sheet, pre-ticked, Task 6: Icons on the project — panel row and Stats header (+1 more)

### Community 81 - "RecordingSource"
Cohesion: 0.25
Nodes (6): RecordingSource, anchor, .isTimeLimited, .label, satellite, Bool

### Community 82 - "IdleWarningView"
Cohesion: 0.32
Nodes (5): IdleWarningView, .body, String, TimeInterval, Void

### Community 84 - "SpokenContentTests"
Cohesion: 0.25
Nodes (4): SpokenContentTests, Calendar, Date, Int

### Community 85 - "Global Constraints"
Cohesion: 0.29
Nodes (6): Global Constraints, Plan 4 — Reorganize and finish the rename Implementation Plan, Task 1: Finish the rename, Task 2: Feature folders, Task 3: `ProjectsModel` — selection, creation, switching, editing, deletion, Task 4: Ledger, graph, push

### Community 86 - "ScenarioProbes"
Cohesion: 0.48
Nodes (4): ScenarioDriver, ScenarioProbes, String, TimeInterval

### Community 87 - "FakeProbes"
Cohesion: 0.38
Nodes (3): FakeProbes, String, TimeInterval

### Community 88 - ".restoredStart"
Cohesion: 0.47
Nodes (3): PauseState, Date, UserDefaults

## Knowledge Gaps
- **243 isolated node(s):** `.accessibilityOfferDismissed`, `.selectedProjectID`, `.selectedProject`, `.globalWorkApps`, `.defaultCurrency` (+238 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 437 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppModel` connect `AppModel` to `AccessibilityOfferTests`, `PillBody`, `ProjectsModel`, `String`, `InvoicePeriodTests`, `DetectionEngine`, `View`, `MenuBarPanel`, `ProjectSheet`, `Project`, `SessionStore`, `.migrate`, `GlobalHotKey`, `DeleteProjectSheet`, `Foundation`, `AppListEditor`, `.earnings`, `.project`, `PromptPanel`, `StatusItemController`, `EditDaySheet`, `SwitcherList`, `BillingCurrency`, `AppDelegate`, `InstalledApp`, `ScenarioProbes`?**
  _High betweenness centrality (0.166) - this node is a cross-community bridge._
- **Why does `DetectionEngine` connect `DetectionEngine` to `AppModel`, `EngineClockTests`, `ProjectsModel`, `.tick`, `SessionRecord`, `IdleWarningTests`, `RenderExemptionTests`, `FullScreenSuppressionTests`, `SessionAccumulator`, `AutoResumeTests`, `PausePersistenceTests`, `SystemProbing`, `DetectionState`, `SwiftUI`, `SessionLogger`, `FakeProbes`, `.visible`, `RecordingSource`, `FakeProbes`?**
  _High betweenness centrality (0.094) - this node is a cross-community bridge._
- **Why does `SessionStore` connect `SessionStore` to `.createProject`, `Foundation`, `AppModel`, `.project`, `ProjectsModel`, `SessionStoreTests`, `SessionRecord`, `SpokenContentTests`, `DisasterRecoveryTests`, `LastSessionReceiptTests`, `SessionDetailTests`?**
  _High betweenness centrality (0.070) - this node is a cross-community bridge._
- **Are the 16 inferred relationships involving `AppModel` (e.g. with `ProjectDetector` and `.applicationDidFinishLaunching()`) actually correct?**
  _`AppModel` has 16 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `DetectionEngine` (e.g. with `SessionAccumulator` and `.testAnExcelOnlyListRecordsInExcelAndNotInResolve()`) actually correct?**
  _`DetectionEngine` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `Project` (e.g. with `.seconds()` and `.todayMoney`) actually correct?**
  _`Project` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.accessibilityOfferDismissed`, `.selectedProjectID`, `.selectedProject` to the rest of the system?**
  _243 weakly-connected nodes found - possible documentation gaps or missing edges._
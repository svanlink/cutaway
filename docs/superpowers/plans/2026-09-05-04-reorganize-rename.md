# Plan 4 — Reorganize and finish the rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One name (Cutaway) for folder, project, targets and env vars; feature folders; `AppModel` split so project selection/creation/switching lives in `ProjectsModel`; tests untouched in intent, re-pointed where they read paths; then `main` fast-forwarded and pushed.

**Architecture:** Three mechanical commits (rename, move, split) each on a green tree, then ledger and push. Every move is `git mv`; every test that reads a source file by path gets the new path; the token/settings guards scan the whole source tree instead of one folder (stronger, and folder-independent).

**Tech Stack:** git, xcodegen, XCTest, `scripts/smoke.sh`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-04-final-form-design.md`, Part 3. One addition, journaled: the `TimexCurrency` type becomes `BillingCurrency` — the last "Timex" in code; its raw values ("CHF"…) are what is persisted, so nothing on disk changes.
- **Not renamed**: on-disk store files (`default.store`, `timex.store` in data dirs), the scenario `UserDefaults` suite `com.vaneickelen.cutaway.scenario`, every pref key.
- After the project rename, DerivedData gets a NEW `Cutaway-<hash>` dir; `scripts/smoke.sh`/`release.sh` must match `$ROOT/Cutaway.xcodeproj` and glob `Cutaway-*`. The old `Timex-*` dirs are the human's to delete.
- Gate per commit: `-only-testing:CutawayTests` green (count stays 324 unless stated), `./scripts/smoke.sh "" 3` → `RESULT: ALL PASS` printing today's app, `-only-testing:CutawayUITests` green. Output filter as in Plan 3.
- Push `main` at the end (approved: push, no tag, no release).

---

### Task 1: Finish the rename

**Files:** everything under `Sources/Timex`, `Tests/TimexTests`, `Tests/TimexUITests`, `project.yml`, `.gitignore`, `scripts/smoke.sh`, `scripts/release.sh`, `README.md`.

- [ ] **Step 1: Move the trees and the app file**

```bash
git mv Sources/Timex Sources/Cutaway
git mv Tests/TimexTests Tests/CutawayTests
git mv Tests/TimexUITests Tests/CutawayUITests
git mv Sources/Cutaway/TimexApp.swift Sources/Cutaway/CutawayApp.swift
```

- [ ] **Step 2: project.yml, .gitignore**

`project.yml`: `name: Cutaway`; sources `Sources/Cutaway`; info path `Sources/Cutaway/Info.plist`; targets `CutawayTests` (sources `Tests/CutawayTests`) and `CutawayUITests` (sources `Tests/CutawayUITests`); scheme test targets `CutawayTests`, `CutawayUITests`. `.gitignore`: `Cutaway.xcodeproj/` replaces `Timex.xcodeproj/`.

- [ ] **Step 3: Identifiers and env vars (mechanical, verified by grep)**

```bash
cd "/Users/vaneickelen/Downloads/App Development/cutaway"
LC_ALL=C sed -i '' -e 's/struct TimexApp: App/struct CutawayApp: App/' -e 's/TimexCurrency/BillingCurrency/g' -e 's/TIMEX_SCENARIO/CUTAWAY_SCENARIO/g' -e 's/TIMEX_DATA_DIR/CUTAWAY_DATA_DIR/g' -e 's/TIMEX_DEMO/CUTAWAY_DEMO/g' -e 's/TIMEX_SHOW/CUTAWAY_SHOW/g' -e 's#Sources/Timex/#Sources/Cutaway/#g' -e 's/Timex\.xcodeproj/Cutaway.xcodeproj/g' -e 's/DerivedData\/Timex-\*/DerivedData\/Cutaway-*/g' -e 's/older Timex-\* dir/older Timex-* DerivedData dir/' -e 's/-only-testing:TimexTests/-only-testing:CutawayTests/g' $(grep -rl "Timex\|TIMEX_" Sources Tests scripts README.md)
grep -rn "TIMEX_\|Timex\b" Sources Tests scripts README.md project.yml .gitignore | grep -v "timex\.store\|Timex-\* DerivedData"
```
Expected: the final grep prints nothing (the two allowed leftovers are the store file name and the historical comment about the stale dir). `AppModel.swift:379`'s comment "if Timex hasn't seen it before" reads "if Cutaway hasn't seen it before" after this — check it.

- [ ] **Step 4: Regenerate, gate, commit**

```bash
rm -rf Timex.xcodeproj && xcodegen generate && ls -d Cutaway.xcodeproj
```
Then the full gate with the NEW target names. The first build populates `DerivedData/Cutaway-<hash>`; smoke must print that path. Commit:

```
chore: finish the rename — Cutaway everywhere but the store file

Sources/Cutaway, Cutaway.xcodeproj, CutawayTests, CutawayUITests,
CutawayApp, BillingCurrency, CUTAWAY_* env vars. The on-disk store names
and the scenario defaults suite are untouched: renaming them would
strand data. Scripts resolve DerivedData by the new project path.
```

---

### Task 2: Feature folders

**Files:** `git mv` only, plus four tests that read paths.

- [ ] **Step 1: Move**

```bash
cd "/Users/vaneickelen/Downloads/App Development/cutaway/Sources/Cutaway"
mkdir -p App Projects Billing Stats MenuBar Settings Design
git mv CutawayApp.swift AppModel.swift Prefs.swift HotKey.swift Scenario/ScenarioDriver.swift Policy/UserFacingPolicy.swift App/
git mv Store/Models.swift Store/SessionStore.swift Store/DaySplitter.swift Store/StoreBackup.swift UI/ProjectSheet.swift UI/ProjectManageSheets.swift Projects/
git mv Billing/BillingEngine.swift Billing/ 2>/dev/null; git mv CSV/CSVExporter.swift UI/CSVExportButton.swift Billing/
git mv UI/StatsView.swift UI/EditDaySheet.swift Stats/
git mv UI/MenuBarPanel.swift UI/StatusItemController.swift UI/PromptPanel.swift UI/IdleWarningPanel.swift UI/PanelCards.swift MenuBar/
git mv UI/SettingsView.swift UI/AppListEditor.swift Settings/
git mv UI/DesignTokens.swift UI/Components.swift Design/
rmdir Store CSV UI Scenario Policy 2>/dev/null; ls
```
Expected `ls`: `App Billing Design Detection Info.plist MenuBar Projects Settings Stats` (Info.plist stays at the root of `Sources/Cutaway`; `project.yml` already points there).

- [ ] **Step 2: Tests that read paths**

- `DesignTokenGuardTests.uiSources` and `SystemSettingsTests.testTheAppStillReadsTheSystemSettings`: replace the single-folder listing with a recursive walk of `Sources/Cutaway` collecting every `.swift` file. Guard code:
```swift
    private var sources: [URL] {
        get throws {
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<3 { root.deleteLastPathComponent() }
            let base = root.appendingPathComponent("Sources/Cutaway")
            let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)!
            return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
    }
```
  The font-literal rule now applies to the WHOLE tree (it already held: no `.system(size:` outside DesignTokens anywhere). `testTheGuardIsActuallyLookingAtTheSources` keeps its `> 5` floor and the DesignTokens presence check.
- `StatusItemTimerTests.source`: path `Sources/Cutaway/MenuBar/StatusItemController.swift`.
- `DetectionWiringTests.appModelSource`: path `Sources/Cutaway/App/AppModel.swift` (Task 3 widens it).

- [ ] **Step 3: Gate and commit**

`xcodegen generate` (paths changed), full gate. Commit:

```
refactor: feature folders — App, Detection, Projects, Billing, Stats, MenuBar, Settings, Design

git mv only. The token and system-settings guards now walk the whole
tree instead of one UI folder — stronger, and indifferent to layout.
```

---

### Task 3: `ProjectsModel` — selection, creation, switching, editing, deletion

**Files:**
- Create: `Sources/Cutaway/Projects/ProjectsModel.swift`
- Modify: `Sources/Cutaway/App/AppModel.swift`, `Tests/CutawayTests/DetectionWiringTests.swift`

**Interfaces:**
- Produces: `@Observable @MainActor final class ProjectsModel` with `init(store: SessionStore, engine: DetectionEngine)`; `var selectedProjectID: PersistentIdentifier?`; `var selectedProject: Project?`; `var projects: [Project]`; `private(set) var intent: ManualIntent` (read by AppModel's Tier-1 loop); `func restoreSelection()`; `func autoDetected(_ name: String, canCreate: Bool) -> Bool` (returns whether attribution moved); `func selectManually(_:)`; `func select(_:)`; `func createProject(name:client:mode:rate:budget:currency:apps:isManual:)`; `func update(_:name:client:mode:rate:budget:currency:apps:)`; `func delete(_:reassignTo:)`; `func applyAnchors()`; `static var globalWorkApps: [String]`; `func seedDemoData()`.
- `AppModel` keeps: `engine`, `store`, `detector`, `let projects: ProjectsModel`, the init wiring (backup, store open, demo seed guard, crash recovery, the Tier-1/Tier-2 tick loop, notifications, scenario start), `installedApps`, live figures, banked flash, announcements, accessibility offer, zero state, day editing (`setDaySeconds`, `seconds(fromHoursText:)`, `hoursText`), `detectLine`, window callbacks, sheet targets. It FORWARDS the members every view uses so no view changes: `selectedProject`, `selectedProjectID`, `projects` (the array — rename the model property to `projectsModel` to avoid the clash), `selectManually`, `select`, `createProject`, `update`, `delete`, `applyAnchors`, `globalWorkApps`, `isDuplicateName`, `clampedRate`, `defaultCurrency`, `defaultHourlyRate`.

- [ ] **Step 1: Extract**

Move these AppModel members verbatim into `ProjectsModel` (order preserved): `selectedProjectID`, `follower`, `intent`, `isDuplicateName`, `clampedRate`, `defaultCurrency`, `defaultHourlyRate`, `globalWorkApps`, `applyAnchors`, `autoDetected` (now returns `Bool`: `selectedProjectID != before`), `update`, `delete`, `seedDemoData`, `cachedProject`/`selectedProject`, `cachedProjects`/`projects`, `invalidateProjectCache`, `switchOrCreate`, `selectManually`, `select`, `createProject`. Its `init(store:engine:)` stores both; `restoreSelection()` holds the "restore last selected project by name … engine.hasActiveProject … applyAnchors()" lines from AppModel.init.

`AppModel.init` becomes: backup → store → `projectsModel = ProjectsModel(store: store, engine: engine)` → demo seed (`projectsModel.seedDemoData()`) → `projectsModel.restoreSelection()` → onSessionClosed (uses `projectsModel.selectedProject`) → crash recovery → resume prompt hook → tick loop (`let startedAt = self.projectsModel.intent.token` … `self.projectsModel.intent.hasMovedSince(startedAt)` … `self.projectsModel.autoDetected(name, canCreate:)`; announce when it returns true) → notification observer → installed-apps scan → scenario/start. `scenarioDetect` calls `projectsModel.autoDetected`. Announcement of an auto-switch moves to AppModel: `if projectsModel.autoDetected(...) , let now = selectedProject?.name { announce(Self.switchAnnouncement(to: now)) }`.

Forwarders in AppModel (all one-liners):
```swift
    // MARK: - Projects (forwarded — the views were written against AppModel)
    var selectedProjectID: PersistentIdentifier? { projectsModel.selectedProjectID }
    var selectedProject: Project? { projectsModel.selectedProject }
    var projects: [Project] { projectsModel.projects }
    func selectManually(_ p: Project) { projectsModel.selectManually(p) }
    func select(_ p: Project) { projectsModel.select(p) }
    func createProject(name: String, client: String, mode: BillingMode, rate: Double, budget: Double,
                       currency: BillingCurrency, apps: [String], isManual: Bool = false) {
        projectsModel.createProject(name: name, client: client, mode: mode, rate: rate, budget: budget,
                                    currency: currency, apps: apps, isManual: isManual)
    }
    func update(_ p: Project, name: String, client: String, mode: BillingMode, rate: Double,
                budget: Double, currency: BillingCurrency, apps: [String]) {
        projectsModel.update(p, name: name, client: client, mode: mode, rate: rate, budget: budget,
                             currency: currency, apps: apps)
    }
    func delete(_ p: Project, reassignTo t: Project?) { projectsModel.delete(p, reassignTo: t) }
    func applyAnchors() { projectsModel.applyAnchors() }
    static var globalWorkApps: [String] { ProjectsModel.globalWorkApps }
    static var defaultCurrency: BillingCurrency { ProjectsModel.defaultCurrency }
    static var defaultHourlyRate: Double { ProjectsModel.defaultHourlyRate }
    nonisolated static func clampedRate(_ r: Double) -> Double { ProjectsModel.clampedRate(r) }
    nonisolated static func isDuplicateName(_ n: String, existing: [String]) -> Bool { ProjectsModel.isDuplicateName(n, existing: existing) }
```
`demoSeedAllowed` stays in AppModel (it is about the harness, not projects).

- [ ] **Step 2: The wiring test reads both files (deliberate)**

`DetectionWiringTests`: `appModelSource` becomes the concatenation of `Sources/Cutaway/App/AppModel.swift` and `Sources/Cutaway/Projects/ProjectsModel.swift`; the first assertion's needle becomes `"intent.token"` (the request still stamps the token before starting — the object it lives on moved). Doc comment: "reads the two files the detection path now spans".

- [ ] **Step 3: Gate and commit**

Full gate (324 tests; `ManualIntentTests`, `DetectionWiringTests`, `MoneyDefaultsTests` are the ones that would notice a slip). Commit:

```
refactor: ProjectsModel owns selection, creation, switching, editing, deletion

AppModel keeps detection wiring, live figures, announcements, the
sheets and the harness hooks, and forwards the project API the views
were written against. DetectionWiringTests reads both files now; the
intent token lives on ProjectsModel and is still stamped before every
Tier-1 request.
```

---

### Task 4: Ledger, graph, push

- [ ] **Step 1: README build lines** already renamed in Task 1 (`Cutaway.xcodeproj`). Verify: `grep -n "xcodeproj" README.md`.

- [ ] **Step 2: Journal, results, GOALS, graph**

Journal entry (newest): rename (what changed, what deliberately did not), folders, the split and the wiring-test re-point, the BillingCurrency addition, gate numbers, and the standing "owed" list (README screenshots; the human's first-run manual pass over the native Forms; stale `Timex-*` DerivedData dirs to delete). `LOOP_RESULTS.tsv` one row per commit. `GOALS.md` Done: `- [structure] Cutaway everywhere; feature folders; ProjectsModel split — <Task 3 hash>`.

```bash
graphify update . 2>&1 | grep -E "Rebuilt|updated"
git add LOOP_JOURNAL.md GOALS.md graphify-out && git commit -m "docs: ledger and graph for the reorganization

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

- [ ] **Step 3: Final gate on the finished tree, then push (approved)**

Full gate once more on HEAD. Then:
```bash
git branch -f main autoresearch/aug20 && git push origin main 2>&1 | tail -2 && git rev-list --left-right --count main...origin/main
```
Expected `0	0`. No tag; the human runs `scripts/release.sh 1.2.0` after a day of use (that script's first step is this same gate).

# Plan 2 — Per-project apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A project lists the apps it is worked in; while it is selected, only those apps are anchors. New projects start with the full default set pre-ticked, the picker shows the real installed icons, and the project's icons appear on its row in the panel and in the Stats header.

**Architecture:** `Project.appBundleIDs: [String]` (empty = global list). One pure function, `AnchorSet.resolve`, decides what the engine gets; `AppModel.applyAnchors()` is the only place that writes `engine.workAppPrefixes`. `AppCatalog` is static data (suites → bundle-id prefixes); `InstalledApps` scans `/Applications` once and resolves prefixes to installed bundles and icons. `AppPickerView` is a native `LazyVGrid` of toggle buttons inside the existing `ProjectSheet`.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData, AppKit (`NSWorkspace`, `Bundle`), XCTest.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-04-final-form-design.md`, Part 2.
- Gate: replace, not extend — a project's list REPLACES the global anchor list while selected; empty means "use the global list". Satellites, auto-switch, billing arithmetic untouched.
- Pre-tick: the create sheet starts with every entry of the current global anchor list ticked; auto-created Resolve projects get the global list as their `appBundleIDs`.
- Everything ticked is an anchor (decision Q2-A). No per-project satellites.
- Icons come from the installed app via `NSWorkspace.shared.icon(forFile:)`; nothing is bundled. Not installed → SF Symbol `app.dashed`, 50 % opacity, help "Not installed".
- Fonts are tokens (`DT.*`); `.system(size:)` fails `DesignTokenGuardTests`. Colours: `DT.signal`, `DT.onSignal`, `DT.text`, `DT.text2`, `DT.text3`, `DT.card2`, `DT.strokeSubtle`, `DT.rMd`, `DT.rSm`, `DT.s1`…`DT.s4`.
- `AppModel.init()` opens the REAL store unless `ScenarioMode.isActive`; never construct `AppModel` in a unit test. Test the pure function and the engine instead; test the store with `SessionStore(inMemory: true)`.
- Engine tests use `DetectionEngineTests.FakeProbes` (`frontmost`, `idle`) and a scratch `UserDefaults` suite.
- Gate per commit: unit suite green (`-only-testing:TimexTests`), `./scripts/smoke.sh "" 3` → `RESULT: ALL PASS`; a11y UI test for visual tasks. Filter xcodebuild output with `grep -E "^.*\.swift:[0-9]+:[0-9]+: error:|failed \(|Executed [0-9]+ tests|TEST (FAILED|SUCCEEDED)"` — plain `error:` also matches harmless "linkd" noise.
- After the plan: `graphify update .`, journal + results row + GOALS Done line. No push, no tag (main is pushed at the end of Plan 4).

---

### Task 1: `AnchorSet.resolve` and `Project.appBundleIDs`

**Files:**
- Create: `Sources/Timex/Detection/AnchorSet.swift`
- Modify: `Sources/Timex/Store/Models.swift` (Project)
- Test: `Tests/TimexTests/AnchorSetTests.swift` (new)

**Interfaces:**
- Produces: `enum AnchorSet { static func resolve(project: [String], global: [String]) -> [String] }`; `Project.appBundleIDs: [String]` (default `[]`); `Project.init(name:client:mode:hourlyRate:budget:currency:appBundleIDs:)` with `appBundleIDs: [String] = []`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import SwiftData
@testable import Cutaway

/// Which apps prove work for the SELECTED project. One pure function, so
/// the gate/replace decision has exactly one home.
final class AnchorSetTests: XCTestCase {

    func testEmptyProjectListMeansTheGlobalList() {
        XCTAssertEqual(AnchorSet.resolve(project: [], global: ["a", "b"]), ["a", "b"])
    }

    func testProjectListReplacesTheGlobalListVerbatim() {
        XCTAssertEqual(AnchorSet.resolve(project: ["com.microsoft.Excel"], global: ["a", "b"]),
                       ["com.microsoft.Excel"], "replace, not extend — that is the whole point")
    }

    func testProjectListIsSanitizedLikeTheSettingsEditor() {
        XCTAssertEqual(AnchorSet.resolve(project: [" com.adobe.Photoshop ", "", "COM.ADOBE.PHOTOSHOP"],
                                         global: ["a"]),
                       ["com.adobe.Photoshop"])
    }

    @MainActor
    func testProjectPersistsItsApps() throws {
        let store = try SessionStore(inMemory: true)
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly, hourlyRate: 85,
                                        currency: .chf, appBundleIDs: ["com.adobe.InDesign"])
        XCTAssertEqual(try store.projects()[0].appBundleIDs, ["com.adobe.InDesign"])
        let legacy = try store.createProject(name: "Old", client: "", mode: .hourly, hourlyRate: 85, currency: .chf)
        XCTAssertEqual(legacy.appBundleIDs, [], "a project created before the field existed reads as 'global'")
        _ = p
    }
}
```

- [ ] **Step 2: Run — expect compile failure**

Run: `xcodebuild -project Timex.xcodeproj -scheme Cutaway -destination 'platform=macOS' test -only-testing:TimexTests/AnchorSetTests 2>&1 | grep -E "^.*\.swift:[0-9]+:[0-9]+: error:|Executed" | head -5`
Expected: `error: cannot find 'AnchorSet' in scope`, `extra argument 'appBundleIDs'`.

- [ ] **Step 3: Implement**

`Sources/Timex/Detection/AnchorSet.swift`:
```swift
import Foundation

/// Which apps prove work for the selected project.
///
/// A project's own list REPLACES the global one while it is selected — a
/// colour pass in Resolve must not land on an InDesign-only job's invoice.
/// An empty list means "the global list": that is what every project
/// created before the field existed says, and it is the fallback.
enum AnchorSet {
    static func resolve(project: [String], global: [String]) -> [String] {
        let own = DetectionInput.sanitizedPrefixes(project)
        return own.isEmpty ? global : own
    }
}
```

`Sources/Timex/Store/Models.swift`, class `Project`: after `var createdAt: Date` add
```swift
    /// Bundle-id prefixes this project is worked in. Empty = use the global
    /// anchor list (legacy projects, and the fallback). See AnchorSet.
    var appBundleIDs: [String] = []
```
and change the init to
```swift
    init(name: String, client: String, mode: BillingMode, hourlyRate: Double,
         budget: Double = 0, currency: TimexCurrency, appBundleIDs: [String] = []) {
        self.name = name
        self.client = client
        self.modeRaw = mode.rawValue
        self.hourlyRate = hourlyRate
        self.budget = budget
        self.currencyRaw = currency.rawValue
        self.createdAt = Date()
        self.appBundleIDs = appBundleIDs
    }
```

`Sources/Timex/Store/SessionStore.swift`, `createProject`: add the parameter and pass it through:
```swift
    @discardableResult
    func createProject(name: String, client: String, mode: BillingMode,
                       hourlyRate: Double, budget: Double = 0,
                       currency: TimexCurrency, appBundleIDs: [String] = []) throws -> Project {
        let p = Project(name: name, client: client, mode: mode,
                        hourlyRate: hourlyRate, budget: budget, currency: currency,
                        appBundleIDs: appBundleIDs)
        context.insert(p)
        try context.save()
        return p
    }
```

- [ ] **Step 4: Run — expect pass**

Same command. Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Timex/Detection/AnchorSet.swift Sources/Timex/Store/Models.swift Sources/Timex/Store/SessionStore.swift Tests/TimexTests/AnchorSetTests.swift
git commit -m "feat: a project can name its apps; AnchorSet decides what the engine gets

Project.appBundleIDs (empty = global list). AnchorSet.resolve is the one
place the replace-not-extend rule lives.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: The engine honours a narrowed list; AppModel pushes it

**Files:**
- Modify: `Sources/Timex/AppModel.swift` (`applyAnchors`, `select`, `createProject`, `update`, `switchOrCreate`, `init`)
- Modify: `Sources/Timex/UI/SettingsView.swift` (work-app editor `onChange`)
- Test: `Tests/TimexTests/AnchorSetTests.swift` (engine case appended)

**Interfaces:**
- Consumes: `AnchorSet.resolve`, `DetectionEngine.workAppPrefixes`.
- Produces: `AppModel.applyAnchors()`; `AppModel.globalWorkApps: [String]` (static); `AppModel.createProject(name:client:mode:rate:budget:currency:apps:isManual:)` with `apps: [String]`; `AppModel.update(_:name:client:mode:rate:budget:currency:apps:)` with `apps: [String]`.

- [ ] **Step 1: Write the failing engine test**

Append inside `final class AnchorSetTests`:
```swift
    /// The engine does not know about projects; it bills whatever list it
    /// holds. This pins that a NARROWED list really stops Resolve counting.
    @MainActor
    func testAnExcelOnlyListRecordsInExcelAndNotInResolve() {
        let probes = DetectionEngineTests.FakeProbes()
        let scratch = UserDefaults(suiteName: "cutaway.tests.\(UUID().uuidString)")!
        let engine = DetectionEngine(probes: probes, defaults: scratch)
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { clock }
        engine.workAppPrefixes = AnchorSet.resolve(project: ["com.microsoft.Excel"],
                                                   global: DetectionInput.defaultWorkAppPrefixes)

        probes.frontmost = DetectionInput.resolveBundleIDs[0]
        for _ in 0..<5 { clock = clock.addingTimeInterval(1); engine.tick() }
        XCTAssertEqual(engine.state, .paused(.notFrontmost), "Resolve is not this project's app")
        XCTAssertEqual(engine.accumulator.activeSeconds, 0)

        probes.frontmost = "com.microsoft.Excel"
        for _ in 0..<5 { clock = clock.addingTimeInterval(1); engine.tick() }
        XCTAssertEqual(engine.state, .recording)
        XCTAssertGreaterThan(engine.accumulator.activeSeconds, 3)

        // Back to "global" — the fallback restores Resolve as an anchor.
        engine.workAppPrefixes = AnchorSet.resolve(project: [], global: DetectionInput.defaultWorkAppPrefixes)
        probes.frontmost = DetectionInput.resolveBundleIDs[0]
        for _ in 0..<3 { clock = clock.addingTimeInterval(1); engine.tick() }
        XCTAssertEqual(engine.state, .recording)
    }
```

- [ ] **Step 2: Run — expect pass already** (this pins existing engine behaviour; it must be green before the wiring changes so a later red is the wiring's fault)

Run: `xcodebuild ... -only-testing:TimexTests/AnchorSetTests ...`
Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 3: Wire AppModel**

In `Sources/Timex/AppModel.swift`:

After `static var defaultHourlyRate: Double { ... }` add:
```swift
    /// The Settings list — what a project with no list of its own uses, and
    /// what a new project starts with pre-ticked.
    static var globalWorkApps: [String] {
        Prefs.stringArray(forKey: "workApps") ?? DetectionInput.defaultWorkAppPrefixes
    }

    /// The ONLY writer of engine.workAppPrefixes. Called on launch, on every
    /// selection change, after a project edit, and after the Settings list
    /// changes — so a project-specific list is never overwritten by editing
    /// the global one, and a global edit still reaches projects that rely on it.
    func applyAnchors() {
        engine.workAppPrefixes = AnchorSet.resolve(project: selectedProject?.appBundleIDs ?? [],
                                                   global: Self.globalWorkApps)
    }
```

In `init()`, directly after `engine.hasActiveProject = selectedProjectID != nil` (the first occurrence, before `ResumeNotifier.install`), add:
```swift
        applyAnchors()
```

In `select(_:)`, after `Prefs.set(project.name, forKey: "selectedProjectName")` add:
```swift
        applyAnchors()
```

Change `createProject` to:
```swift
    func createProject(name: String, client: String, mode: BillingMode,
                       rate: Double, budget: Double, currency: TimexCurrency,
                       apps: [String], isManual: Bool = false) {
        guard let p = try? store.createProject(name: name, client: client, mode: mode,
                                               hourlyRate: rate, budget: budget, currency: currency,
                                               appBundleIDs: DetectionInput.sanitizedPrefixes(apps)) else { return }
        invalidateProjectCache()
        // Auto-creation routes here too, so only stamp intent when a human
        // filled in the sheet — `switchOrCreate` calls this as well.
        if isManual { intent.userChose() }
        select(p)
        engine.hasActiveProject = true
    }
```

In `switchOrCreate`, the auto-create call becomes:
```swift
        createProject(name: name, client: "", mode: .hourly,
                      rate: Self.defaultHourlyRate, budget: 0, currency: Self.defaultCurrency,
                      apps: Self.globalWorkApps)
```

Change `update` to take `apps:` and re-apply:
```swift
    func update(_ project: Project, name newName: String, client: String, mode: BillingMode,
                rate: Double, budget: Double, currency: TimexCurrency, apps: [String]) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        try? store.update(project) {
            $0.name = name
            $0.client = client.trimmingCharacters(in: .whitespaces)
            $0.mode = mode
            $0.hourlyRate = Self.clampedRate(rate)
            $0.budget = max(0, budget)
            $0.currency = currency
            $0.appBundleIDs = DetectionInput.sanitizedPrefixes(apps)
        }
        if project.persistentModelID == selectedProjectID {
            Prefs.set(name, forKey: "selectedProjectName")
        }
        invalidateProjectCache()
        applyAnchors()
    }
```

`seedDemoData()` calls `store.createProject` (not the model's) — unchanged.

- [ ] **Step 4: Settings pushes through the model, not straight into the engine**

In `Sources/Timex/UI/SettingsView.swift`, the Workflow apps editor's closure `{ model.engine.workAppPrefixes = $0 }` becomes `{ _ in model.applyAnchors() }`. The satellite editor's closure is unchanged.

- [ ] **Step 5: Fix the call sites the signature change breaks**

`ProjectSheet.save()` — temporary until Task 5 adds the picker:
```swift
        if let p = editing {
            model.update(p, name: n, client: c, mode: mode, rate: r, budget: b, currency: currency,
                         apps: p.appBundleIDs)
        } else {
            model.createProject(name: n, client: c, mode: mode, rate: r, budget: b,
                                currency: currency, apps: AppModel.globalWorkApps, isManual: true)
        }
```
Also `Sources/Timex/Scenario/ScenarioDriver.swift` if it calls `model.createProject` (grep `createProject(` across `Sources`): add `apps: AppModel.globalWorkApps`.

- [ ] **Step 6: Build, unit suite, smoke**

Run:
```bash
xcodebuild -project Timex.xcodeproj -scheme Cutaway -destination 'platform=macOS' test -only-testing:TimexTests 2>&1 | grep -E "^.*\.swift:[0-9]+:[0-9]+: error:|failed \(|Executed [0-9]+ tests|TEST (FAILED|SUCCEEDED)" | sort -u | tail -4 && ./scripts/smoke.sh "" 3 2>&1 | tail -2
```
Expected: `Executed 315 tests, with 0 failures`; `RESULT: ALL PASS`. Scenario s1 (zero-state detect → auto-create) proves the auto-create path still compiles and creates.

- [ ] **Step 7: Commit**

```bash
git add Sources/Timex/AppModel.swift Sources/Timex/UI/SettingsView.swift Sources/Timex/UI/ProjectSheet.swift Sources/Timex/Scenario/ScenarioDriver.swift Tests/TimexTests/AnchorSetTests.swift
git commit -m "feat: the selected project's apps are the engine's anchors

applyAnchors() is the only writer of engine.workAppPrefixes: launch,
selection, project edit, Settings edit. Auto-created projects start with
the global list, so nothing changes for a Resolve-only day.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: `AppCatalog` and `InstalledApps`

**Files:**
- Create: `Sources/Timex/Projects/AppCatalog.swift`
- Create: `Sources/Timex/Projects/InstalledApps.swift`
- Test: `Tests/TimexTests/AppCatalogTests.swift` (new)

**Interfaces:**
- Produces: `struct AppCatalog.Entry: Identifiable, Hashable { let name: String; let prefix: String; var id: String { prefix } }`; `struct AppCatalog.Group: Identifiable { let name: String; let entries: [Entry]; var id: String { name } }`; `AppCatalog.groups: [Group]`; `AppCatalog.allEntries: [Entry]`.
- Produces: `struct InstalledApp: Identifiable, Hashable, Sendable { let name: String; let bundleID: String; let url: URL; var id: String { bundleID } }`; `enum InstalledApps { static func scan(directories: [URL] = defaultDirectories) -> [InstalledApp]; static let defaultDirectories: [URL]; static func installed(matching prefix: String, in apps: [InstalledApp]) -> InstalledApp? }`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Cutaway

final class AppCatalogTests: XCTestCase {

    func testNoCatalogPrefixShadowsAnother() {
        let prefixes = AppCatalog.allEntries.map(\.prefix)
        XCTAssertEqual(Set(prefixes).count, prefixes.count, "duplicate prefix")
        // Resolve's three ids are a family the engine matches EXACTLY (they are
        // DetectionInput.resolveBundleIDs), so "…DaVinciResolve" being a string
        // prefix of "…DaVinciResolveLite" is not a shadow.
        let exact = Set(DetectionInput.resolveBundleIDs)
        for a in prefixes where !exact.contains(a) {
            for b in prefixes where a != b {
                XCTAssertFalse(b.hasPrefix(a), "\(a) would also match \(b) — one tile would tick two apps")
            }
        }
    }

    func testTheNamedSuitesArePresent() {
        let names = Set(AppCatalog.groups.map(\.name))
        for g in ["DaVinci Resolve", "Adobe", "Microsoft Office", "Also"] {
            XCTAssertTrue(names.contains(g), g)
        }
        XCTAssertTrue(AppCatalog.allEntries.contains { $0.prefix == "com.adobe.PremierePro" })
        XCTAssertTrue(AppCatalog.allEntries.contains { $0.prefix == "com.microsoft.Excel" })
    }

    func testResolveEntriesAreTheEngineIds() {
        let resolve = AppCatalog.groups.first { $0.name == "DaVinci Resolve" }!
        XCTAssertEqual(Set(resolve.entries.map(\.prefix)), Set(DetectionInput.resolveBundleIDs))
    }

    /// The scan finds the app the tests are running inside — no fixture, no
    /// assumption about what is in /Applications on this Mac.
    func testScanFindsTheTestHost() {
        let productsDir = Bundle.main.bundleURL.deletingLastPathComponent()
        let found = InstalledApps.scan(directories: [productsDir])
        let host = found.first { $0.bundleID == Bundle.main.bundleIdentifier }
        XCTAssertNotNil(host, "Cutaway.app must be found in \(productsDir.path)")
        XCTAssertEqual(host?.name, "Cutaway")
    }

    func testScanSkipsNonBundlesAndSortsByName() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Empty.app"), withIntermediateDirectories: true)
        for (name, id) in [("Zed", "dev.zed"), ("Alpha", "com.alpha")] {
            let contents = dir.appendingPathComponent("\(name).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        let found = InstalledApps.scan(directories: [dir])
        XCTAssertEqual(found.map(\.name), ["Alpha", "Zed"], "sorted; Empty.app (no plist) and notes.txt skipped")
    }

    func testPrefixResolvesToAnInstalledBundle() {
        let apps = [
            InstalledApp(name: "Premiere Pro 2025", bundleID: "com.adobe.PremierePro.2025", url: URL(fileURLWithPath: "/x")),
            InstalledApp(name: "Excel", bundleID: "com.microsoft.Excel", url: URL(fileURLWithPath: "/y")),
        ]
        XCTAssertEqual(InstalledApps.installed(matching: "com.adobe.PremierePro", in: apps)?.bundleID, "com.adobe.PremierePro.2025")
        XCTAssertEqual(InstalledApps.installed(matching: "com.microsoft.Excel", in: apps)?.name, "Excel")
        XCTAssertNil(InstalledApps.installed(matching: "com.blackmagic-design.DaVinciResolve", in: apps))
    }
}
```

- [ ] **Step 2: Run — expect compile failure** (`cannot find 'AppCatalog'`, `'InstalledApps'`, `'InstalledApp'`).

- [ ] **Step 3: Implement the catalog**

`Sources/Timex/Projects/AppCatalog.swift`:
```swift
import Foundation

/// The apps a video project is worked in, by suite. Pure data: names for
/// the picker, bundle-id PREFIXES for the engine (Adobe ids carry a year,
/// com.adobe.PremierePro.2025; prefix matching covers every version).
/// Icons are never shipped — InstalledApps finds the real one.
enum AppCatalog {
    struct Entry: Identifiable, Hashable, Sendable {
        let name: String
        let prefix: String
        var id: String { prefix }
    }

    struct Group: Identifiable, Sendable {
        let name: String
        let entries: [Entry]
        var id: String { name }
    }

    static let groups: [Group] = [
        Group(name: "DaVinci Resolve", entries: [
            Entry(name: "DaVinci Resolve", prefix: "com.blackmagic-design.DaVinciResolve"),
            Entry(name: "DaVinci Resolve (Lite)", prefix: "com.blackmagic-design.DaVinciResolveLite"),
            Entry(name: "DaVinci Resolve Studio", prefix: "com.blackmagic-design.DaVinciResolveStudio"),
        ]),
        Group(name: "Adobe", entries: [
            Entry(name: "Premiere Pro", prefix: "com.adobe.PremierePro"),
            Entry(name: "After Effects", prefix: "com.adobe.AfterEffects"),
            Entry(name: "Photoshop", prefix: "com.adobe.Photoshop"),
            Entry(name: "Illustrator", prefix: "com.adobe.illustrator"),
            Entry(name: "Audition", prefix: "com.adobe.Audition"),
            Entry(name: "Lightroom Classic", prefix: "com.adobe.LightroomClassicCC"),
            Entry(name: "InDesign", prefix: "com.adobe.InDesign"),
            Entry(name: "Media Encoder", prefix: "com.adobe.ame.application"),
        ]),
        Group(name: "Microsoft Office", entries: [
            Entry(name: "Word", prefix: "com.microsoft.Word"),
            Entry(name: "Excel", prefix: "com.microsoft.Excel"),
            Entry(name: "PowerPoint", prefix: "com.microsoft.Powerpoint"),
            Entry(name: "Outlook", prefix: "com.microsoft.Outlook"),
            Entry(name: "OneNote", prefix: "com.microsoft.onenote.mac"),
        ]),
        Group(name: "Also", entries: [
            Entry(name: "Final Cut Pro", prefix: "com.apple.FinalCut"),
            Entry(name: "Motion", prefix: "com.apple.motionapp"),
            Entry(name: "Compressor", prefix: "com.apple.Compressor"),
            Entry(name: "Logic Pro", prefix: "com.apple.logic10"),
            Entry(name: "Blender", prefix: "org.blenderfoundation.blender"),
            Entry(name: "Affinity Photo", prefix: "com.seriflabs.affinityphoto"),
            Entry(name: "Affinity Designer", prefix: "com.seriflabs.affinitydesigner"),
            Entry(name: "Figma", prefix: "com.figma.Desktop"),
            Entry(name: "Notion", prefix: "notion.id"),
        ]),
    ]

    static let allEntries: [Entry] = groups.flatMap(\.entries)
}
```
Note on ids: Resolve's three ids are exact (they are the engine's `resolveBundleIDs`) and the shadow test exempts them, as written above.

- [ ] **Step 4: Implement the scan**

`Sources/Timex/Projects/InstalledApps.swift`:
```swift
import AppKit

struct InstalledApp: Identifiable, Hashable, Sendable {
    let name: String
    let bundleID: String
    let url: URL
    var id: String { bundleID }
}

/// What is actually on this Mac. One scan per sheet open, off the main
/// thread; the result answers both "Other…" and "is this catalog app
/// installed, and where is its icon".
enum InstalledApps {
    static let defaultDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
    ]

    static func scan(directories: [URL] = defaultDirectories) -> [InstalledApp] {
        let fm = FileManager.default
        var found: [String: InstalledApp] = [:]
        for dir in directories {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" {
                let plist = url.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plist),
                      let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let id = dict["CFBundleIdentifier"] as? String, !id.isEmpty else { continue }
                let name = (dict["CFBundleDisplayName"] as? String)
                    ?? (dict["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                // First hit wins: /Applications outranks ~/Applications.
                if found[id] == nil { found[id] = InstalledApp(name: name, bundleID: id, url: url) }
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The installed bundle a catalog PREFIX stands for, if any.
    static func installed(matching prefix: String, in apps: [InstalledApp]) -> InstalledApp? {
        apps.first { $0.bundleID.hasPrefix(prefix) }
    }
}
```

- [ ] **Step 5: Run — expect pass**

Expected: `Executed 6 tests, with 0 failures`. If `testScanFindsTheTestHost` fails, print `Bundle.main.bundleURL` in the failure message — under TEST_HOST, `Bundle.main` is `Cutaway.app`, whose parent is the Products directory.

- [ ] **Step 6: Commit**

```bash
git add Sources/Timex/Projects/AppCatalog.swift Sources/Timex/Projects/InstalledApps.swift Tests/TimexTests/AppCatalogTests.swift
git commit -m "feat: app catalog (Resolve, Adobe, Office, more) and an installed-apps scan

Pure data plus one directory scan. No artwork shipped: the scan is also
how a catalog prefix finds the installed bundle whose icon to show.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `AppIcon` — the real icon, or an honest placeholder

**Files:**
- Create: `Sources/Timex/Projects/AppIcon.swift`
- Test: `Tests/TimexTests/AppIconTests.swift` (new)

**Interfaces:**
- Produces: `@MainActor enum AppIcon { static func image(for app: InstalledApp?) -> NSImage? }` (nil ⇒ placeholder); `struct AppIconView: View { init(app: InstalledApp?, name: String, size: CGFloat) }`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import AppKit
@testable import Cutaway

@MainActor
final class AppIconTests: XCTestCase {
    func testInstalledAppYieldsItsIconAndCachesIt() {
        let host = InstalledApp(name: "Cutaway", bundleID: Bundle.main.bundleIdentifier!, url: Bundle.main.bundleURL)
        let first = AppIcon.image(for: host)
        XCTAssertNotNil(first)
        XCTAssertTrue(AppIcon.image(for: host) === first, "second lookup is the cached object")
    }

    func testNotInstalledYieldsNoImage() {
        XCTAssertNil(AppIcon.image(for: nil))
    }
}
```

- [ ] **Step 2: Run — expect compile failure** (`cannot find 'AppIcon'`).

- [ ] **Step 3: Implement**

`Sources/Timex/Projects/AppIcon.swift`:
```swift
import SwiftUI
import AppKit

/// The installed app's own icon, via the workspace. Nothing is bundled:
/// trademarks stay with their owners, and the icon is always the one the
/// user actually sees in their Dock.
@MainActor
enum AppIcon {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for app: InstalledApp?) -> NSImage? {
        guard let app else { return nil }
        let key = app.bundleID as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Icon tile: the real icon when installed, a dashed placeholder when not.
struct AppIconView: View {
    let app: InstalledApp?
    let name: String
    var size: CGFloat = 32

    var body: some View {
        if let image = AppIcon.image(for: app) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed")
                .font(DT.glyph)
                .foregroundStyle(DT.text3)
                .opacity(0.5)
                .frame(width: size, height: size)
                .help("\(name) is not installed")
                .accessibilityHidden(true)
        }
    }
}
```

- [ ] **Step 4: Run — expect pass** (`Executed 2 tests, with 0 failures`).

- [ ] **Step 5: Commit**

```bash
git add Sources/Timex/Projects/AppIcon.swift Tests/TimexTests/AppIconTests.swift
git commit -m "feat: app icons from the installed bundle, cached; dashed placeholder otherwise

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `AppPickerView` in the project sheet, pre-ticked

**Files:**
- Create: `Sources/Timex/Projects/AppPickerView.swift`
- Modify: `Sources/Timex/UI/ProjectSheet.swift`
- Test: `Tests/TimexTests/AppPickerTests.swift` (new — the pure selection model)

**Interfaces:**
- Produces: `struct AppPickerModel { var selected: Set<String>; var query: String; func visibleGroups(catalog:installed:) -> [AppCatalog.Group]; func otherApps(installed:) -> [InstalledApp]; mutating func toggle(_ prefix: String) }`; `struct AppPickerView: View { @Binding var selected: Set<String> }`.
- Consumes: `AppModel.globalWorkApps`, `AppModel.createProject(...apps:)`, `AppModel.update(...apps:)`.

- [ ] **Step 1: Write the failing tests for the selection model**

```swift
import XCTest
@testable import Cutaway

final class AppPickerTests: XCTestCase {
    private let installed = [
        InstalledApp(name: "Premiere Pro 2025", bundleID: "com.adobe.PremierePro.2025", url: URL(fileURLWithPath: "/a")),
        InstalledApp(name: "Excel", bundleID: "com.microsoft.Excel", url: URL(fileURLWithPath: "/b")),
        InstalledApp(name: "Spotify", bundleID: "com.spotify.client", url: URL(fileURLWithPath: "/c")),
    ]

    func testSearchFiltersAcrossGroupsAndDropsEmptyGroups() {
        var m = AppPickerModel(selected: [])
        m.query = "prem"
        let groups = m.visibleGroups(catalog: AppCatalog.groups, installed: installed)
        XCTAssertEqual(groups.map(\.name), ["Adobe"])
        XCTAssertEqual(groups[0].entries.map(\.name), ["Premiere Pro"])
    }

    func testOtherIsEveryInstalledAppNotAlreadyInTheCatalog() {
        let m = AppPickerModel(selected: [])
        XCTAssertEqual(m.otherApps(installed: installed).map(\.name), ["Spotify"],
                       "Premiere and Excel are catalog apps; only Spotify is 'other'")
    }

    func testToggleAddsAndRemoves() {
        var m = AppPickerModel(selected: ["a"])
        m.toggle("b"); XCTAssertEqual(m.selected, ["a", "b"])
        m.toggle("a"); XCTAssertEqual(m.selected, ["b"])
    }

    func testSearchAlsoReachesOtherApps() {
        var m = AppPickerModel(selected: [])
        m.query = "spot"
        XCTAssertEqual(m.otherApps(installed: installed).map(\.name), ["Spotify"])
        m.query = "zzz"
        XCTAssertTrue(m.otherApps(installed: installed).isEmpty)
    }
}
```

- [ ] **Step 2: Run — expect compile failure** (`cannot find 'AppPickerModel'`).

- [ ] **Step 3: Implement the model and the view**

`Sources/Timex/Projects/AppPickerView.swift`:
```swift
import SwiftUI

/// Selection + search, kept out of the view so it is testable.
struct AppPickerModel {
    var selected: Set<String>
    var query: String = ""

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    func visibleGroups(catalog: [AppCatalog.Group], installed: [InstalledApp]) -> [AppCatalog.Group] {
        guard !q.isEmpty else { return catalog }
        return catalog.compactMap { g in
            let hits = g.entries.filter { $0.name.lowercased().contains(q) || $0.prefix.lowercased().contains(q) }
            return hits.isEmpty ? nil : AppCatalog.Group(name: g.name, entries: hits)
        }
    }

    /// Installed apps the catalog does not already name.
    func otherApps(installed: [InstalledApp]) -> [InstalledApp] {
        installed.filter { app in
            !AppCatalog.allEntries.contains { app.bundleID.hasPrefix($0.prefix) }
                && (q.isEmpty || app.name.lowercased().contains(q) || app.bundleID.lowercased().contains(q))
        }
    }

    mutating func toggle(_ prefix: String) {
        if selected.contains(prefix) { selected.remove(prefix) } else { selected.insert(prefix) }
    }
}

/// Native grid of icon toggles by suite, a search field, and "Other…" for
/// everything installed that the catalog does not name.
struct AppPickerView: View {
    @Binding var selected: Set<String>
    @State private var query = ""
    @State private var installed: [InstalledApp] = []
    @State private var showOthers = false

    private var model: AppPickerModel { AppPickerModel(selected: selected, query: query) }
    private let columns = [GridItem(.adaptive(minimum: 84), spacing: DT.s2)]

    var body: some View {
        VStack(alignment: .leading, spacing: DT.s2) {
            TextField("Search apps", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search apps")
            ScrollView {
                VStack(alignment: .leading, spacing: DT.s3) {
                    ForEach(model.visibleGroups(catalog: AppCatalog.groups, installed: installed)) { group in
                        Text(group.name.uppercased()).font(DT.caption).kerning(0.55).foregroundStyle(DT.text3)
                        LazyVGrid(columns: columns, spacing: DT.s2) {
                            ForEach(group.entries) { entry in
                                tile(prefix: entry.prefix, name: entry.name,
                                     app: InstalledApps.installed(matching: entry.prefix, in: installed))
                            }
                        }
                    }
                    DisclosureGroup("Other…", isExpanded: $showOthers) {
                        let others = model.otherApps(installed: installed)
                        if others.isEmpty {
                            Text(query.isEmpty ? "Nothing else installed" : "No match")
                                .font(DT.captionMedium).foregroundStyle(DT.text3)
                        } else {
                            LazyVGrid(columns: columns, spacing: DT.s2) {
                                ForEach(others) { app in
                                    tile(prefix: app.bundleID, name: app.name, app: app)
                                }
                            }
                        }
                    }
                    .font(DT.smallSemibold)
                    .foregroundStyle(DT.text2)
                }
                .padding(.vertical, DT.s1)
            }
            .frame(maxHeight: 240)
        }
        .task {
            // One scan per sheet, off the main thread.
            let apps = await Task.detached(priority: .utility) { InstalledApps.scan() }.value
            installed = apps
        }
    }

    private func tile(prefix: String, name: String, app: InstalledApp?) -> some View {
        let on = selected.contains(prefix)
        return Button {
            var m = model; m.toggle(prefix); selected = m.selected
        } label: {
            VStack(spacing: 4) {
                AppIconView(app: app, name: name, size: 32)
                Text(name).font(DT.captionMedium).foregroundStyle(on ? DT.text : DT.text2)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(on ? AnyShapeStyle(DT.signalSoft) : AnyShapeStyle(DT.card2),
                        in: RoundedRectangle(cornerRadius: DT.rMd))
            .overlay(RoundedRectangle(cornerRadius: DT.rMd)
                .stroke(on ? DT.signal : DT.strokeSubtle, lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .help(app == nil ? "\(name) — not installed" : name)
        .accessibilityLabel(name)
        .accessibilityValue(on ? "selected" : "not selected")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
```

- [ ] **Step 4: Put it in the sheet, pre-ticked**

In `Sources/Timex/UI/ProjectSheet.swift`:

Add state after `@State private var currency`:
```swift
    // Pre-ticked with the global list: the normal case needs zero clicks;
    // a narrow job (an InDesign-only template) is an untick.
    @State private var apps: Set<String> = Set(AppModel.globalWorkApps)
```
Insert after the rate/budget/currency `HStack` and before the hint/duplicate `HStack`:
```swift
            VStack(alignment: .leading, spacing: 6) {
                label("APPS")
                AppPickerView(selected: $apps)
                Text("Only these apps count toward this project.")
                    .font(DT.captionMedium).foregroundStyle(DT.text3)
            }
```
In `.onAppear`, after `currency = p.currency`:
```swift
            // A legacy project (empty list) shows the global list ticked; saving
            // it writes that list out explicitly — same behaviour, now visible.
            apps = p.appBundleIDs.isEmpty ? Set(AppModel.globalWorkApps) : Set(p.appBundleIDs)
```
In `save()`, pass `apps: Array(apps).sorted()` to both `update` and `createProject`, replacing the Task 2 placeholders.
The Create button's `.disabled(...)` gains `|| apps.isEmpty` — a project with no apps can never record, and a sheet must not let someone build that by accident.
Change `.frame(width: 400)` to `.frame(width: 460)`.

- [ ] **Step 5: Build, unit suite, a11y test**

Run the unit filter command (Global Constraints) and the a11y test. Expected: `Executed 327 tests, with 0 failures`; a11y `TEST SUCCEEDED`. If the a11y audit flags the tiles, the missing piece is the `.accessibilityLabel(name)` — every tile has one; check the search field.

- [ ] **Step 6: Commit**

```bash
git add Sources/Timex/Projects/AppPickerView.swift Sources/Timex/UI/ProjectSheet.swift Tests/TimexTests/AppPickerTests.swift
git commit -m "feat: pick a project's apps in the sheet — pre-ticked, searchable, real icons

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Icons on the project — panel row and Stats header

**Files:**
- Create: `Sources/Timex/Projects/AppIconRow.swift`
- Modify: `Sources/Timex/UI/MenuBarPanel.swift` (`PanelRow`)
- Modify: `Sources/Timex/UI/StatsView.swift` (header)
- Test: `Tests/TimexTests/AppIconRowTests.swift` (new — the pure "which four" rule)

**Interfaces:**
- Produces: `enum AppIconRowPolicy { static func shown(_ prefixes: [String], max: Int = 4) -> (shown: [String], more: Int) }`; `struct AppIconRow: View { let prefixes: [String]; let installed: [InstalledApp] }`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Cutaway

final class AppIconRowTests: XCTestCase {
    func testUpToFourThenACount() {
        XCTAssertEqual(AppIconRowPolicy.shown(["a", "b"]).shown, ["a", "b"])
        XCTAssertEqual(AppIconRowPolicy.shown(["a", "b"]).more, 0)
        let six = AppIconRowPolicy.shown(["a", "b", "c", "d", "e", "f"])
        XCTAssertEqual(six.shown, ["a", "b", "c", "d"])
        XCTAssertEqual(six.more, 2)
    }

    func testEmptyListShowsNothing() {
        XCTAssertEqual(AppIconRowPolicy.shown([]).shown, [])
        XCTAssertEqual(AppIconRowPolicy.shown([]).more, 0)
    }
}
```

- [ ] **Step 2: Run — expect compile failure.**

- [ ] **Step 3: Implement**

`Sources/Timex/Projects/AppIconRow.swift`:
```swift
import SwiftUI

enum AppIconRowPolicy {
    /// At most `max` icons, then "+N". Order is the project's own.
    static func shown(_ prefixes: [String], max: Int = 4) -> (shown: [String], more: Int) {
        (Array(prefixes.prefix(max)), Swift.max(0, prefixes.count - max))
    }
}

/// Glanceable "what is this job": the project's app icons, small,
/// decorative — the row's label already names the project.
struct AppIconRow: View {
    let prefixes: [String]
    let installed: [InstalledApp]
    var size: CGFloat = 16

    var body: some View {
        let s = AppIconRowPolicy.shown(prefixes)
        HStack(spacing: 3) {
            ForEach(s.shown, id: \.self) { prefix in
                AppIconView(app: InstalledApps.installed(matching: prefix, in: installed),
                            name: AppCatalog.allEntries.first { $0.prefix == prefix }?.name ?? prefix,
                            size: size)
            }
            if s.more > 0 {
                Text("+\(s.more)").font(DT.tag).foregroundStyle(DT.text3)
            }
        }
        .accessibilityHidden(true)
    }
}
```

`AppModel` gets the shared scan (the panel renders every tick; scanning per render is exactly the kind of cost this app has removed twice already). In `AppModel`, after `var storeIsEphemeral = false`:
```swift
    /// Installed apps, scanned once per launch for the icon rows. The
    /// picker scans again when opened, so a freshly installed app shows up
    /// there without a relaunch.
    private(set) var installedApps: [InstalledApp] = []
```
and at the end of `init()`, before the `if ScenarioMode.isActive { ScenarioDriver.run` block:
```swift
        Task.detached(priority: .utility) { [weak self] in
            let apps = InstalledApps.scan()
            await MainActor.run { self?.installedApps = apps }
        }
```

In `MenuBarPanel.PanelRow`, add `let installed: [InstalledApp]` after `let sessionSeconds: TimeInterval`, pass `installed: model.installedApps` at the call site, and replace the project-name `Text` with:
```swift
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(isRunning ? DT.panelRowActive : DT.body)
                        .foregroundStyle(isRunning ? DT.text : DT.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                    if !project.appBundleIDs.isEmpty {
                        AppIconRow(prefixes: project.appBundleIDs, installed: installed, size: 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
```

In `StatsView.header`, inside the switcher button's `HStack`, directly after the `Text("▼")`:
```swift
                    if let p = project, !p.appBundleIDs.isEmpty {
                        AppIconRow(prefixes: p.appBundleIDs, installed: model.installedApps, size: 16)
                            .padding(.leading, 4)
                    }
```

- [ ] **Step 4: Build, unit suite, a11y, smoke**

Expected: `Executed 329 tests, with 0 failures`; a11y `TEST SUCCEEDED`; `RESULT: ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Timex/Projects/AppIconRow.swift Sources/Timex/AppModel.swift Sources/Timex/UI/MenuBarPanel.swift Sources/Timex/UI/StatsView.swift Tests/TimexTests/AppIconRowTests.swift
git commit -m "feat: a project's app icons on its panel row and in the Stats header

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Migration proof against a copy of the real store; ledger; graphify

**Files:**
- Modify: `LOOP_JOURNAL.md`, `LOOP_RESULTS.tsv`, `GOALS.md`, `README.md`
- Modify: `graphify-out/` (regenerated)

- [ ] **Step 1: Prove the schema change opens an existing store (copy, never the live one)**

The spec asked for a "pre-change fixture"; none exists and one cannot be built from current code. The honest proof: the user's real store, copied into the harness's quarantined data dir, opened by the new build through scenario s8 (relaunch, no-op, counts unchanged).

Run:
```bash
cd "/Users/vaneickelen/Downloads/App Development/cutaway"
D="$HOME/Library/Caches/cutaway-migration-proof"; rm -rf "$D"; mkdir -p "$D"
cp "$HOME/Library/Application Support/default.store" "$D/timex.store"
[ -f "$HOME/Library/Application Support/default.store-wal" ] && cp "$HOME/Library/Application Support/default.store-wal" "$D/timex.store-wal"
[ -f "$HOME/Library/Application Support/default.store-shm" ] && cp "$HOME/Library/Application Support/default.store-shm" "$D/timex.store-shm"
BEFORE=$(sqlite3 "$D/timex.store" 'SELECT COUNT(*) || "|" || CAST(IFNULL(SUM(ZACTIVESECONDS),0) AS INT) FROM ZWORKSESSION;')
cp scenarios/s8-noop-relaunch.txt "$D/scenario.txt"
launchctl setenv TIMEX_SCENARIO "$D/scenario.txt"; launchctl setenv TIMEX_DATA_DIR "$D"
APP=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/Timex-*/Build/Products/Debug/Cutaway.app | head -1)
open -W "$APP"; RC=$?
launchctl unsetenv TIMEX_SCENARIO; launchctl unsetenv TIMEX_DATA_DIR
AFTER=$(sqlite3 "$D/timex.store" 'SELECT COUNT(*) || "|" || CAST(IFNULL(SUM(ZACTIVESECONDS),0) AS INT) FROM ZWORKSESSION;')
COLS=$(sqlite3 "$D/timex.store" 'PRAGMA table_info(ZPROJECT);' | grep -c "ZAPPBUNDLEIDS")
echo "rc=$RC before=$BEFORE after=$AFTER appBundleIDs-column=$COLS"
rm -rf "$D"
```
Expected: `rc=0 before=<n|s> after=<same n|s> appBundleIDs-column=1`. `before == after` proves nothing was lost or duplicated; the column count proves the lightweight migration ran. Record both values in the journal.

- [ ] **Step 2: README**

In `README.md`, directly after the `**Projects follow Resolve.**` paragraph, insert:
```markdown
**Projects know their apps.** When you create a project, tick the apps it's worked in — DaVinci Resolve, the Adobe suite, Office, anything installed. Everything you normally use starts ticked, so most projects need no clicks; an InDesign-only template job is an untick. While a project is selected, only its apps count toward it: a colour pass in Resolve can't land on the wrong invoice. Icons are the real ones from the apps on your Mac.
```

- [ ] **Step 3: Ledger and graph**

Prepend to `LOOP_JOURNAL.md` (newest, under the top `---`):
```markdown
## 2026-09-04 — [feature] Per-project apps — KEPT (<hashes of Tasks 1–6>)
Project.appBundleIDs (empty = global). AnchorSet.resolve is the single
replace-not-extend rule; AppModel.applyAnchors() the single writer of
engine.workAppPrefixes (launch, select, edit, Settings). New projects
pre-ticked with the global list; auto-created Resolve projects get it
too, so a Resolve-only day is unchanged. Catalog is pure data; one
/Applications scan serves "Other…" and prefix→icon resolution; icons come
from NSWorkspace, nothing shipped. Picker is a native LazyVGrid of
toggles with search. Icon rows (max 4, +N) on panel rows and the Stats
header, decorative.
Migration proof: a COPY of the real store opened by the new build via
scenario s8 — before=<n|s> after=<n|s>, ZAPPBUNDLEIDS column present.
Gate: 329 unit tests, smoke x3 ALL PASS, accessibility audit green.
```
Append to `LOOP_RESULTS.tsv` one row per task commit (`<hash>\tPASS\t<count>\tkeep\t<one line>`). Add to `GOALS.md` Done: `- [feature] Per-project apps — catalog, picker, icons, gate-not-memo — <Task 6 hash>`.

Run:
```bash
graphify update . 2>&1 | grep -E "Rebuilt|updated"
git add README.md LOOP_JOURNAL.md GOALS.md graphify-out
git commit -m "docs: per-project apps in the README; ledger; graph

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

No push. Plan 3 (UI, spec Part 4) follows.

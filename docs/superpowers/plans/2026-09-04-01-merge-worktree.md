# Plan 1 — Merge the worktree branch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land `claude/time-tracking-edit-auto-resume-592ba4` (one commit, `670af20`: editable day totals, unified ProjectSheet, forgotten-pause resume) onto `autoresearch/aug20`, keeping both sides everywhere, and make manual edits leave a trace in the data and the CSV.

**Architecture:** One `git merge --no-commit`, seven files resolved by hand to the exact code below, then the tree is built and the whole gate run before the merge commit is made. A second, ordinary commit adds the adjusted-trace (`WorkSession.isAdjusted` → `DayTotal.adjustedSeconds` → CSV `adjusted_hours` → Stats pencil). Then README, journal, fast-forward `main`, push, delete the worktree.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData, XCTest, xcodegen, `scripts/smoke.sh`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-04-final-form-design.md`, Part 1.
- Keep BOTH branches' behaviour: pause persistence (`PauseState.persist`), `pausedLong`, reclaim, idle warning, bridge-idle fix (this branch) AND `autoResume`, `ResumeNotifier`, `ProjectSheet`, `EditDaySheet`, `setActiveSeconds` (worktree).
- Never edit a test to make a change pass. The ONE intended expectation change is `CSVExporterTests.testHeaderMatchesSpecExactly` (a column is added on purpose) — say so in the journal.
- Tokens: this branch was repainted. The worktree's `DT.orange` → `DT.signal`, `DT.onOrange` → `DT.onSignal`. `DT.amber`, `DT.text2`, `DT.text3`, `DT.textPrimary`, `DT.strokeSubtle`, `DT.rowInset`, `DT.rSm` exist.
- `WorkSession.init` on this branch is `init(start:end:activeSeconds:hourlyRate:project:)` — the worktree's call without `hourlyRate:` will not compile.
- `DetectionEngine` on this branch takes an injected `defaults: UserDefaults`; anything the worktree read from `Prefs` inside the engine reads from `defaults` instead. Engine tests use a scratch suite, never `Prefs`.
- `createProject(...)` on this branch has `isManual:`; a human-filled sheet passes `isManual: true`.
- Gate for every commit: unit tests green, `./scripts/smoke.sh "" 3` → `RESULT: ALL PASS`. Visual changes also run `-only-testing:TimexUITests/AccessibilityAuditTests`.
- No tag, no release. `main` is pushed at the end of this plan (approved).
- Journal (`LOOP_JOURNAL.md`, newest entry at top under the `---` line), `LOOP_RESULTS.tsv` (gitignored, append anyway), `GOALS.md` Done list.

---

### Task 1: Start the merge; resolve the two documentation conflicts

**Files:**
- Modify: `GOALS.md`, `LOOP_JOURNAL.md` (conflict markers)

- [ ] **Step 1: Confirm clean tree and start the merge**

Run:
```bash
cd "/Users/vaneickelen/Downloads/App Development/cutaway" && git status --short && git merge --no-commit --no-ff claude/time-tracking-edit-auto-resume-592ba4 2>&1 | tail -12
```
Expected: `git status --short` prints nothing; merge output ends with `Automatic merge failed; fix conflicts and then commit the result.` and lists CONFLICT lines for GOALS.md, LOOP_JOURNAL.md, DetectionEngine.swift, MenuBarPanel.swift, NewProjectSheet.swift, ProjectManageSheets.swift, SettingsView.swift, StatsView.swift, StatusItemController.swift.

- [ ] **Step 2: Resolve GOALS.md — keep ours, add the worktree's Done line**

Run:
```bash
git checkout --ours GOALS.md
```
Then insert this line as the FIRST bullet under `## Done` (keep everything else):
```
- [billing] Editable time & money; forgotten-pause ask/auto resume — 670af20 (merged)
```

- [ ] **Step 3: Resolve LOOP_JOURNAL.md — keep ours, keep the worktree's entry**

Run:
```bash
git checkout --ours LOOP_JOURNAL.md && git show 670af20:LOOP_JOURNAL.md | sed -n '/^## /,/^## /p' | sed '$d' > /tmp/wt-entry.md && head -3 /tmp/wt-entry.md
```
Expected: first line starts with `## ` and mentions editable time / auto resume. Insert the contents of `/tmp/wt-entry.md` into `LOOP_JOURNAL.md` immediately after the top `---` line's following blank line (i.e. it becomes the newest entry, above the 2026-09-04 bridge-idle entry).

- [ ] **Step 4: Stage the two docs**

Run:
```bash
git add GOALS.md LOOP_JOURNAL.md && git diff --name-only --diff-filter=U
```
Expected: the seven Swift files remain listed; no `.md` files.

Do NOT commit — the merge commit is made in Task 7.

---

### Task 2: DetectionEngine — both pause features, one engine

**Files:**
- Modify: `Sources/Timex/Detection/DetectionEngine.swift` (conflict markers)
- Modify: `Tests/TimexTests/EditAndAutoResumeTests.swift` (auto-added by merge; make it use scratch defaults)
- Verify auto-merged: `Sources/Timex/Detection/DetectionState.swift` (gains `AutoResumeMode`)

**Interfaces:**
- Produces: `DetectionEngine.autoResume: AutoResumeMode`, `DetectionEngine.workDetectedWhilePaused: Bool`, `DetectionEngine.onResumePrompt: (() -> Void)?`, `DetectionEngine.resume()`, `DetectionEngine.resumeSignalDuration`, `DetectionEngine.resumePromptCooldown`.

- [ ] **Step 1: Resolve the property block**

Open the file. In the conflicted region near the top (after `static let longPauseThreshold: TimeInterval = 900`), the result must read exactly:

```swift
    static let longPauseThreshold: TimeInterval = 900
    /// What a manual pause does when anchor work is seen again. Read from the
    /// injected defaults in `init` — never from the global store here.
    var autoResume: AutoResumeMode
    /// Sustained anchor input needed before a paused timer reacts — a glance
    /// at Resolve during a call must not wake the clock.
    static let resumeSignalDuration: TimeInterval = 45
    /// "Stay paused" is respected for this long before asking again.
    static let resumePromptCooldown: TimeInterval = 900
    private var resumeSignalStart: Date?
    private var lastResumePrompt: Date?
    /// Paused by hand, yet the editor is clearly working — panel and pill
    /// surface this so the Resume is one click away.
    private(set) var workDetectedWhilePaused = false
    /// Ask mode: fired when work is detected during a manual pause.
    var onResumePrompt: (() -> Void)?
    var idleThreshold: TimeInterval = Prefs.object(forKey: "idleThreshold") as? TimeInterval ?? 120
```

- [ ] **Step 2: Initialise `autoResume` from the injected defaults**

In `init(probes:logger:defaults:)`, directly after `self.defaults = defaults`, add:

```swift
        self.autoResume = AutoResumeMode(rawValue: defaults.string(forKey: "autoResume") ?? "") ?? .ask
```

- [ ] **Step 3: Resolve `togglePause()` — persistence AND signal reset**

The merged function must be exactly:

```swift
    func togglePause() {
        manuallyPaused.toggle()
        manualPauseStart = manuallyPaused ? now() : nil
        PauseState.persist(start: manualPauseStart, to: defaults)
        pausedLong = false
        resumeSignalStart = nil
        lastResumePrompt = nil
        workDetectedWhilePaused = false
        // Re-evaluate immediately but do NOT accumulate — only the 1 Hz
        // timer adds seconds, otherwise every toggle injects phantom time.
        tick(accumulate: false)
    }
```

- [ ] **Step 4: Resolve the `tick()` insertion point**

In `tick(accumulate:)`, directly after `input.satellitePrefixes = satellitePrefixes` and BEFORE the `// Anchor activity ... refreshes the research window` comment, the line must be:

```swift
        reactToWorkWhilePaused(&input)
```
Everything else in `tick` (idle warning, full-screen suppression, reclaim, bridge-idle case, checkpoint) stays as on this branch.

- [ ] **Step 5: Resolve the new methods block**

After `var onTick: (() -> Void)?`, the merged file must contain (verbatim from the worktree):

```swift
    /// Resume from the notification / panel — a no-op unless paused by hand.
    func resume() {
        if manuallyPaused { togglePause() }
    }

    /// A manual pause is sacred while the editor is away. Once an ANCHOR app
    /// is frontmost with live input for `resumeSignalDuration`, the pause is
    /// evidently forgotten: auto mode lifts it, ask mode prompts. Satellites
    /// never count — browsing is ambiguous, editing in Resolve is not.
    /// ponytail: the signal window itself stays unbilled (under-billing rule).
    private func reactToWorkWhilePaused(_ input: inout DetectionInput) {
        guard manuallyPaused, autoResume != .off else {
            resumeSignalStart = nil
            if workDetectedWhilePaused { workDetectedWhilePaused = false }
            return
        }
        if input.frontmostIsAnchor, input.secondsSinceInput < 10 {
            if resumeSignalStart == nil { resumeSignalStart = now() }
        } else if !input.frontmostIsAnchor || input.secondsSinceInput >= 60 {
            resumeSignalStart = nil
        }
        let sustained = resumeSignalStart.map {
            now().timeIntervalSince($0) >= Self.resumeSignalDuration
        } ?? false
        if sustained != workDetectedWhilePaused { workDetectedWhilePaused = sustained }
        guard sustained else { return }
        switch autoResume {
        case .auto:
            logger.log(event: "auto-resume", detail: "anchor work during manual pause")
            togglePause()
            // Same tick evaluates as resumed — no phantom paused(.manual) frame.
            input.manuallyPaused = false
        case .ask:
            let due = lastResumePrompt.map {
                now().timeIntervalSince($0) >= Self.resumePromptCooldown
            } ?? true
            if due {
                lastResumePrompt = now()
                logger.log(event: "resume-prompt")
                onResumePrompt?()
            }
        case .off:
            break
        }
    }
```

- [ ] **Step 6: Remove every conflict marker; confirm DetectionState merged cleanly**

Run:
```bash
grep -n "^<<<<<<<\|^=======\|^>>>>>>>" Sources/Timex/Detection/DetectionEngine.swift; grep -n "enum AutoResumeMode" Sources/Timex/Detection/DetectionState.swift
```
Expected: first grep prints nothing; second prints one line.

- [ ] **Step 7: Make `AutoResumeTests` use a scratch defaults suite**

In `Tests/TimexTests/EditAndAutoResumeTests.swift`, class `AutoResumeTests`, replace the `setUp` body so it reads:

```swift
    override func setUp() async throws {
        probes = DetectionEngineTests.FakeProbes()
        // Isolated defaults: togglePause() persists the manual pause, and a
        // test must never leave a real pause behind in the app's Prefs.
        let scratch = UserDefaults(suiteName: "cutaway.tests.\(UUID().uuidString)")!
        engine = DetectionEngine(probes: probes, defaults: scratch)
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { [weak self] in self!.clock }
        engine.tick()
        engine.togglePause()
        XCTAssertEqual(engine.state, .paused(.manual))
    }
```

- [ ] **Step 8: Stage**

Run:
```bash
git add Sources/Timex/Detection/DetectionEngine.swift Sources/Timex/Detection/DetectionState.swift Tests/TimexTests/EditAndAutoResumeTests.swift
```

---

### Task 3: ProjectSheet replaces NewProjectSheet + RenameProjectSheet

**Files:**
- Modify: `Sources/Timex/UI/NewProjectSheet.swift` (conflict; becomes `ProjectSheet`)
- Modify: `Sources/Timex/UI/ProjectManageSheets.swift` (conflict; drop `RenameProjectSheet`)
- Modify: `Sources/Timex/TimexApp.swift` (auto-merged; verify)
- Modify: `Sources/Timex/UI/TimerView.swift`, `Sources/Timex/UI/StatsView.swift` (`renameTarget` → `editTarget`)
- Verify auto-merged: `Sources/Timex/AppModel.swift` (`editTarget`, `editDay`, `update`, `setDaySeconds`, `seconds(fromHoursText:)`, `hoursText`, no `rename(_:to:)`), `Sources/Timex/UI/Components.swift` (`"Edit…"`)

**Interfaces:**
- Consumes: `AppModel.update(_:name:client:mode:rate:budget:currency:)`, `AppModel.editTarget: Project?`.
- Produces: `struct ProjectSheet: View` with `init(model: AppModel, editing: Project? = nil)`.

- [ ] **Step 1: Write the merged sheet**

Replace the ENTIRE contents of `Sources/Timex/UI/NewProjectSheet.swift` with:

```swift
import SwiftUI

/// Create or edit a project — every billing field is editable after the
/// fact, because rates get negotiated and budgets get amended.
struct ProjectSheet: View {
    @Bindable var model: AppModel
    var editing: Project? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var client = ""
    @State private var mode: BillingMode = .hourly
    // Seeded from the shared defaults, not invented here — a project created
    // on this form and one auto-created from Resolve must agree.
    @State private var rate = String(format: "%.2f", AppModel.defaultHourlyRate)
    @State private var budget = ""
    @State private var currency: TimexCurrency = AppModel.defaultCurrency

    var body: some View {
        VStack(alignment: .leading, spacing: DT.s3) {
            Text(editing == nil ? "New Project" : "Edit Project").font(DT.title).foregroundStyle(DT.text)

            field("PROJECT NAME") {
                TextField("e.g. Nyx Fashion Film", text: $name).accessibilityLabel("Project name").textFieldStyle(.plain)
            }
            field("CLIENT") {
                TextField("optional", text: $client).accessibilityLabel("Client").textFieldStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                label("BILLING MODE")
                HStack(spacing: 2) {
                    modeSeg("Hourly", .hourly)
                    modeSeg("Fixed Budget", .budget)
                }
                .padding(2)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: DT.rMd))
            }

            HStack(spacing: DT.s3) {
                field("HOURLY RATE") {
                    TextField(String(format: "%.2f", AppModel.defaultHourlyRate), text: $rate)
                        .accessibilityLabel("Hourly rate").textFieldStyle(.plain)
                }
                if mode == .budget {
                    field("BUDGET") {
                        TextField("4500", text: $budget).accessibilityLabel("Fixed budget").textFieldStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    label("CURRENCY")
                    Picker("", selection: $currency) {
                        ForEach(TimexCurrency.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
            }

            HStack {
                if isDuplicate {
                    Text("A project with this name already exists")
                        .font(DT.captionMedium)
                        .foregroundStyle(DT.amber)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Create Project" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(DT.signal)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || Double(rate) == nil || isDuplicate)
            }
            .padding(.top, DT.s1)
        }
        .padding(DT.s4)
        .frame(width: 400)
        .background(DT.card)
        .onAppear {
            guard let p = editing else { return }
            name = p.name
            client = p.client
            mode = p.mode
            rate = String(format: "%.2f", p.hourlyRate)
            budget = p.budget > 0 ? String(format: "%.0f", p.budget) : ""
            currency = p.currency
        }
    }

    private var isDuplicate: Bool {
        let others = model.projects.filter { $0.persistentModelID != editing?.persistentModelID }
        return AppModel.isDuplicateName(name, existing: others.map(\.name))
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let c = client.trimmingCharacters(in: .whitespaces)
        let r = AppModel.clampedRate(Double(rate) ?? 0)
        let b = max(0, Double(budget) ?? 0)
        if let p = editing {
            model.update(p, name: n, client: c, mode: mode, rate: r, budget: b, currency: currency)
        } else {
            model.createProject(name: n, client: c, mode: mode, rate: r, budget: b,
                                currency: currency, isManual: true)
        }
        dismiss()
    }

    private func label(_ t: String) -> some View {
        Text(t).font(DT.caption).kerning(0.55).foregroundStyle(DT.text3)
    }

    @ViewBuilder
    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title)
            content()
                .font(DT.body)
                .foregroundStyle(DT.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(DT.card2, in: RoundedRectangle(cornerRadius: DT.rMd))
                .overlay(RoundedRectangle(cornerRadius: DT.rMd).stroke(DT.strokeSubtle, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func modeSeg(_ title: String, _ m: BillingMode) -> some View {
        let on = mode == m
        Button { mode = m } label: {
            Text(title)
                .font(DT.smallSemibold)
                .foregroundStyle(on ? DT.signal : DT.text3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(on ? AnyShapeStyle(DT.signalSoft) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: DT.rSm))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Rename the file to match the type**

Run:
```bash
git mv Sources/Timex/UI/NewProjectSheet.swift Sources/Timex/UI/ProjectSheet.swift
```
(If git reports the path is in conflict, run `git add Sources/Timex/UI/NewProjectSheet.swift` first, then the `git mv`.)

- [ ] **Step 3: Resolve ProjectManageSheets — delete `RenameProjectSheet`, keep `DeleteProjectSheet`**

Run:
```bash
git checkout --theirs Sources/Timex/UI/ProjectManageSheets.swift && grep -c "RenameProjectSheet" Sources/Timex/UI/ProjectManageSheets.swift; grep -n "tint(DT\." Sources/Timex/UI/ProjectManageSheets.swift
```
Expected: `0`, and the tint line shows `DT.red`. If it shows `DT.orange`, change it to `DT.red` (the delete button was always red on this branch).

- [ ] **Step 4: Point the two switchers at `editTarget`**

In `Sources/Timex/UI/TimerView.swift` line ~51 and `Sources/Timex/UI/StatsView.swift` line ~61, change
```swift
onRename: { switcherOpen = false; model.renameTarget = $0 },
```
to
```swift
onRename: { switcherOpen = false; model.editTarget = $0 },
```
(StatsView still has conflict markers from Task 4; edit this line inside the `ours` side and leave the rest for Task 4.)

- [ ] **Step 5: Verify the auto-merged files**

Run:
```bash
grep -n "ProjectSheet\|editTarget\|editDay\|EditDaySheet" Sources/Timex/TimexApp.swift; grep -n "func update(\|func setDaySeconds\|editTarget\|renameTarget\|func rename(" Sources/Timex/AppModel.swift; grep -n '"Edit…"' Sources/Timex/UI/Components.swift
```
Expected: TimexApp shows the three `.sheet` uses (`ProjectSheet(model:)`, `ProjectSheet(model:editing:)`, `EditDaySheet`); AppModel shows `update(`, `setDaySeconds`, `editTarget`, and NO `renameTarget` / `func rename(`; Components shows one `"Edit…"`.

- [ ] **Step 6: Stage**

Run:
```bash
git add Sources/Timex/UI/ProjectSheet.swift Sources/Timex/UI/ProjectManageSheets.swift Sources/Timex/UI/TimerView.swift Sources/Timex/TimexApp.swift Sources/Timex/AppModel.swift Sources/Timex/UI/Components.swift
```

---

### Task 4: StatsView — edit rows on top of session-detail rows

Both branches made the day row a button: this branch expands the session detail, the worktree opens the editor. Click keeps this branch's meaning (expand); editing is reached from the expanded detail and from a right-click.

**Files:**
- Modify: `Sources/Timex/UI/StatsView.swift` (conflict)
- Modify: `Sources/Timex/UI/EditDaySheet.swift` (auto-added; retint)

**Interfaces:**
- Consumes: `AppModel.editDay: DayEditTarget?`, `DayEditTarget(day: Date?)`.

- [ ] **Step 1: Resolve the header conflict — keep ours + `＋ Add`**

In `daysCard`, the header `HStack` must read:

```swift
            HStack {
                Text("Daily Breakdown").font(DT.smallSemibold).foregroundStyle(DT.text)
                Spacer()
                Text(rangeLabel(days)).font(DT.captionMedium).foregroundStyle(DT.text3)
                Button { model.editDay = DayEditTarget(day: nil) } label: {
                    Text("＋ Add").font(DT.captionMedium).foregroundStyle(DT.text2)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: DT.rSm))
                }
                .buttonStyle(.plain)
                .help("Add time for a day")
                .accessibilityLabel("Add time for a day")
            }
```

- [ ] **Step 2: Resolve `dayRow` — keep ours (expand toggle), add a context menu**

Take the `ours` side of `dayRow` entirely (the `Button { expandedDay = ... }` version with the `.accessibilityHint(expandedDay == d.day ? "Hide sessions" : "Show sessions")`). Drop the worktree's `dayRowBody` split. Then add, directly after that `.accessibilityHint(...)` modifier:

```swift
        .contextMenu {
            Button("Edit day…") { model.editDay = DayEditTarget(day: d.day) }
        }
```

- [ ] **Step 3: Add the edit affordance to the expanded detail**

In `private func sessionDetail(_ d: DayTotal, project p: Project, isToday: Bool) -> some View`, inside its outermost `VStack`, append as the LAST child:

```swift
            HStack {
                Spacer()
                Button("Edit day…") { model.editDay = DayEditTarget(day: d.day) }
                    .font(DT.captionMedium)
                    .buttonStyle(.plain)
                    .foregroundStyle(DT.signal)
                    .accessibilityLabel("Edit \(isToday ? "today" : d.day.formatted(.dateTime.month(.abbreviated).day()))")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
```

- [ ] **Step 4: Retint `EditDaySheet`**

Run:
```bash
sed -i '' 's/DT\.orange/DT.signal/g; s/DT\.onOrange/DT.onSignal/g' Sources/Timex/UI/EditDaySheet.swift && grep -n "DT.orange\|DT.onOrange" Sources/Timex/UI/EditDaySheet.swift
```
Expected: no output from grep.

- [ ] **Step 5: No markers left; stage**

Run:
```bash
grep -n "^<<<<<<<\|^=======\|^>>>>>>>" Sources/Timex/UI/StatsView.swift; git add Sources/Timex/UI/StatsView.swift Sources/Timex/UI/EditDaySheet.swift
```
Expected: grep prints nothing.

---

### Task 5: Panel banner and pill hint

**Files:**
- Modify: `Sources/Timex/UI/MenuBarPanel.swift` (conflict)
- Modify: `Sources/Timex/UI/StatusItemController.swift` (conflict)

**Interfaces:**
- Consumes: `DetectionEngine.workDetectedWhilePaused`, `DetectionEngine.resume()`.

- [ ] **Step 1: Resolve the panel body — banner between project list and research window**

The `body` VStack must be:

```swift
        VStack(spacing: 0) {
            hero
            projectList
            resumeBanner
            researchWindow
            receipt
            footer
        }
```

- [ ] **Step 2: Add the banner (retinted) after `projectList`**

Insert before `// MARK: - Research window`:

```swift
    // MARK: - Resume banner

    /// Paused by hand, but Resolve is clearly being driven. The notification
    /// asks the same question; this is the answer that needs no permission.
    @ViewBuilder
    private var resumeBanner: some View {
        if model.engine.workDetectedWhilePaused {
            HStack(spacing: DT.s2) {
                Text("Looks like you're working")
                    .font(DT.captionMedium)
                    .foregroundStyle(DT.amber)
                Spacer(minLength: 0)
                Button {
                    model.engine.resume()
                } label: {
                    Text("Resume")
                        .font(DT.smallSemibold)
                        .foregroundStyle(DT.onSignal)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(DT.signal, in: RoundedRectangle(cornerRadius: DT.rSm))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume tracking")
            }
            .padding(.horizontal, DT.rowInset)
            .padding(.vertical, DT.s2)
            .background(DT.amber.opacity(0.08))
            .overlay(alignment: .top) {
                Rectangle().fill(DT.strokeSubtle).frame(height: 1)
            }
        }
    }
```

- [ ] **Step 3: Resolve the pill hint at every `pausedHint:` call site**

In `StatusItemController.swift` there are three sites (approx. lines 33, 252, 258). Each becomes:

Visual pill (line ~252, inside `PillView`):
```swift
                 pausedHint: model.engine.workDetectedWhilePaused ? "‖ paused · working?"
                             : model.engine.pausedLong ? "‖ still paused" : nil)
```
Spoken / label sites (lines ~33 and ~258, the ones that read `"still paused"` without the bar):
```swift
pausedHint: model.engine.workDetectedWhilePaused ? "paused, working?"
            : model.engine.pausedLong ? "still paused" : nil
```
Keep each site's surrounding call exactly as it is; only the `pausedHint:` argument changes.

- [ ] **Step 4: No markers; stage**

Run:
```bash
grep -n "^<<<<<<<\|^=======\|^>>>>>>>" Sources/Timex/UI/MenuBarPanel.swift Sources/Timex/UI/StatusItemController.swift; git add Sources/Timex/UI/MenuBarPanel.swift Sources/Timex/UI/StatusItemController.swift
```
Expected: grep prints nothing.

---

### Task 6: Settings row "After a manual pause"

**Files:**
- Modify: `Sources/Timex/UI/SettingsView.swift` (conflict)

- [ ] **Step 1: Resolve — ours, plus one row after "Away grace"**

Take the `ours` side of the whole file, then insert directly after the `row("Away grace", ...) { ... }` block and its following `divider`:

```swift
                row("After a manual pause", sub: "When you start editing again in a workflow app") {
                    Picker("", selection: Binding(
                        get: { model.engine.autoResume.rawValue },
                        set: { Prefs.set($0, forKey: "autoResume")
                               model.engine.autoResume = AutoResumeMode(rawValue: $0) ?? .ask }
                    )) {
                        Text("Stay paused").tag(AutoResumeMode.off.rawValue)
                        Text("Ask me (notification)").tag(AutoResumeMode.ask.rawValue)
                        Text("Resume automatically").tag(AutoResumeMode.auto.rawValue)
                    }
                    .labelsHidden().frame(width: 170)
                }
                divider
```

- [ ] **Step 2: No markers; stage**

Run:
```bash
grep -n "^<<<<<<<\|^=======\|^>>>>>>>" Sources/Timex/UI/SettingsView.swift; git add Sources/Timex/UI/SettingsView.swift; git diff --name-only --diff-filter=U
```
Expected: both greps print nothing (no unresolved paths remain).

---

### Task 7: Compile, fix the store call, run the gate, make the merge commit

**Files:**
- Modify: `Sources/Timex/Store/SessionStore.swift` (auto-merged; one call is wrong for this branch)

- [ ] **Step 1: Fix the adjustment insert to stamp the rate**

In `SessionStore.setActiveSeconds(_:on:for:calendar:now:)`, change
```swift
            context.insert(WorkSession(start: anchor, end: anchor, activeSeconds: delta, project: project))
```
to
```swift
            context.insert(WorkSession(start: anchor, end: anchor, activeSeconds: delta,
                                       hourlyRate: project.hourlyRate, project: project))
```
Also make the method drop the memo: add `invalidateTodayCache()` as the line after `try context.save()` inside that method.

- [ ] **Step 2: Regenerate the project (new files) and build**

Run:
```bash
xcodegen generate >/dev/null && xcodebuild -project Timex.xcodeproj -scheme Cutaway -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -20
```
Expected: `** BUILD SUCCEEDED **`. If errors: they are token names (`DT.orange`, `DT.onOrange`) or `renameTarget` — fix per the Global Constraints, never by adding tokens.

- [ ] **Step 3: Unit tests**

Run:
```bash
xcodebuild -project Timex.xcodeproj -scheme Cutaway -destination 'platform=macOS' test -only-testing:TimexTests 2>&1 | grep -E "Executed [0-9]+ tests|error:|failed" | tail -5
```
Expected: last line `Executed 306 tests, with 0 failures` (293 + 7 DayEditTests + 6 AutoResumeTests). A failure in `PausePersistenceTests` means Task 2 Step 3 lost `PauseState.persist`; a failure in `SessionStoreTests.testRename…` means `SessionStore.rename` was removed (it must stay).

- [ ] **Step 4: Smoke ×3**

Run:
```bash
./scripts/smoke.sh "" 3 2>&1 | tail -4
```
Expected: `RESULT: ALL PASS`.

- [ ] **Step 5: Accessibility UI test**

Run:
```bash
xcodebuild -project Timex.xcodeproj -scheme Cutaway -destination 'platform=macOS' test -only-testing:TimexUITests/AccessibilityAuditTests 2>&1 | grep -E "Executed|failed|error:" | tail -3
```
Expected: `with 0 failures`.

- [ ] **Step 6: Merge commit**

Run:
```bash
git add -A Sources Tests && git status --short | grep -v "^M \|^A \|^R " ; git commit -F - <<'EOF'
merge: editable time & money, forgotten-pause resume (claude/time-tracking-edit-auto-resume-592ba4)

Both branches kept everywhere:
- DetectionEngine: autoResume (off/ask/auto) alongside pause persistence,
  pausedLong, reclaim, idle warning and the bridge-idle fix. Auto-resume
  lifts the pause through togglePause(), so the persisted pause start is
  cleared the same way a click clears it.
- ProjectSheet (create + edit) replaces NewProjectSheet and RenameProjectSheet;
  the delete-with-reassignment sheet stays.
- Stats: click still expands a day's sessions; "Edit day…" lives in the
  expanded detail and in the row's context menu; "＋ Add" in the header.
- Panel resume banner and pill hint, Settings "After a manual pause".
- setActiveSeconds stamps the project rate on the adjustment session
  (this branch's WorkSession requires it).
- AutoResumeTests use a scratch defaults suite, like every engine test here.

Gate: 306 unit tests, smoke x3 ALL PASS, accessibility audit green.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git log --oneline -1
```
Expected: the `status` grep prints nothing (no untracked leftovers); a merge commit hash prints.

---

### Task 8: Edits leave a trace — `isAdjusted` → `adjustedSeconds` → CSV → pencil

**Files:**
- Modify: `Sources/Timex/Store/Models.swift`
- Modify: `Sources/Timex/Store/SessionStore.swift` (`setActiveSeconds`, `dayTotals`)
- Modify: `Sources/Timex/CSV/CSVExporter.swift`
- Modify: `Sources/Timex/UI/StatsView.swift` (pencil in `dayRow`)
- Test: `Tests/TimexTests/EditAndAutoResumeTests.swift` (DayEditTests), `Tests/TimexTests/CSVExporterTests.swift`

**Interfaces:**
- Produces: `WorkSession.isAdjusted: Bool` (default `false`), `WorkSession.init(start:end:activeSeconds:hourlyRate:project:isAdjusted:)` with `isAdjusted: Bool = false`, `DayTotal.adjustedSeconds: TimeInterval` (default `0`), CSV column `adjusted_hours` directly after `active_hours`.

- [ ] **Step 1: Write the failing store tests**

Append inside `final class DayEditTests` (before its closing brace):

```swift
    func testGrowingADayIsFlaggedAsAdjusted() throws {
        try store.record(SessionRecord(start: date(17, 9), end: date(17, 11), activeSeconds: 6000), to: p, calendar: cal)
        try store.setActiveSeconds(9000, on: date(17, 15), for: p, calendar: cal)
        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal).first)
        XCTAssertEqual(day.adjustedSeconds, 3000, accuracy: 0.01, "the typed part is separable from the tracked part")
        let adjusted = try store.context.fetch(FetchDescriptor<WorkSession>()).filter(\.isAdjusted)
        XCTAssertEqual(adjusted.count, 1)
        XCTAssertEqual(adjusted[0].hourlyRate, 85, "an adjustment bills at the rate in force, like any session")
    }

    func testShrinkingIsNotAnAdjustment() throws {
        try store.record(SessionRecord(start: date(17, 9), end: date(17, 10), activeSeconds: 3600), to: p, calendar: cal)
        try store.setActiveSeconds(1800, on: date(17, 9), for: p, calendar: cal)
        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal).first)
        XCTAssertEqual(day.adjustedSeconds, 0, "removing time invents nothing — no flag")
    }

    func testUntouchedDayHasNoAdjustment() throws {
        try store.record(SessionRecord(start: date(17, 9), end: date(17, 10), activeSeconds: 3600), to: p, calendar: cal)
        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal).first)
        XCTAssertEqual(day.adjustedSeconds, 0)
    }
```

- [ ] **Step 2: Run them — expect compile failure**

Run:
```bash
xcodebuild -project Timex.xcodeproj -scheme Cutaway -destination 'platform=macOS' test -only-testing:TimexTests/DayEditTests 2>&1 | grep -E "error:|Executed" | head -5
```
Expected: `error: value of type 'DayTotal' has no member 'adjustedSeconds'` (and `isAdjusted`).

- [ ] **Step 3: Model + store**

In `Sources/Timex/Store/Models.swift`, class `WorkSession`, after `var hourlyRate: Double = 0` add:

```swift
    /// True for a span that was TYPED, not tracked — the growth half of a day
    /// edit. Invoices may carry typed time; they may not hide it. Default so
    /// rows written before this field existed migrate as "tracked".
    var isAdjusted: Bool = false
```
Change the init to:
```swift
    init(start: Date, end: Date, activeSeconds: TimeInterval,
         hourlyRate: Double, project: Project?, isAdjusted: Bool = false) {
        self.start = start
        self.end = end
        self.activeSeconds = activeSeconds
        self.hourlyRate = hourlyRate
        self.project = project
        self.isAdjusted = isAdjusted
    }
```
In `struct DayTotal`, after `var earned: Double = 0` add:
```swift
    /// Seconds of this day that were typed in, not tracked. Part of
    /// `activeSeconds`, never in addition to it.
    var adjustedSeconds: TimeInterval = 0
```
In `SessionStore.setActiveSeconds`, the insert becomes:
```swift
            context.insert(WorkSession(start: anchor, end: anchor, activeSeconds: delta,
                                       hourlyRate: project.hourlyRate, project: project,
                                       isAdjusted: true))
```
In `SessionStore.dayTotals`, add to the `DayTotal(` initializer, after `earned: ...`:
```swift
                earned: sessions.reduce(0) { $0 + $1.earned(projectRate: project.hourlyRate) },
                adjustedSeconds: sessions.filter(\.isAdjusted).reduce(0) { $0 + $1.activeSeconds }
```

- [ ] **Step 4: Run the three tests — expect pass**

Run the Step 2 command. Expected: `Executed 10 tests, with 0 failures`.

- [ ] **Step 5: Write the failing CSV test and update the header expectation**

In `Tests/TimexTests/CSVExporterTests.swift`:

Change `testHeaderMatchesSpecExactly` to expect the new header (intended change — an `adjusted_hours` column after `active_hours`; journal it):
```swift
    func testHeaderMatchesSpecExactly() {
        XCTAssertEqual(CSVExporter.header,
            "date,weekday,project,client,billing_mode,currency,sessions_count,first_start,last_end,active_hours,adjusted_hours,idle_excluded_hours,hourly_rate,earned,budget_total,budget_remaining,budget_percent_used,cumulative_hours,cumulative_earned")
    }
```
Add:
```swift
    func testAdjustedHoursColumnIsZeroUnlessTyped() {
        var days = sampleDays
        days[1].adjustedSeconds = 0.6 * 3600
        let csv = CSVExporter.export(project: "Nyx", client: "", mode: .hourly, currency: .chf,
                                     hourlyRate: 85, budget: 0, days: days, calendar: cal)
        let rows = csv.split(separator: "\n").map { $0.split(separator: ",", omittingEmptySubsequences: false) }
        let col = rows[0].firstIndex(of: "adjusted_hours")!
        XCTAssertEqual(rows[1][col], "0.00", "an untouched day shows no adjustment")
        XCTAssertEqual(rows[2][col], "0.60")
        XCTAssertEqual(rows[2][col - 1], "4.60", "active_hours still includes the typed part")
        XCTAssertTrue(csv.contains("total_active_hours,11.50"), "totals unchanged by the trace column")
    }
```

- [ ] **Step 6: Run — expect the header test and the new test to fail**

Run:
```bash
xcodebuild -project Timex.xcodeproj -scheme Cutaway -destination 'platform=macOS' test -only-testing:TimexTests/CSVExporterTests 2>&1 | grep -E "error:|failed|Executed" | tail -4
```
Expected: two failures (`testHeaderMatchesSpecExactly`, `testAdjustedHoursColumnIsZeroUnlessTyped`).

- [ ] **Step 7: Exporter**

In `CSVExporter.header`, change `"active_hours",` to `"active_hours", "adjusted_hours",`. Update the doc comment `/// Builds the 18-column CSV per spec.` → `/// Builds the 19-column CSV per spec.`
In the row builder, directly after `String(format: "%.2f", hours),` add:
```swift
                String(format: "%.2f", round2(d.adjustedSeconds / 3600)),
```

- [ ] **Step 8: Run the whole unit suite**

Run:
```bash
xcodebuild -project Timex.xcodeproj -scheme Cutaway -destination 'platform=macOS' test -only-testing:TimexTests 2>&1 | grep -E "Executed [0-9]+ tests|failed" | tail -3
```
Expected: `Executed 310 tests, with 0 failures`. If any other CSV test indexes a column by position past `active_hours`, it is asserting on the old shape — update its index and say so in the journal; do not touch its values.

- [ ] **Step 9: Pencil on adjusted days**

In `StatsView.dayRow`, directly after the hours `Text(String(format: "%.1fh", d.activeSeconds / 3600))...monospacedDigit()` add:
```swift
            if d.adjustedSeconds > 0 {
                Image(systemName: "pencil")
                    .font(DT.glyph)
                    .foregroundStyle(DT.text3)
                    .help("Includes manual adjustment")
                    .accessibilityLabel("includes manual adjustment")
            }
```

- [ ] **Step 10: Build, a11y test, commit**

Run:
```bash
xcodebuild -project Timex.xcodeproj -scheme Cutaway -destination 'platform=macOS' test -only-testing:TimexUITests/AccessibilityAuditTests 2>&1 | grep -E "Executed|failed" | tail -2 && git add Sources/Timex/Store/Models.swift Sources/Timex/Store/SessionStore.swift Sources/Timex/CSV/CSVExporter.swift Sources/Timex/UI/StatsView.swift Tests/TimexTests/EditAndAutoResumeTests.swift Tests/TimexTests/CSVExporterTests.swift && git commit -F - <<'EOF'
feat: typed time is marked — adjusted_hours in the CSV, a pencil in Stats

A day edit that grows a day writes an adjustment session; it is now
flagged isAdjusted, summed per day as DayTotal.adjustedSeconds, printed
as a 19th CSV column directly after active_hours, and shown as a pencil
on the Stats row. Shrinking a day deletes real sessions and is not
flagged — nothing was invented. Totals are unchanged: the column is a
subset of active_hours, not an addition.

The CSV header test changed on purpose (one column added); every other
expectation is untouched.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
git log --oneline -1
```
Expected: a11y `0 failures`; commit hash prints.

---

### Task 9: README, ledger, push `main`, remove the worktree

**Files:**
- Modify: `README.md`, `LOOP_JOURNAL.md`, `LOOP_RESULTS.tsv`, `GOALS.md`

- [ ] **Step 1: README — forgotten pauses and editing, with the sacred-pause wording from the spec**

In `README.md`, directly after the `**Hard boundaries.**` paragraph (line ~58), insert:

```markdown
**Forgotten pauses.** Pause for a call, come back, edit for an hour — and never notice the amber pill. Cutaway watches for that: once you've been actively editing in Resolve (or another workflow app) for about 45 seconds while paused, it asks *"Are you working?"* as a notification — one click resumes. The panel shows the same question with a Resume button, and the pill reads *paused · working?*. The pause stays sacred backwards: nothing before the resume is ever billed, including those 45 seconds. Prefer it to resume on its own, or never to ask? Settings → *After a manual pause*. Browsers never trigger this; only workflow apps do.
```

Directly after the `**CSV export**` paragraph (line ~71), insert:

```markdown
**Everything is editable — and it says so.** Expand any day in *Stats → Daily Breakdown* and choose *Edit day…* (or right-click the row) to correct its time — type hours (`1:30`, `1.5`, `90m`) or type the amount and the hours follow from your rate. *＋ Add* enters a day Cutaway never saw. Right-click a project in the switcher → *Edit…* to change its name, client, rate, budget, mode or currency. Corrections trim or extend the recorded sessions, so first/last activity in the CSV stays truthful — and typed time is marked: a pencil on the day, and an `adjusted_hours` column in the CSV, so every line on an invoice says whether it was tracked or entered.
```

- [ ] **Step 2: Journal, results, goals**

Prepend to `LOOP_JOURNAL.md` (as the newest entry, directly under the top `---` line and blank line), replacing `<merge>` and `<trace>` with the two commit hashes from Task 7 and Task 8:

```markdown
## 2026-09-04 — [merge] Worktree branch landed; edits now leave a trace — KEPT (<merge>, <trace>)
Merged claude/time-tracking-edit-auto-resume-592ba4 (670af20) into
autoresearch/aug20. Seven files conflicted; both sides kept everywhere.
Decisions: click on a Stats day still expands its sessions (this branch's
newer meaning); "Edit day…" lives in the expanded detail and the row's
context menu. Auto-resume lifts a pause through togglePause(), so the
persisted pause start clears exactly as a click would. AutoResumeTests
moved onto a scratch defaults suite — the worktree's version toggled the
REAL manual-pause pref from a unit test.
Fix found by the merge: the worktree's adjustment insert had no rate
(this branch stamps every session); it would not have compiled.
Then, per the spec's honesty rule: WorkSession.isAdjusted →
DayTotal.adjustedSeconds → CSV adjusted_hours (after active_hours) →
pencil on the Stats row. One test expectation changed on purpose:
CSVExporterTests.testHeaderMatchesSpecExactly gains the column.
Gate: 310 unit tests, smoke x3 ALL PASS, accessibility audit green.
main fast-forwarded and pushed; worktree and branch deleted.

```

Append to `LOOP_RESULTS.tsv` (two rows, hashes filled in):
```
<merge>	PASS	306	keep	worktree branch merged: editable time, ProjectSheet, forgotten-pause resume
<trace>	PASS	310	keep	typed time marked: isAdjusted, adjusted_hours CSV column, Stats pencil
```

In `GOALS.md` under `## Done`, add as the first bullet:
```
- [billing] Typed time is marked — adjusted_hours column, Stats pencil — <trace>
```

- [ ] **Step 3: Commit the docs**

Run:
```bash
git add README.md LOOP_JOURNAL.md GOALS.md && git commit -qm "docs: README for forgotten pauses and marked edits; ledger

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" && git log --oneline -1
```

- [ ] **Step 4: Fast-forward `main` and push it (approved in the design session)**

Run:
```bash
git branch -f main autoresearch/aug20 && git push origin main 2>&1 | tail -2 && git rev-list --left-right --count main...origin/main
```
Expected: push succeeds; final line `0	0`.

- [ ] **Step 5: Remove the worktree and the merged branch**

Run:
```bash
git worktree remove ".claude/worktrees/time-tracking-edit-auto-resume-592ba4" && git branch -d claude/time-tracking-edit-auto-resume-592ba4 && git worktree list && git branch
```
Expected: one worktree (this directory); branches `autoresearch/aug20` and `main` only. `git branch -d` must succeed without `-D` — if it refuses, the merge did not land and nothing above should have been pushed; stop and report.

- [ ] **Step 6: Build the knowledge graph for the next plan**

Run:
```bash
graphify update . 2>&1 | tail -3 && ls graphify-out/ | head
```
Expected: `graphify-out/graph.json` and `GRAPH_REPORT.md` exist. Commit:
```bash
git add graphify-out && git commit -qm "chore: graphify map of the merged tree

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" && git log --oneline -1
```

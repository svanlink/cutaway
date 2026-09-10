import SwiftUI

/// View 2 — stats: title switcher, stat rows, daily breakdown, CSV export.
struct StatsView: View {
    @Bindable var model: AppModel
    @State private var switcherOpen = false
    /// The day whose sessions are unfolded, if any. One at a time — the
    /// breakdown is a ledger, not an outline.
    @State private var expandedDay: Date?

    private var project: Project? { model.selectedProject }

    var body: some View {
        VStack(spacing: DT.s3) {
            header.accessibilityIdentifier("stats.header")
            if let p = project {
                statRows(p).accessibilityIdentifier("stats.rows")
                daysCard(p).accessibilityIdentifier("stats.days")
            } else {
                // An empty state that names the next action and then hands
                // it to you. "Create a project to see stats" was true, and a
                // dead end: it told a first-time user what was missing while
                // leaving them to find the way to fix it.
                Spacer()
                VStack(spacing: DT.s3) {
                    Text("No project yet")
                        .font(DT.title)
                        .foregroundStyle(DT.text2)
                    Text("Cutaway follows DaVinci Resolve. Make a project here, or just open one in Resolve and Cutaway will ask.")
                        .font(DT.body)
                        .foregroundStyle(DT.text3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    Button("New project…") { model.showNewProjectSheet = true }
                        .buttonStyle(DayActionButtonStyle())
                }
                Spacer()
            }
        }
        .padding(.horizontal, DT.margin)
        .padding(.bottom, DT.margin)
    }

    // MARK: - Header (title = switcher)

    private var header: some View {
        HStack(spacing: DT.s2) {
            Button { switcherOpen.toggle() } label: {
                // Two lines, not one. Name, client, disclosure arrow and the
                // app-icon row were all competing for a single baseline, and
                // the loser was the project name — "Nyx Fashion Film" printed
                // as "Nyx Fash…". The name is the identity of the thing being
                // billed; it is the last thing that may be abbreviated. The
                // panel already stacks client-over-name, so this is the
                // pattern the app has, not a new one.
                VStack(alignment: .leading, spacing: DT.s1) {
                    // The client and the app icons share the small line. Both
                    // are context; neither is the name, and on a 480 pt
                    // window the icon row plus the arrow was exactly the
                    // width that pushed "Nyx Fashion Film" into "Nyx Fash…".
                    HStack(spacing: DT.within) {
                        if let c = project?.client, !c.isEmpty {
                            Text(c.uppercased())
                                .font(DT.panelClient)
                                .kerning(0.84)
                                .foregroundStyle(DT.text3)
                                .lineLimit(1)
                        }
                        if let p = project, !p.appBundleIDs.isEmpty {
                            AppIconRow(prefixes: p.appBundleIDs, installed: model.installedApps, size: 12)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: DT.s2) {
                        Text(project?.name ?? "No project")
                            .font(DT.title)
                            .foregroundStyle(DT.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.down").font(DT.glyphLight).foregroundStyle(DT.text3)
                    }
                }
                // The identity wins the row. Actions are verbs you can find
                // again; the name is the thing you are billing.
                .layoutPriority(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $switcherOpen, arrowEdge: .bottom) {
                SwitcherList(
                    projects: model.projects,
                    currentID: model.selectedProjectID,
                    select: { model.selectManually($0); switcherOpen = false },
                    newProject: { switcherOpen = false; model.showNewProjectSheet = true },
                    onEdit: { switcherOpen = false; model.editTarget = $0 },
                    onDelete: { switcherOpen = false; model.deleteTarget = $0 }
                )
            }
            Spacer()
            // Edit project, Invoice and Export CSV used to sit here, three
            // window-level verbs crowded against the name of the thing they
            // act on. They are in the window's toolbar now, which is where
            // macOS keeps commands (HIG: "Toolbars are the secondary command
            // surface after the menu bar"), and it gives this row back to the
            // one thing it should carry: what you are billing.
        }
    }

    /// The window's commands. Icon AND label — HIG asks for both, and a bare
    /// pencil between two worded buttons was a guess for everyone who had
    /// not already learned it.
    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let p = project {
                Button { model.editTarget = p } label: {
                    Label("Edit project", systemImage: "pencil")
                }
                .help("Edit project: rate, budget, currency…")
            }
            InvoiceButton(model: model, inToolbar: true)
            // Export CSV is NOT here. A SwiftUI Menu in a toolbar renders as
            // a control the accessibility audit reports as having no action,
            // and announces itself by its SF Symbol's identifier — no
            // modifier fixes either. It is also the wrong home: a toolbar
            // carries frequent actions, and exporting a spreadsheet is
            // occasional. File ▸ Export CSV is where macOS keeps exports,
            // and that is now the one place it lives.
        }
    }

    // MARK: - Stat rows

    /// Hierarchy: one lead, two supports. The question an editor opens Stats
    /// to answer is a money question — that row gets the size. Time totals
    /// are the evidence behind it, so they sit below at support weight.
    @ViewBuilder
    private func statRows(_ p: Project) -> some View {
        let total = model.store.totalActiveSeconds(for: p) + model.engine.accumulator.activeSeconds
        let days = model.dayTotalsIncludingLive(for: p)
        let dayCount = max(days.count, days.isEmpty && total > 0 ? 1 : days.count)
        // Round each day, then sum — the same order the CSV uses, so the
        // headline figure and the exported total are the same number.
        let earned = days.reduce(0) { $0 + Money.round2($1.earned) }
        // From the same days as `total`. `avgDailySeconds` reads the store
        // alone, so while the clock ran the headline said "27.4 h · 5 days"
        // over an average computed from 27.0 — three figures on one line
        // that did not divide.
        let avg = dayCount > 0 ? total / Double(dayCount) : 0
        let avgEarned = days.isEmpty ? 0 : earned / Double(days.count)

        VStack(spacing: DT.within) {
            if p.mode == .budget {
                budgetRow(p, used: earned)
                summaryLine(total: total, dayCount: dayCount, avg: avg)
                    .padding(.horizontal, DT.s1)
            } else {
                earnedLead(p, earned: earned, total: total, dayCount: dayCount,
                           avg: avg, avgEarned: avgEarned)
            }
        }
    }

    /// Five facts, one line, no boxes.
    ///
    /// These were three cards — EARNED, PROJECT TOTAL, AVG PER DAY — which is
    /// three backgrounds, three borders, three padding boxes and three
    /// label-over-value pairs to carry five numbers. Cards are for things you
    /// act on separately; these are one thought: what the project has earned
    /// and the evidence behind it. Boxes around each made the window read as
    /// a dashboard of unrelated readouts.
    private func summaryLine(total: TimeInterval, dayCount: Int,
                             avg: TimeInterval) -> some View {
        let days = dayCount == 1 ? String(localized: "1 day") : String(localized: "\(dayCount) days")
        return HStack(spacing: DT.within) {
            Text(hours(total)).foregroundStyle(DT.text2)
            Text(verbatim: "·").foregroundStyle(DT.text3)
            Text(days).foregroundStyle(DT.text3)
            if avg > 0 {
                Text(verbatim: "·").foregroundStyle(DT.text3)
                Text("\(hours(avg)) / day").foregroundStyle(DT.text3)
            }
            Spacer(minLength: 0)
        }
        .font(DT.captionMedium)
        .monospacedDigit()
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(hours(total)) over \(days)"))
    }

    /// The lead figure — hourly projects. (Budget projects lead with
    /// `budgetRow`, which already carries the visual weight of its bar.)
    private func earnedLead(_ p: Project, earned: Double, total: TimeInterval,
                            dayCount: Int, avg: TimeInterval, avgEarned: Double) -> some View {
        VStack(alignment: .leading, spacing: DT.s1) {
            Text("EARNED").font(DT.caption).kerning(0.55).foregroundStyle(DT.text3)
            HStack(alignment: .firstTextBaseline, spacing: DT.within) {
                Text(p.currency.formatWhole(earned))
                    .font(DT.statLead).foregroundStyle(DT.text).monospacedDigit()
                Text("@ \(String(format: "%.2f", p.hourlyRate)) / h")
                    .font(DT.captionMedium).foregroundStyle(DT.text3).monospacedDigit()
            }
            summaryLine(total: total, dayCount: dayCount, avg: avg)
                .padding(.top, DT.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .statCard()
        .accessibilityIdentifier("stats.earned")
    }

    @ViewBuilder
    private func budgetRow(_ p: Project, used: Double) -> some View {
        let status = BillingEngine.budgetStatus(usedAmount: used, budget: p.budget)
        let barColor: Color = switch status.warning {
        case .none: DT.signal
        case .warn75: DT.amber
        case .warn90, .over: DT.red
        }
        let forecast = BillingEngine.forecast(
            remaining: status.remaining,
            avgDailySeconds: model.store.avgDailySeconds(for: p),
            hourlyRate: p.hourlyRate,
            daysWorked: model.store.dayTotals(for: p).count
        )

        VStack(spacing: DT.within) {
            HStack(alignment: .firstTextBaseline, spacing: DT.s2) {
                Text("BUDGET").font(DT.caption).kerning(0.55).foregroundStyle(DT.text3)
                Spacer()
                Text("\(p.currency.formatWhole(max(status.remaining, 0))) left")
                    .font(DT.statValue).foregroundStyle(DT.text).monospacedDigit()
                Text("of \(p.currency.formatWhole(p.budget)) · \(Int(status.percentUsed.rounded()))% used")
                    .font(DT.captionMedium).foregroundStyle(DT.text3).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(barColor)
                        .frame(width: geo.size.width * min(status.percentUsed / 100, 1))
                }
            }
            .frame(height: 5)
            if let line = BillingEngine.forecastLine(forecast) {
                Text(line)
                    .font(DT.captionMedium)
                    .foregroundStyle(status.warning == .none ? DT.text3 : DT.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .statCard()
    }

    // MARK: - Daily breakdown

    @ViewBuilder
    private func daysCard(_ p: Project) -> some View {
        let days = model.dayTotalsIncludingLive(for: p)
        let cal = Calendar.current

        VStack(spacing: 0) {
            HStack {
                Text("Daily Breakdown").font(DT.smallSemibold).foregroundStyle(DT.text)
                Spacer()
                Text(rangeLabel(days)).font(DT.captionMedium).foregroundStyle(DT.text3)
                // A SPAN, from the header, for any day.
                //
                // "Add session…" existed only inside an expanded day row, and
                // dayTotals groups the sessions that exist — so a day Cutaway
                // never saw produced no row, could not be expanded, and had no
                // route to the sheet that records a span. "I worked 9:30 to
                // 19:00 on Tuesday" took two passes: invent a day total to
                // conjure the row, expand it, add the real session, then
                // reconcile the two.
                //
                // The sheet's own Day picker was already editable when adding
                // (`.disabled(editing != nil)`), so one entry point that does
                // not depend on an existing row closes the whole gap.
                //
                // A span, not a total, because a span says WHEN — and the day
                // total sheet stays where it was, inside a day that exists,
                // which is the only place replacing a total makes sense.
                Button { model.editSessionTarget = SessionEditTarget(session: nil, day: Date(), project: p) } label: {
                    Label("Add session", systemImage: "plus").labelStyle(.titleAndIcon)
                        .font(DT.captionMedium).foregroundStyle(DT.text2)
                        .padding(.horizontal, DT.within).padding(.vertical, DT.s1)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: DT.rSm))
                }
                .buttonStyle(.plain)
                .help("Record a session on any day — pick the day in the sheet")
                .accessibilityLabel("Add a session on any day")
            }
            .padding(.horizontal, DT.rowInset)
            .padding(.vertical, DT.s3)
            Rectangle().fill(DT.strokeSubtle).frame(height: 1)

            ScrollView {
                VStack(spacing: 0) {
                    let maxDay = days.map(\.activeSeconds).max() ?? 1
                    if days.isEmpty {
                        // A new project renders an empty box otherwise, which
                        // reads as "something failed" rather than "nothing has
                        // happened yet".
                        VStack(spacing: DT.s2) {
                            Text("Nothing tracked yet")
                                .font(DT.smallSemibold).foregroundStyle(DT.text2)
                            Text("Open this project in Resolve and the clock starts on its own. Days you worked before Cutaway can be typed in.")
                                .font(DT.captionMedium).foregroundStyle(DT.text3)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 300)
                            Button("Set a day's total…") {
                                model.editDay = DayEditTarget(day: nil, project: p)
                            }
                            .buttonStyle(DayActionButtonStyle())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DT.s5)
                    }
                    ForEach(days, id: \.day) { d in
                        let isToday = cal.isDateInToday(d.day)
                        dayRow(d, project: p, isToday: isToday, maxSeconds: maxDay)
                        if expandedDay == d.day {
                            sessionDetail(d, project: p, isToday: isToday)
                        }
                    }
                }
            }
            // Today, already open. The strip is the best thing in the window
            // and it sat behind a disclosure nobody had a reason to click —
            // so a third of the Stats window was empty on every launch while
            // its most useful view stayed hidden.
            .onAppear {
                if expandedDay == nil, let today = days.first(where: { cal.isDateInToday($0.day) }) {
                    expandedDay = today.day
                }
            }

            Spacer(minLength: 0)
            // The footer that stood here said "5 days · 27.4 h active" and
            // "Total CHF 2'329.00" — the same two figures as the PROJECT
            // TOTAL and EARNED cards at the top of the same window, a
            // hundred points away. Restating a number does not reinforce it;
            // it makes the reader check whether the two agree.
        }
        .background(DT.card)
        .clipShape(RoundedRectangle(cornerRadius: DT.rLg))
        .overlay(RoundedRectangle(cornerRadius: DT.rLg).stroke(DT.strokeSubtle, lineWidth: 1))
        .frame(maxHeight: .infinity)
    }

    /// Click unfolds the day into its sessions; editing lives in the unfolded
    /// detail and in the row's context menu.
    private func dayRow(_ d: DayTotal, project p: Project, isToday: Bool, maxSeconds: TimeInterval) -> some View {
        Button {
            expandedDay = expandedDay == d.day ? nil : d.day
        } label: {
        HStack(spacing: DT.s3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                (isToday ? Text("Today") : Text(verbatim: d.day.formatted(.dateTime.month(.abbreviated).day())))
                    .font(DT.small)
                    .foregroundStyle(isToday ? DT.signal : DT.textPrimary)
                Text(d.day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(DT.captionMedium).foregroundStyle(DT.text3)
            }
            // Was a fixed 82pt: a wider window should give the date more
            // room, not leave it truncated beside empty space.
            .frame(minWidth: 82, alignment: .leading)
            Text(String(format: "%.1fh", d.activeSeconds / 3600))
                .font(DT.small).foregroundStyle(DT.text2).monospacedDigit()
            if d.adjustedSeconds > 0 {
                Image(systemName: "pencil")
                    .font(DT.glyph)
                    .foregroundStyle(DT.text3)
                    .help("Includes manual adjustment")
                    .accessibilityLabel("includes manual adjustment")
            }
            // A day on an issued invoice cannot be edited. Saying so here is
            // cheaper than letting someone try and meet a refusal.
            if let number = model.invoiceNumber(for: d.day, project: p) {
                Image(systemName: "lock.fill")
                    .font(DT.glyph)
                    .foregroundStyle(DT.text3)
                    .help("On invoice \(number)")
                    .accessibilityHidden(true)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(DT.signal.opacity(0.75))
                        .frame(width: geo.size.width * (maxSeconds > 0 ? d.activeSeconds / maxSeconds : 0))
                }
            }
            .frame(height: 5)
            Text(p.currency.format(d.earned))
                .font(DT.smallBold)
                .foregroundStyle(DT.text)
                .monospacedDigit()
                .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.vertical, DT.within)
        .padding(.leading, isToday ? 12 : 14)
        .padding(.trailing, DT.s4)
        .background(isToday ? DT.signal.opacity(0.06) : .clear)
        .overlay(alignment: .leading) {
            if isToday { Rectangle().fill(DT.signal).frame(width: 2) }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
        }
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A label on a container REPLACES everything inside it. This one said
        // "Show sessions" over a row containing a date, hours and an amount —
        // so the whole daily ledger, the thing a client's money depends on,
        // announced the same four words thirty times.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.dayRowLabel(d, project: p, isToday: isToday,
                                             invoice: model.invoiceNumber(for: d.day, project: p)))
        .accessibilityHint(expandedDay == d.day ? "Hide sessions" : "Show sessions")
        .contextMenu {
            if let number = model.invoiceNumber(for: d.day, project: p) {
                Text("On invoice \(number)")
            } else {
                Button("Set day total…") { model.editDay = DayEditTarget(day: d.day, project: p) }
            }
        }
        .accessibilityAddTraits(.isButton)
    }

    /// The day, unfolded into a strip you can grab. The list of rows this
    /// replaced could say what happened but not WHERE the gaps were, and the
    /// gap is the thing an editor argues with.
    @ViewBuilder
    private func sessionDetail(_ d: DayTotal, project p: Project, isToday: Bool) -> some View {
        let sessions = model.store.sessions(for: p, on: d.day)
        VStack(spacing: 0) {
            DayTimelineView(
                model: model, project: p, day: d.day, sessions: sessions,
                // The running session belongs to the SELECTED project, and to
                // no other. Without this guard, switching the Stats view to
                // another client and expanding today drew a green "running"
                // block, listed it as a session, and folded it into that
                // day's gap arithmetic — while the collapsed day row directly
                // above said 0:00, because `dayTotalsIncludingLive` has the
                // guard. Two figures for one day, one of them another
                // client's time.
                live: isToday && p.persistentModelID == model.selectedProjectID
                    && model.engine.accumulator.activeSeconds > 0
                    ? model.engine.accumulator.sessionStart.map { ($0, model.engine.accumulator.activeSeconds) }
                    : nil)
            if sessions.isEmpty {
                Text("No sessions on this day")
                    .font(DT.captionMedium).foregroundStyle(DT.text3)
                    .padding(.bottom, DT.s2)
            }
            HStack {
                Spacer()
                // A day an invoice claims is not editable, and the row's own
                // context menu has always known that — it shows "On invoice
                // …" instead of the button. The panel underneath it offered
                // both buttons anyway, so the row drew a padlock and then
                // handed over two ways to try. Both ended in a refusal, and
                // "Set day total…" ended in a refusal that told the owner to
                // pause a timer.
                if let number = model.invoiceNumber(for: d.day, project: p) {
                    Text("On invoice \(number) — void it to make changes")
                        .font(DT.captionMedium).foregroundStyle(DT.text3)
                } else {
                    Button("Add session…") {
                        model.editSessionTarget = SessionEditTarget(session: nil, day: d.day, project: p)
                    }
                    .buttonStyle(DayActionButtonStyle())
                    Button("Set day total…") { model.editDay = DayEditTarget(day: d.day, project: p) }
                        .buttonStyle(DayActionButtonStyle())
                }
            }
            .padding(.horizontal, DT.rowInset)
            .padding(.bottom, DT.s2)
        }
        .background(Color.white.opacity(0.02))
    }



    static func dayRowLabel(_ d: DayTotal, project p: Project, isToday: Bool,
                            invoice: String? = nil) -> String {
        let day = isToday ? "Today" : d.day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let worked = PillView.spokenDuration(d.activeSeconds)
        let base = "\(day), \(worked), \(p.currency.format(d.earned))"
        // The lock is drawn as a glyph; without this a VoiceOver user meets
        // the refusal instead of the reason.
        return invoice.map { "\(base), on invoice \($0)" } ?? base
    }

    private func hours(_ t: TimeInterval) -> String {
        String(format: "%.1f h", t / 3600)
    }

    private func rangeLabel(_ days: [DayTotal]) -> String {
        guard let last = days.last?.day, let first = days.first?.day else { return "—" }
        let f = Date.FormatStyle().month(.abbreviated).day()
        return "\(last.formatted(f)) – \(first.formatted(f)), \(Calendar.current.component(.year, from: first))"
    }
}

/// The small actions under an unfolded day. They were bare tinted text,
/// which reads as a label rather than something to press — the same
/// complaint that the prompt card's actions drew.
struct DayActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DT.captionMedium)
            .foregroundStyle(configuration.isPressed ? DT.text : DT.text2)
            .padding(.horizontal, DT.s3)
            .padding(.vertical, 4)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08),
                        in: RoundedRectangle(cornerRadius: DT.rSm))
            .contentShape(RoundedRectangle(cornerRadius: DT.rSm))
    }
}

/// One card treatment, defined once — the stat cards drifted apart every
/// time one of them was edited in isolation.
private extension View {
    func statCard() -> some View {
        self
            .padding(.horizontal, DT.rowInset)
            .padding(.vertical, DT.s3)
            .background(DT.card, in: RoundedRectangle(cornerRadius: DT.rLg))
            .overlay(RoundedRectangle(cornerRadius: DT.rLg).stroke(DT.strokeSubtle, lineWidth: 1))
            // A card is one fact — "CHF 1'240 · 14 h this month" — so it
            // reads as one thing. Unlabelled card containers were the last
            // real finding of the accessibility audit on 2026-09-08.
            .accessibilityElement(children: .combine)
    }
}

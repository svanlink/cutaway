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
                Spacer()
                Text("Create a project to see stats")
                    .font(DT.body)
                    .foregroundStyle(DT.text3)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, DT.s4)
    }

    // MARK: - Header (title = switcher)

    private var header: some View {
        HStack(spacing: DT.s2) {
            Button { switcherOpen.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: DT.s2) {
                    Text(project?.name ?? "No project")
                        .font(DT.title)
                        .foregroundStyle(DT.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        // The name is the header; the client and the icon
                        // row yield to it when the window is at its minimum.
                        .layoutPriority(1)
                    if let c = project?.client, !c.isEmpty {
                        Text("· \(c)")
                            .font(DT.captionMedium)
                            .foregroundStyle(DT.text3)
                            .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    }
                    Text("▼").font(DT.glyphLight).foregroundStyle(DT.text3)
                    if let p = project, !p.appBundleIDs.isEmpty {
                        AppIconRow(prefixes: p.appBundleIDs, installed: model.installedApps, size: 16)
                            .padding(.leading, 4)
                    }
                }
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
            if let p = project {
                // Visible affordance — a context menu alone is a secret.
                Button { model.editTarget = p } label: {
                    Image(systemName: "pencil")
                        .font(DT.glyph)
                        .foregroundStyle(DT.text2)
                        .frame(width: 28, height: 26)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: DT.rSm))
                }
                .buttonStyle(.plain)
                .help("Edit project: rate, budget, currency…")
                .accessibilityLabel("Edit project")
            }
            InvoiceButton(model: model)
            CSVExportButton(model: model)
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
        let avg = model.store.avgDailySeconds(for: p)
        let avgEarned = days.isEmpty ? 0 : earned / Double(days.count)

        VStack(spacing: DT.s2) {
            if p.mode == .budget {
                budgetRow(p, used: earned)
            } else {
                earnedLead(p, earned: earned)
            }
            HStack(spacing: DT.s2) {
                supportStat(key: "PROJECT TOTAL", value: hours(total),
                            sub: dayCount == 1 ? String(localized: "1 day") : String(localized: "\(dayCount) days"))
                supportStat(key: "AVG PER DAY", value: hours(avg),
                            sub: avg > 0
                                ? String(localized: "\(p.currency.formatWhole(avgEarned)) / day")
                                : "—")
            }
        }
    }

    /// The lead figure — hourly projects. (Budget projects lead with
    /// `budgetRow`, which already carries the visual weight of its bar.)
    private func earnedLead(_ p: Project, earned: Double) -> some View {
        VStack(alignment: .leading, spacing: DT.s1) {
            Text("EARNED").font(DT.caption).kerning(0.55).foregroundStyle(DT.text3)
            HStack(alignment: .firstTextBaseline, spacing: DT.s2) {
                Text(p.currency.formatWhole(earned))
                    .font(DT.statLead).foregroundStyle(DT.text).monospacedDigit()
                Text("@ \(String(format: "%.2f", p.hourlyRate)) / h")
                    .font(DT.captionMedium).foregroundStyle(DT.text3).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .statCard()
        .accessibilityIdentifier("stats.earned")
    }

    /// Supporting figure — stacked, half width, one step down in type.
    private func supportStat(key: LocalizedStringKey, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: DT.s1) {
            Text(key).font(DT.caption).kerning(0.55).foregroundStyle(DT.text3)
            Text(value).font(DT.statValue).foregroundStyle(DT.text).monospacedDigit()
            Text(sub).font(DT.captionMedium).foregroundStyle(DT.text3).monospacedDigit()
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .statCard()
        .accessibilityIdentifier("stats.support")
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

        VStack(spacing: 6) {
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
        let total = days.reduce(0.0) { $0 + $1.activeSeconds }
        let cal = Calendar.current

        VStack(spacing: 0) {
            HStack {
                Text("Daily Breakdown").font(DT.smallSemibold).foregroundStyle(DT.text)
                Spacer()
                Text(rangeLabel(days)).font(DT.captionMedium).foregroundStyle(DT.text3)
                Button { model.editDay = DayEditTarget(day: nil, project: p) } label: {
                    Text("＋ Add").font(DT.captionMedium).foregroundStyle(DT.text2)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: DT.rSm))
                }
                .buttonStyle(.plain)
                .help("Add time for a day")
                .accessibilityLabel("Add time for a day")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            Rectangle().fill(DT.strokeSubtle).frame(height: 1)

            ScrollView {
                VStack(spacing: 0) {
                    let maxDay = days.map(\.activeSeconds).max() ?? 1
                    ForEach(days, id: \.day) { d in
                        let isToday = cal.isDateInToday(d.day)
                        dayRow(d, project: p, isToday: isToday, maxSeconds: maxDay)
                        if expandedDay == d.day {
                            sessionDetail(d, project: p, isToday: isToday)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            Rectangle().fill(DT.strokeSubtle).frame(height: 1)
            HStack {
                (Text("\(days.count) days").font(DT.captionMedium).foregroundStyle(DT.text)
                 + Text(" · ").foregroundStyle(DT.text2)
                 + Text(hours(total)).font(DT.captionMedium).foregroundStyle(DT.text)
                 + Text(" active").foregroundStyle(DT.text2))
                    .font(DT.captionMedium)
                Spacer()
                Text("Total  \(p.currency.format(days.reduce(0) { $0 + $1.earned }))")
                    .font(DT.bodyBold).foregroundStyle(DT.text).monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
        .padding(.vertical, 8)
        .padding(.leading, isToday ? 12 : 14)
        .padding(.trailing, 14)
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
                Button("Edit day…") { model.editDay = DayEditTarget(day: d.day, project: p) }
            }
        }
        .accessibilityAddTraits(.isButton)
    }

    /// The sessions behind one day. The breakdown row is a claim; this is the
    /// itemisation that backs it — the same thing the CSV would show a client.
    @ViewBuilder
    private func sessionDetail(_ d: DayTotal, project p: Project, isToday: Bool) -> some View {
        let sessions = model.store.sessions(for: p, on: d.day)
        let live = isToday ? model.engine.accumulator.activeSeconds : 0
        VStack(spacing: 0) {
            ForEach(sessions, id: \.persistentModelID) { s in
                Button {
                    model.editSessionTarget = SessionEditTarget(session: s, day: d.day, project: p)
                } label: {
                    sessionLine(range: AppModel.sessionTimeRange(start: s.start, end: s.end),
                                seconds: s.activeSeconds,
                                earned: s.earned(projectRate: p.hourlyRate),
                                project: p, isLive: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.sessionRowLabel(s, project: p))
                .accessibilityHint("Edit this session")
            }
            // A day row that includes the running accumulator must itemise it,
            // or the parts visibly fail to add up to the total above them.
            if live > 0, let started = model.engine.accumulator.sessionStart {
                sessionLine(range: AppModel.sessionTimeRange(start: started, end: Date()),
                            seconds: live,
                            earned: BillingEngine.earnings(activeSeconds: live,
                                                           hourlyRate: p.hourlyRate),
                            project: p, isLive: true)
            }
            HStack {
                Spacer()
                Button("Add session…") {
                    model.editSessionTarget = SessionEditTarget(session: nil, day: d.day, project: p)
                }
                    .font(DT.captionMedium)
                    .buttonStyle(.plain)
                    .foregroundStyle(DT.signal)
                Button("Edit day…") { model.editDay = DayEditTarget(day: d.day, project: p) }
                    .font(DT.captionMedium)
                    .buttonStyle(.plain)
                    .foregroundStyle(DT.signal)
                    .accessibilityLabel("Edit \(isToday ? "today" : d.day.formatted(.dateTime.month(.abbreviated).day()))")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .padding(.leading, DT.s5)
        .padding(.trailing, DT.rowInset)
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
        }
    }

    private func sessionLine(range: String, seconds: TimeInterval, earned: Double,
                             project p: Project, isLive: Bool) -> some View {
        HStack(spacing: DT.s3) {
            Text(range)
                .font(DT.captionMedium)
                .foregroundStyle(isLive ? DT.recording : DT.textSecondary)
                .monospacedDigit()
            if isLive {
                Text("running").font(DT.tag).foregroundStyle(DT.recording)
            }
            Spacer(minLength: DT.s2)
            Text(String(format: "%.1fh", seconds / 3600))
                .font(DT.captionMedium).foregroundStyle(DT.text3).monospacedDigit()
            Text(p.currency.format(earned))
                .font(DT.captionMedium).foregroundStyle(DT.text2).monospacedDigit()
                .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.vertical, DT.s1)
    }

    /// What VoiceOver hears for one day of the ledger. Pure, so the claim
    /// "every row states its own figures" is testable without a screen reader.
    static func sessionRowLabel(_ s: WorkSession, project p: Project) -> String {
        let range = AppModel.sessionTimeRange(start: s.start, end: s.end)
        let worked = PillView.spokenDuration(s.activeSeconds)
        let entered = s.isAdjusted ? String(localized: ", entered by hand") : ""
        return "\(range), \(worked), \(p.currency.format(s.earned(projectRate: p.hourlyRate)))\(entered)"
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

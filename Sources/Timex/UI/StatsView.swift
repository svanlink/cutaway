import SwiftUI

/// View 2 — stats: title switcher, stat rows, daily breakdown, CSV export.
struct StatsView: View {
    @Bindable var model: AppModel
    @State private var switcherOpen = false

    private var project: Project? { model.selectedProject }

    var body: some View {
        VStack(spacing: DT.s3) {
            header
            if let p = project {
                statRows(p)
                daysCard(p)
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
                    if let c = project?.client, !c.isEmpty {
                        Text("· \(c)")
                            .font(DT.captionMedium)
                            .foregroundStyle(DT.text3)
                            .lineLimit(1)
                    }
                    Text("▼").font(.system(size: 9)).foregroundStyle(DT.text3)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $switcherOpen, arrowEdge: .bottom) {
                SwitcherList(
                    projects: model.projects,
                    currentID: model.selectedProjectID,
                    select: { model.select($0); switcherOpen = false },
                    newProject: { switcherOpen = false; model.showNewProjectSheet = true },
                    onRename: { switcherOpen = false; model.renameTarget = $0 },
                    onDelete: { switcherOpen = false; model.deleteTarget = $0 }
                )
            }
            Spacer()
            CSVExportButton(model: model)
        }
    }

    // MARK: - Stat rows

    @ViewBuilder
    private func statRows(_ p: Project) -> some View {
        let total = model.store.totalActiveSeconds(for: p) + model.engine.accumulator.activeSeconds
        let days = model.dayTotalsIncludingLive(for: p)
        let dayCount = max(days.count, days.isEmpty && total > 0 ? 1 : days.count)
        let earned = BillingEngine.earnings(activeSeconds: total, hourlyRate: p.hourlyRate)

        VStack(spacing: DT.s2) {
            statRow(key: "PROJECT TOTAL", value: hours(total), sub: "· \(dayCount) day\(dayCount == 1 ? "" : "s")")
            statRow(key: p.mode == .budget ? "USED" : "EARNED",
                    value: p.currency.formatWhole(earned),
                    sub: "@ \(String(format: "%.2f", p.hourlyRate)) / h")
            if p.mode == .budget {
                budgetRow(p, used: earned)
            } else {
                let avg = model.store.avgDailySeconds(for: p)
                statRow(key: "AVG PER DAY", value: hours(avg),
                        sub: avg > 0 ? "\(p.currency.formatWhole(BillingEngine.earnings(activeSeconds: avg, hourlyRate: p.hourlyRate))) / day" : "—")
            }
        }
    }

    private func statRow(key: String, value: String, sub: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DT.s2) {
            Text(key).font(DT.caption).kerning(0.55).foregroundStyle(DT.text3)
            Spacer()
            Text(value).font(DT.statValue).foregroundStyle(DT.text).monospacedDigit()
            Text(sub).font(DT.captionMedium).foregroundStyle(DT.text3).monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DT.card, in: RoundedRectangle(cornerRadius: DT.rLg))
        .overlay(RoundedRectangle(cornerRadius: DT.rLg).stroke(DT.strokeSubtle, lineWidth: 1))
    }

    @ViewBuilder
    private func budgetRow(_ p: Project, used: Double) -> some View {
        let status = BillingEngine.budgetStatus(usedAmount: used, budget: p.budget)
        let barColor: Color = switch status.warning {
        case .none: DT.orange
        case .warn75: DT.amber
        case .warn90, .over: DT.red
        }
        let forecast = BillingEngine.forecastDaysLeft(
            remaining: status.remaining,
            avgDailySeconds: model.store.avgDailySeconds(for: p),
            hourlyRate: p.hourlyRate
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
            if let f = forecast {
                Text("≈ \(String(format: "%.1f", f)) working days left at current pace")
                    .font(DT.captionMedium)
                    .foregroundStyle(status.warning == .none ? DT.text3 : DT.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DT.card, in: RoundedRectangle(cornerRadius: DT.rLg))
        .overlay(RoundedRectangle(cornerRadius: DT.rLg).stroke(DT.strokeSubtle, lineWidth: 1))
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
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            Rectangle().fill(DT.strokeSubtle).frame(height: 1)

            ScrollView {
                VStack(spacing: 0) {
                    let maxDay = days.map(\.activeSeconds).max() ?? 1
                    ForEach(days, id: \.day) { d in
                        dayRow(d, project: p, isToday: cal.isDateInToday(d.day), maxSeconds: maxDay)
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
                Text("Total  \(p.currency.format(BillingEngine.earnings(activeSeconds: total, hourlyRate: p.hourlyRate)))")
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

    private func dayRow(_ d: DayTotal, project p: Project, isToday: Bool, maxSeconds: TimeInterval) -> some View {
        HStack(spacing: DT.s3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(isToday ? "Today" : d.day.formatted(.dateTime.month(.abbreviated).day()))
                    .font(DT.small)
                    .foregroundStyle(isToday ? DT.orange : DT.text)
                Text(d.day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(DT.captionMedium).foregroundStyle(DT.text3)
            }
            .frame(width: 82, alignment: .leading)
            Text(String(format: "%.1fh", d.activeSeconds / 3600))
                .font(DT.small).foregroundStyle(DT.text2).monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(DT.orange.opacity(0.85))
                        .frame(width: geo.size.width * (maxSeconds > 0 ? d.activeSeconds / maxSeconds : 0))
                }
            }
            .frame(height: 5)
            Text(p.currency.format(BillingEngine.earnings(activeSeconds: d.activeSeconds, hourlyRate: p.hourlyRate)))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DT.text)
                .monospacedDigit()
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.leading, isToday ? 12 : 14)
        .padding(.trailing, 14)
        .background(isToday ? DT.orange.opacity(0.05) : .clear)
        .overlay(alignment: .leading) {
            if isToday { Rectangle().fill(DT.orange).frame(width: 2) }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
        }
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

import SwiftUI

/// A day as a strip you can grab.
///
/// This is the removed reclaim prompt's replacement: the gap is VISIBLE, and
/// dragging an edge over it is how you claim it — no prompt, no guess, and a
/// trace on whatever you change. The strip is for the gesture; the sheet is
/// for the number.
struct DayTimelineView: View {
    @Bindable var model: AppModel
    let project: Project
    let day: Date
    let sessions: [WorkSession]
    /// The running session, drawn but never draggable.
    let live: (start: Date, seconds: TimeInterval)?

    @State private var selected: String?
    @State private var dragging: Drag?
    @State private var hovered: String?

    private static let height: CGFloat = 44
    private static let minimumBlock: CGFloat = 6

    private struct Drag {
        let id: String
        let edge: Edge
        var start: Date
        var end: Date
        enum Edge { case body, leading, trailing }
    }

    private var blocks: [DayTimeline.Block] {
        var result = sessions.enumerated().map { index, session in
            // Position within the day, which is stable for as long as the
            // strip is on screen and unique per row — unlike the store
            // identifier, which is one value for the whole file.
            DayTimeline.Block(id: Self.blockID(session, index: index),
                              start: session.start, end: session.end,
                              activeSeconds: session.activeSeconds,
                              isAdjusted: session.isAdjusted)
        }
        if let live {
            result.append(DayTimeline.Block(id: "live", start: live.start, end: Date(),
                                            activeSeconds: live.seconds, isAdjusted: false,
                                            isLive: true))
        }
        return result.sorted { $0.start < $1.start }
    }

    private var timeline: DayTimeline {
        let b = blocks
        let domain = DayTimeline.domain(for: b, on: day)
        return DayTimeline(start: domain.start, end: domain.end, blocks: b)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let t = timeline
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: DT.rMd).fill(DT.card2)
                    ForEach(t.blocks) { block in
                        blockView(block, timeline: t, width: geo.size.width)
                    }
                    // ABOVE the blocks, not beneath them. A full day is one
                    // block covering the whole track, and ticks underneath it
                    // vanish precisely when the strip most needs to say what
                    // hour anything happened at.
                    ticks(t, width: geo.size.width)
                }
            }
            .frame(height: Self.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Day timeline")
            caption
        }
        .padding(.horizontal, 14)
        .padding(.bottom, DT.s2)
    }

    // MARK: - Pieces

    private func ticks(_ t: DayTimeline, width: CGFloat) -> some View {
        ForEach(t.ticks(), id: \.self) { tick in
            let x = CGFloat(t.fraction(of: tick)) * width
            ZStack(alignment: .topLeading) {
                // Dark enough to read over a filled block, light enough to
                // stay out of the way over an empty track.
                Rectangle().fill(Color.black.opacity(0.28))
                    .frame(width: 1, height: Self.height)
                    .offset(x: x)
                Text(tick.formatted(.dateTime.hour()))
                    .font(DT.tag)
                    .foregroundStyle(DT.text2)
                    .shadow(color: .black.opacity(0.55), radius: 1.5)
                    .offset(x: x + 3, y: 1)
            }
        }
        .allowsHitTesting(false)      // the axis is scenery; blocks take the clicks
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func blockView(_ block: DayTimeline.Block, timeline t: DayTimeline, width: CGFloat) -> some View {
        let shown = dragging?.id == block.id
            ? DayTimeline.Block(id: block.id, start: dragging!.start, end: dragging!.end,
                                activeSeconds: block.activeSeconds, isAdjusted: block.isAdjusted,
                                isLive: block.isLive)
            : block
        // Typed time has no span and must not pretend to one: a fixed, hatched
        // width says "entered" rather than drawing an hour nobody sat through.
        let isTyped = shown.isAdjusted && shown.span < 60
        let x = CGFloat(t.fraction(of: shown.start)) * width
        let w = isTyped ? 24 : max(CGFloat(t.fraction(of: shown.end) - t.fraction(of: shown.start)) * width,
                                   Self.minimumBlock)

        RoundedRectangle(cornerRadius: 3)
            .fill(fill(shown, typed: isTyped))
            .frame(width: w, height: Self.height - 14)
            .overlay {
                if isTyped {
                    Image(systemName: "pencil").font(DT.tag).foregroundStyle(DT.text)
                }
            }
            .overlay {
                if selected == block.id {
                    RoundedRectangle(cornerRadius: 3).stroke(DT.signal, lineWidth: 1.5)
                }
            }
            .offset(x: x, y: 7)
            .onHover { hovered = $0 ? block.id : (hovered == block.id ? nil : hovered) }
            .help(tooltip(shown))
            .gesture(shown.isLive ? nil : drag(block, timeline: t, width: width))
            .onTapGesture(count: 2) { edit(block) }
            .onTapGesture { selected = block.id }
            .contextMenu { menu(block) }
            .accessibilityElement()
            .accessibilityLabel(spoken(shown))
            .accessibilityAddTraits(.isButton)
            // The DEFAULT action, not only the named ones. The trait above
            // promises something activatable, and VoiceOver's activate did
            // nothing — the audit calls this "Action is missing". It went
            // unseen because the strip only appeared after expanding a day,
            // so the audit never had a block on screen until today opened by
            // default. Mirrors the single click: select the block.
            .accessibilityAction { selected = block.id }
            .accessibilityAction(named: Text("Edit")) { edit(block) }
            .accessibilityAction(named: Text("Split in the middle")) { split(block, at: middle(shown)) }
            .accessibilityAction(named: Text("Delete")) { delete(block) }
    }

    /// Three meanings, three fills — and only one of them is green.
    ///
    /// The strip used to paint every recorded block with DT.recording, the
    /// colour that means "the clock is running now", while the day bars two
    /// rows above painted the same quantity with DT.signal. The same thing in
    /// two colours, and green spent on work that finished hours ago — so when
    /// something WAS running there was nothing left to say it with.
    ///
    /// Worked time is DT.signal, like every other worked-time figure in the
    /// app. Green now means exactly one thing: this block is growing as you
    /// look at it. Typed time stays grey, because it was not observed.
    private func fill(_ block: DayTimeline.Block, typed: Bool) -> AnyShapeStyle {
        if typed { return AnyShapeStyle(DT.text3.opacity(0.35)) }
        if block.isLive { return AnyShapeStyle(DT.recording) }
        let strong = hovered == block.id || selected == block.id
        return AnyShapeStyle(DT.signal.opacity(strong ? 1 : 0.8))
    }

    private var caption: some View {
        let s = DayTimeline.summary(blocks)
        return Text(Self.captionText(sessions: s.sessions, tracked: s.tracked, gaps: s.gaps))
            .font(DT.tag).foregroundStyle(DT.text3).monospacedDigit()
    }

    /// "1 session", not "1 sessions".
    static func captionText(sessions: Int, tracked: TimeInterval, gaps: TimeInterval) -> String {
        let count = sessions == 1
            ? String(localized: "1 session")
            : String(localized: "\(sessions) sessions")
        let worked = String(localized: "\(AppModel.hoursText(tracked)) tracked")
        guard gaps > 0 else { return "\(count) · \(worked)" }
        return "\(count) · \(worked) · \(AppModel.hoursText(gaps)) in gaps"
    }

    // MARK: - Gestures

    private func drag(_ block: DayTimeline.Block, timeline t: DayTimeline, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let seconds = Double(value.translation.width / width) * t.duration
                // Five minutes by default; ⌥ for one. A drag landing on
                // 11:37:42 is noise recorded as precision.
                let step = NSEvent.modifierFlags.contains(.option) ? 1 : 5
                let edge: Drag.Edge = value.startLocation.x < 8 ? .leading
                    : (value.startLocation.x > width - 8 ? .trailing : .body)
                var start = block.start, end = block.end
                switch edge {
                case .body:
                    // A move corrects WHEN, never how much.
                    start = DayTimeline.snap(block.start.addingTimeInterval(seconds), toMinutes: step)
                    end = start.addingTimeInterval(block.span)
                case .leading:
                    start = min(DayTimeline.snap(block.start.addingTimeInterval(seconds), toMinutes: step),
                                block.end.addingTimeInterval(-300))
                case .trailing:
                    end = max(DayTimeline.snap(block.end.addingTimeInterval(seconds), toMinutes: step),
                              block.start.addingTimeInterval(300))
                }
                dragging = Drag(id: block.id, edge: edge, start: start, end: end)
            }
            .onEnded { _ in
                defer { dragging = nil }
                guard let d = dragging, let session = session(for: block.id) else { return }
                model.storeErrors.attempt("save the change") {
                    try model.editSession(session, from: d.start, to: d.end, in: project)
                }
            }
    }

    // MARK: - Actions

    /// Start time plus index: two sessions cannot share both.
    static func blockID(_ session: WorkSession, index: Int) -> String {
        "\(index)-\(session.start.timeIntervalSinceReferenceDate)"
    }

    private func session(for id: String) -> WorkSession? {
        sessions.enumerated()
            .first { Self.blockID($0.element, index: $0.offset) == id }?
            .element
    }

    private func middle(_ block: DayTimeline.Block) -> Date {
        block.start.addingTimeInterval(block.span / 2)
    }

    private func edit(_ block: DayTimeline.Block) {
        guard let s = session(for: block.id) else { return }
        model.editSessionTarget = SessionEditTarget(session: s, day: day, project: project)
    }

    private func split(_ block: DayTimeline.Block, at moment: Date) {
        guard let s = session(for: block.id) else { return }
        model.storeErrors.attempt("split the session") {
            try model.splitSession(s, at: moment, in: project)
        }
    }

    private func delete(_ block: DayTimeline.Block) {
        guard let s = session(for: block.id) else { return }
        model.storeErrors.attempt("delete the session") {
            try model.deleteSession(s, in: project)
        }
    }

    @ViewBuilder
    private func menu(_ block: DayTimeline.Block) -> some View {
        if !block.isLive {
            Button("Edit…") { edit(block) }
            Button("Split in the middle") { split(block, at: middle(block)) }
            if model.projects.count > 1 {
                Menu("Assign to") {
                    ForEach(model.projects.filter { $0.persistentModelID != project.persistentModelID },
                            id: \.persistentModelID) { target in
                        Button(target.name) { assign(block, to: target) }
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) { delete(block) }
        }
    }

    private func assign(_ block: DayTimeline.Block, to target: Project) {
        guard let s = session(for: block.id) else { return }
        model.storeErrors.attempt("move the session") {
            try model.reassignSession(s, from: project, to: target)
        }
    }

    // MARK: - Words

    private func tooltip(_ block: DayTimeline.Block) -> String {
        let range = AppModel.sessionTimeRange(start: block.start, end: block.end)
        let money = project.currency.format(BillingEngine.earnings(
            activeSeconds: block.activeSeconds, hourlyRate: project.hourlyRate))
        let idle = block.idleSeconds > 60
            ? String(localized: " · \(AppModel.hoursText(block.idleSeconds)) idle excluded") : ""
        return "\(range) · \(AppModel.hoursText(block.activeSeconds)) · \(money)\(idle)"
    }

    private func spoken(_ block: DayTimeline.Block) -> String {
        let range = AppModel.sessionTimeRange(start: block.start, end: block.end)
        let worked = PillView.spokenDuration(block.activeSeconds)
        let money = project.currency.format(BillingEngine.earnings(
            activeSeconds: block.activeSeconds, hourlyRate: project.hourlyRate))
        let kind = block.isLive ? String(localized: ", running")
            : (block.isAdjusted ? String(localized: ", entered by hand") : String(localized: ", tracked"))
        return "\(range), \(worked), \(money)\(kind)"
    }
}

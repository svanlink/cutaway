import SwiftUI

/// The hero ring: progress toward the daily goal, money in the center.
/// Recording = orange + glow · paused = gray, no glow · goal reached = green.
struct RingView: View {
    let elapsed: TimeInterval
    let money: String
    let goal: BillingEngine.GoalProgress
    let goalHours: Double
    let isPaused: Bool

    private var ringColor: Color {
        if isPaused { return DT.ringPaused }
        return goal.reached ? DT.green : DT.orange
    }
    private var glow: Color {
        if isPaused { return .clear }
        return (goal.reached ? DT.green : DT.orange).opacity(0.55)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(DT.ringTrack, style: StrokeStyle(lineWidth: 18))
            Circle()
                .trim(from: 0, to: max(goal.fraction, 0.004))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: glow, radius: 6)
                .animation(.easeOut(duration: 0.3), value: goal.fraction)

            VStack(spacing: 3) {
                Text("TODAY")
                    .font(DT.caption)
                    .kerning(0.55)
                    .foregroundStyle(DT.text3)
                elapsedText
                Text(money)
                    .font(DT.money)
                    .foregroundStyle(isPaused ? DT.text2 : DT.orange)
                    .monospacedDigit()
                Text(goalLine)
                    .font(DT.captionMedium)
                    .foregroundStyle(goal.reached && !isPaused ? DT.green : DT.text3)
                    .monospacedDigit()
            }
            .padding(.horizontal, 30)
        }
        .frame(width: 240, height: 240)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today \(timeString(elapsed)) recorded, \(money) earned")
    }

    private var elapsedText: some View {
        let s = Int(elapsed)
        let main = String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
        let sec = String(format: ":%02d", s % 60)
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(main).font(DT.hero).foregroundStyle(DT.text)
            Text(sec).font(DT.heroSec).foregroundStyle(DT.text2)
        }
        .monospacedDigit()
    }

    private var goalLine: String {
        if goal.reached {
            let ot = Int(goal.overtimeSeconds)
            return String(format: "Goal ✓ · +%d:%02d", ot / 3600, (ot % 3600) / 60)
        }
        return "\(Int((goal.fraction * 100).rounded()))% of \(Int(goalHours))h"
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return "\(s / 3600) hours \((s % 3600) / 60) minutes"
    }
}

import AppIntents
import Foundation

/// The sentences the intents hand back — pure, so a test can pin them.
enum IntentText {
    static func today(seconds: TimeInterval, money: String, project: String?) -> String {
        guard let project else { return String(localized: "No project selected") }
        return String(localized: "\(PillView.spokenDuration(seconds)) today on \(project) — \(money)")
    }
}

struct PauseTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Cutaway"
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult {
        if let m = AppDelegate.model, !m.engine.manuallyPaused { m.engine.togglePause() }
        return .result()
    }
}

struct ResumeTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Cutaway"
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult {
        AppDelegate.model?.engine.resume()
        return .result()
    }
}

struct TodayTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Time in Cutaway"
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let m = AppDelegate.model
        let s = IntentText.today(seconds: m?.todaySeconds ?? 0, money: m?.todayMoney ?? "—",
                                 project: m?.selectedProject?.name)
        return .result(value: s, dialog: IntentDialog(stringLiteral: s))
    }
}

struct SwitchProjectIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Cutaway Project"
    static let openAppWhenRun = false
    @Parameter(title: "Project name") var name: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let m = AppDelegate.model,
              let p = m.projects.first(where: { ProjectName.matches($0.name, name) }) else {
            return .result(dialog: "No project named \(name)")
        }
        m.selectManually(p)
        return .result(dialog: "Now tracking \(p.name)")
    }
}

struct CutawayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PauseTrackingIntent(), phrases: ["Pause \(.applicationName)"],
                    shortTitle: "Pause", systemImageName: "pause.fill")
        AppShortcut(intent: ResumeTrackingIntent(), phrases: ["Resume \(.applicationName)"],
                    shortTitle: "Resume", systemImageName: "play.fill")
        AppShortcut(intent: TodayTimeIntent(), phrases: ["How long today in \(.applicationName)"],
                    shortTitle: "Today", systemImageName: "clock")
    }
}

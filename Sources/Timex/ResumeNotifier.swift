import UserNotifications

/// "Are you working?" — the ask-mode reply to anchor activity during a manual
/// pause. Permission is requested lazily at the first prompt; if it is
/// denied the panel banner and pill hint carry the same message.
@MainActor
enum ResumeNotifier {
    nonisolated static let category = "cutaway.resume"
    nonisolated static let resumeAction = "cutaway.resume.yes"
    nonisolated static let stayAction = "cutaway.resume.no"
    private static var delegate: Delegate?

    static func install(onResume: @escaping @MainActor @Sendable () -> Void) {
        let d = Delegate(onResume: onResume)
        delegate = d
        let center = UNUserNotificationCenter.current()
        center.delegate = d
        let yes = UNNotificationAction(identifier: resumeAction, title: "Yes, resume tracking")
        let no = UNNotificationAction(identifier: stayAction, title: "No, stay paused")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [yes, no], intentIdentifiers: []),
        ])
    }

    static func post() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Are you working?"
            content.body = "Cutaway is paused, but you're editing. Click to resume tracking."
            content.categoryIdentifier = category
            content.sound = .default
            center.add(UNNotificationRequest(identifier: category, content: content, trigger: nil))
        }
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
        let onResume: @MainActor @Sendable () -> Void
        init(onResume: @escaping @MainActor @Sendable () -> Void) { self.onResume = onResume }

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse) async {
            let action = response.actionIdentifier
            guard action == resumeAction || action == UNNotificationDefaultActionIdentifier else { return }
            let resume = onResume
            await MainActor.run { resume() }
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }
    }
}

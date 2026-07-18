import SwiftUI
import AppKit

/// Creates the Klokki-style status-item pill once AppKit is ready.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var model: AppModel?
    private var statusController: StatusItemController?
    private var pauseHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            if let model = AppDelegate.model {
                statusController = StatusItemController(model: model)
                // ⌥⌘P — pause/resume from anywhere.
                let hotKey = GlobalHotKey { [weak model] in
                    Task { @MainActor in model?.engine.togglePause() }
                }
                pauseHotKey = hotKey
                model.hotkeyUnavailable = !hotKey.isRegistered
            }
        }
    }
}

@main
struct TimexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        // Settings from the pre-rename bundle id come along exactly once.
        PrefsMigration.migrateIfNeeded()
        // Start detection at launch — not in onAppear, which for a
        // status-item app only fires once the user opens a window.
        let m = AppModel()
        AppDelegate.model = m
        _model = State(initialValue: m)
    }

    var body: some Scene {
        Window("Cutaway", id: "main") {
            MainWindowView(model: model)
                .frame(width: DT.windowSize.width, height: DT.windowSize.height)
                .background(DT.window)
                .preferredColorScheme(.dark)
                .sheet(isPresented: Bindable(model).showNewProjectSheet) {
                    NewProjectSheet(model: model)
                        .preferredColorScheme(.dark)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: DT.windowSize.width, height: DT.windowSize.height)

        Settings {
            SettingsView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}

/// The 480×660 window: custom top bar (segmented) + Timer/Stats views.
struct MainWindowView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: DT.s3) {
            SegmentedTabs(selection: Bindable(model).mainTab)
                .padding(.top, DT.s4)
            switch model.mainTab {
            case .timer: TimerView(model: model)
            case .stats: StatsView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DT.window)
        .onAppear {
            model.openMainWindow = {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            // Zero-state: only ask for a manual project when Resolve isn't
            // running — otherwise auto-detection creates it within seconds.
            if model.projects.isEmpty && model.detector.resolveEdition() == nil
                && !ScenarioMode.isActive {
                model.showNewProjectSheet = true
            }
            if ProcessInfo.processInfo.environment["TIMEX_TAB"] == "stats" { model.mainTab = .stats }
        }
    }
}

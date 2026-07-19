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
        // Menu-bar app: closing the last window retreats to the pill
        // (no Dock icon) instead of lingering as a windowless Dock app.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.async {
                let anyVisible = NSApp.windows.contains {
                    $0.isVisible && $0.styleMask.contains(.titled)
                }
                if !anyVisible { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    /// The red X must NEVER quit — the timer lives in the menu bar.
    /// (SwiftUI's default for status-item apps without MenuBarExtra is to
    /// terminate on last window close — that was the "app closes" bug.)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock icon click (while visible) reopens the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            Task { @MainActor in AppDelegate.model?.openMainWindow?() }
        }
        return true
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
                .sheet(item: Bindable(model).renameTarget) { p in
                    RenameProjectSheet(model: model, project: p)
                        .preferredColorScheme(.dark)
                }
                .sheet(item: Bindable(model).deleteTarget) { p in
                    DeleteProjectSheet(model: model, project: p)
                        .preferredColorScheme(.dark)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: DT.windowSize.width, height: DT.windowSize.height)

        // A real Window, not a Settings scene: the Settings scene can only
        // be opened via showSettingsWindow:, which macOS 14 removed — that
        // was the "settings never opens" bug. A window we open ourselves
        // works from every entry point (panel ⚙, Cmd-comma, harness).
        Window("Cutaway Settings", id: "settings") {
            SettingsView(model: model)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.openSettingsWindow?() }
                    .keyboardShortcut(",", modifiers: .command)
            }
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
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            model.openSettingsWindow = {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            // Zero-state: only ask for a manual project when Resolve isn't
            // running — otherwise auto-detection creates it within seconds.
            if model.projects.isEmpty && model.detector.resolveEdition() == nil
                && !ScenarioMode.isActive {
                model.showNewProjectSheet = true
            }
            if ProcessInfo.processInfo.environment["TIMEX_TAB"] == "stats" { model.mainTab = .stats }
            // Harness hook (like TIMEX_TAB): deterministic Settings capture.
            if ProcessInfo.processInfo.environment["TIMEX_SHOW"] == "settings" {
                model.openSettingsWindow?()
            }
        }
    }
}

import SwiftUI
import AppKit

/// Creates the Klokki-style status-item pill once AppKit is ready.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var model: AppModel?
    private var statusController: StatusItemController?
    private var pauseHotKey: GlobalHotKey?
    private var diagnostics: DiagnosticsSubscriber?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dark-only, decided once. Cutaway sits beside a grading suite; a
        // light window there is glare. Documented exception (Apple: "rare
        // cases"); Increase Contrast and Reduce Transparency are still honoured
        // by the tokens (SystemSettingsTests).
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Crash/hang reports land on disk, never leave the Mac; not during
        // verification runs, which crash on purpose.
        if !ScenarioMode.isActive { diagnostics = DiagnosticsSubscriber() }
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
struct CutawayApp: App {
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
                // A minimum, not a fixed size. macOS has no Dynamic Type, so
                // dragging the window bigger IS the low-vision adaptation —
                // and it was unavailable: the window could not be resized at
                // all, leaving Zoom as the only option, which means panning a
                // magnified viewport around a 480pt window.
                .frame(minWidth: DT.windowSize.width, minHeight: DT.windowSize.height)
                .background(DT.window)
                .sheet(isPresented: Bindable(model).showNewProjectSheet) {
                    ProjectSheet(model: model)
                }
                .sheet(item: Bindable(model).editTarget) { p in
                    ProjectSheet(model: model, editing: p)
                }
                .sheet(item: Bindable(model).editDay) { t in
                    if let p = model.selectedProject {
                        EditDaySheet(model: model, project: p, target: t)
                    }
                }
                .sheet(item: Bindable(model).deleteTarget) { p in
                    DeleteProjectSheet(model: model, project: p)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: DT.windowSize.width, height: DT.windowSize.height)

        // A real Window, not a Settings scene: the Settings scene can only
        // be opened via showSettingsWindow:, which macOS 14 removed — that
        // was the "settings never opens" bug. A window we open ourselves
        // works from every entry point (panel ⚙, Cmd-comma, harness).
        Window("Cutaway Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentMinSize)
        Window("Welcome to Cutaway", id: "permissions") {
            PermissionsView(model: model)
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

/// The Stats window — the only window besides Settings.
struct MainWindowView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: DT.s3) {
            if model.storeIsEphemeral {
                Text("⚠︎ Data can't be saved this run — time tracked now disappears on quit. Restart Cutaway; if this persists, check disk space.")
                    .font(DT.captionMedium)
                    .foregroundStyle(DT.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(DT.red.opacity(0.25))
            }
            if let problem = model.storeErrors.banner {
                Text(problem)
                    .font(DT.captionMedium)
                    .foregroundStyle(DT.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(DT.red.opacity(0.25))
                    .contentShape(Rectangle())
                    .onTapGesture { model.storeErrors.clear() }
            }
            StatsView(model: model)
                .padding(.top, model.storeIsEphemeral ? 0 : DT.s4)
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
            model.openPermissionsWindow = {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "permissions")
            }
            // Zero-state: only ask for a manual project when Resolve isn't
            // running — otherwise auto-detection creates it within seconds.
            if model.projects.isEmpty && model.detector.resolveEdition() == nil
                && !ScenarioMode.isActive {
                model.showNewProjectSheet = true
            }
            if PermissionsPrimerPolicy.shouldShow(alreadyShown: Prefs.bool(forKey: "didShowPermissionsPrimer"),
                                                  scenario: ScenarioMode.isActive) {
                model.openPermissionsWindow?()
            }
            // Harness hooks: deterministic window capture / audit.
            switch ProcessInfo.processInfo.environment["CUTAWAY_SHOW"] {
            case "settings": model.openSettingsWindow?()
            case "permissions": model.openPermissionsWindow?()
            case "newproject": model.openMainWindow?(); model.showNewProjectSheet = true
            default: break
            }
        }
    }
}

import SwiftUI
import ServiceManagement

/// Native, grouped, system-styled. Nobody looks at Settings twice; the
/// identity lives in the pill, the panel and Stats.
struct SettingsView: View {
    @Bindable var model: AppModel
    // `store: Prefs`, not the default. Bare @AppStorage binds
    // UserDefaults.standard — the LIVE domain — in every run including
    // scenario and test-host launches, while the engine reads the same
    // key through the quarantined Prefs. Idle threshold is the single
    // lever that decides how much time gets billed; a test tabbing
    // through this form would rewrite the owner's real one.
    @AppStorage("idleThreshold", store: Prefs) private var idleThreshold: Double = 120
    @AppStorage("defaultCurrency", store: Prefs) private var defaultCurrency = AppModel.defaultCurrency.rawValue
    @State private var editingWorkApps = false
    @State private var editingSatellites = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Tracking") {
                Picker(selection: $idleThreshold) {
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    Text("10 minutes").tag(600.0)
                } label: {
                    // Load-bearing since the render exemption was deleted: this
                    // is the only lever for a workflow with long unattended
                    // renders, and its right value is a fact about the owner's
                    // contracts, not a taste.
                    labelled("Pause after no input for",
                             "Raise it if your renders run unattended and you bill them")
                }
                .accessibilityLabel("Pause after no input for")
                LabeledContent {
                    Button("\(model.engine.workAppPrefixes.count) apps…") { editingWorkApps = true }
                        .popover(isPresented: $editingWorkApps, arrowEdge: .bottom) {
                            AppPrefsPicker(title: "Apps that count", prefsKey: "workApps",
                                           defaults: DetectionInput.defaultWorkAppPrefixes) { _ in model.applyAnchors() }
                        }
                } label: {
                    labelled("Apps that count", "Time in these counts toward the project")
                }
                LabeledContent {
                    Button("\(model.engine.satellitePrefixes.count) apps…") { editingSatellites = true }
                        .popover(isPresented: $editingSatellites, arrowEdge: .bottom) {
                            AppPrefsPicker(title: "Research & comms", prefsKey: "satelliteApps",
                                           defaults: DetectionInput.defaultSatellitePrefixes) { model.engine.satellitePrefixes = $0 }
                        }
                } label: {
                    labelled("Research & comms", "These sustain the timer for 20 minutes after work-app activity")
                }
            }
            Section("Billing") {
                TextField(value: Binding(
                    get: { AppModel.defaultHourlyRate },
                    set: { Prefs.set(AppModel.clampedRate($0), forKey: "defaultHourlyRate") }
                ), format: .number) {
                    labelled("Default hourly rate", "Auto-detected projects start with this rate")
                }
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("Default hourly rate")
                Picker(selection: $defaultCurrency) {
                    ForEach(BillingCurrency.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                } label: {
                    labelled("Default currency", "New projects start with this currency")
                }
                .accessibilityLabel("Default currency")
            }
            Section("Data") {
                LabeledContent {
                    Button("Restore…") { restoreFromBackup() }
                } label: {
                    // One control for an automatic system. Backups run at
                    // launch, daily and at quit; the caption is the
                    // reassurance, and it costs no button.
                    labelled("Backups", "At launch, daily and at quit — kept on this Mac")
                    (model.lastBackup.map { Text("Last backup \($0, format: .dateTime.day().month().hour().minute())") }
                        ?? Text("No backup yet"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        // The switch must never sit ON while the system says
                        // otherwise: re-read the status after every attempt
                        // and explain a refusal instead of swallowing it.
                        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                        catch {
                            let alert = NSAlert()
                            alert.messageText = String(localized: "Couldn't change Launch at login")
                            alert.informativeText = error.localizedDescription
                            alert.runModal()
                        }
                        if SMAppService.mainApp.status == .requiresApproval {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                )) {
                    labelled("Launch at login", "Start tracking when the Mac starts")
                }
                .accessibilityLabel("Launch at login")
                if model.hotkeyUnavailable {
                    LabeledContent("Pause shortcut") { Text("⌥⌘P is taken by another app — pause from the panel") }
                }
                LabeledContent("DaVinci Resolve", value: model.detectLine)
            } header: {
                Text("Menu bar & system")
            }
            Section {
                LabeledContent {
                    if model.detector.accessibilityGranted {
                        Text("Granted").foregroundStyle(.secondary)
                    } else {
                        Button("Enable…") { model.detector.requestAccessibility() }
                    }
                } label: {
                    labelled("Accessibility",
                             "Reads Resolve's window title so the project switches when you do. Never controls your Mac.")
                }
                LabeledContent {
                    Text("Asked per app").foregroundStyle(.secondary)
                } label: {
                    labelled("Automation",
                             "Photoshop, Illustrator, InDesign and After Effects are asked for the name of the open document, once each, when you switch to them. Premiere cannot answer and is never asked.")
                }
                LabeledContent {
                    // Crash reports stay here. "Copy report" pasted MetricKit
                    // JSON into a bug tracker that does not exist — the owner
                    // is the maintainer. A folder still needs a door.
                    Button("Reveal…") {
                        NSWorkspace.shared.activateFileViewerSelecting([DiagnosticsStore.default.directory])
                    }
                } label: {
                    labelled("Diagnostics", "Crash and hang reports, kept on this Mac")
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text(PermissionsPrimerPolicy.statement)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .onChange(of: idleThreshold) { _, new in model.engine.idleThreshold = new }
    }

    /// Pick a `billing-…` folder; the swap happens on relaunch, before the
    /// store opens — a live database is never overwritten underneath itself.
    private func restoreFromBackup() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = AppModel.backupsDir
        panel.message = String(localized: "Choose a backup folder. Cutaway will relaunch with it.")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try StorePath.stagePendingRestore(from: folder)
        } catch {
            let alert = NSAlert(); alert.messageText = String(localized: "Couldn't stage that backup")
            alert.informativeText = error.localizedDescription; alert.runModal(); return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Restore and relaunch?")
        alert.informativeText = String(localized: "The current store is kept beside the restored one. Time tracked since that backup is not in it.")
        alert.addButton(withTitle: String(localized: "Restore and Relaunch"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            try? FileManager.default.removeItem(at: StorePath.pendingRestoreURL()); return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

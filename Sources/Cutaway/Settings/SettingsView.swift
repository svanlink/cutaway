import SwiftUI
import ServiceManagement

/// Native, grouped, system-styled. Nobody looks at Settings twice; the
/// identity lives in the pill, the panel and Stats.
struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("idleThreshold") private var idleThreshold: Double = 120
    @AppStorage("defaultCurrency") private var defaultCurrency = AppModel.defaultCurrency.rawValue
    @AppStorage("pillDisplay") private var pillDisplay = "today"
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
                    labelled("Idle threshold", "Timer pauses after this much inactivity")
                }
                Picker(selection: Binding(
                    get: { model.engine.autoResume.rawValue },
                    set: { Prefs.set($0, forKey: "autoResume")
                           model.engine.autoResume = AutoResumeMode(rawValue: $0) ?? .ask }
                )) {
                    Text("Stay paused").tag(AutoResumeMode.off.rawValue)
                    Text("Ask me").tag(AutoResumeMode.ask.rawValue)
                    Text("Resume automatically").tag(AutoResumeMode.auto.rawValue)
                } label: {
                    labelled("After a manual pause", "When you start editing again in a workflow app")
                }
                Toggle(isOn: Binding(
                    get: { Prefs.bool(forKey: "idleRenderExemption") },
                    set: { Prefs.set($0, forKey: "idleRenderExemption"); model.engine.renderExemption = $0 }
                )) {
                    labelled("Keep counting during renders",
                             "Bills export time with no input — only while Resolve is provably busy, max 30 min")
                }
                LabeledContent {
                    Button("\(model.engine.workAppPrefixes.count) apps…") { editingWorkApps = true }
                        .popover(isPresented: $editingWorkApps, arrowEdge: .bottom) {
                            AppListEditor(title: "Workflow apps", prefsKey: "workApps",
                                          defaults: DetectionInput.defaultWorkAppPrefixes) { _ in model.applyAnchors() }
                        }
                } label: {
                    labelled("Workflow apps", "Time in these counts toward the project")
                }
                LabeledContent {
                    Button("\(model.engine.satellitePrefixes.count) apps…") { editingSatellites = true }
                        .popover(isPresented: $editingSatellites, arrowEdge: .bottom) {
                            AppListEditor(title: "Research & comms apps", prefsKey: "satelliteApps",
                                          defaults: DetectionInput.defaultSatellitePrefixes) { model.engine.satellitePrefixes = $0 }
                        }
                } label: {
                    labelled("Research & comms", "These sustain the timer for 20 minutes after workflow-app activity")
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
                Picker(selection: $defaultCurrency) {
                    ForEach(BillingCurrency.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                } label: {
                    labelled("Default currency", "New projects start with this currency")
                }
            }
            Section("Data") {
                LabeledContent {
                    Button("Back up now") { model.backUpNow(reason: "manual") }
                } label: {
                    labelled("Backups", "Daily, at launch and at quit — kept for 30 days on this Mac")
                }
                LabeledContent {
                    HStack {
                        Button("Reveal backups…") {
                            NSWorkspace.shared.activateFileViewerSelecting([AppModel.backupsDir])
                        }
                        Button("Restore…") { restoreFromBackup() }
                    }
                } label: {
                    (model.lastBackup.map { Text("Last backup \($0, format: .dateTime.day().month().hour().minute())") }
                        ?? Text("No backup yet"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Menu bar & system") {
                Picker(selection: $pillDisplay) {
                    Text("Today").tag("today")
                    Text("Current session").tag("session")
                    Text("Project total").tag("total")
                } label: {
                    labelled("Menu bar shows", "Which time the pill displays")
                }
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
                if model.hotkeyUnavailable {
                    LabeledContent("Pause shortcut") { Text("⌥⌘P is taken by another app — pause from the panel") }
                }
                LabeledContent("DaVinci Resolve", value: model.detectLine)
                LabeledContent {
                    if model.detector.accessibilityGranted {
                        Text("Granted").foregroundStyle(.secondary)
                    } else {
                        Button("Enable…") { model.detector.requestAccessibility() }
                    }
                } label: {
                    labelled("Accessibility", "Lets Cutaway follow Resolve's project switches instantly")
                }
                LabeledContent {
                    Button("Permissions…") { model.openPermissionsWindow?() }
                } label: {
                    labelled("Permissions", "What Cutaway asks for, and what it never does")
                }
                LabeledContent {
                    HStack {
                        Button("Copy report") {
                            NSPasteboard.general.clearContents()
                            let text: String
                            do {
                                let r = try DiagnosticsStore.default.combinedReport()
                                text = r.isEmpty ? String(localized: "No reports") : r
                            } catch {
                                text = String(localized: "Diagnostics folder unreadable: \(error.localizedDescription)")
                            }
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        Button("Reveal…") {
                            NSWorkspace.shared.activateFileViewerSelecting([DiagnosticsStore.default.directory])
                        }
                    }
                } label: {
                    labelled("Diagnostics", "Crash and hang reports stay on this Mac; copy one into a bug report if you want to")
                }
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

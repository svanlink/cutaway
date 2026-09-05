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
                    ForEach(TimexCurrency.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                } label: {
                    labelled("Default currency", "New projects start with this currency")
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
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                )) {
                    labelled("Launch at login", "Start tracking when the Mac starts")
                }
                if model.hotkeyUnavailable {
                    LabeledContent("Pause shortcut", value: "⌥⌘P is taken by another app — pause from the panel")
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
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .onChange(of: idleThreshold) { _, new in model.engine.idleThreshold = new }
    }

    private func labelled(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

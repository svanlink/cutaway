import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("idleThreshold") private var idleThreshold: Double = 120
    @AppStorage("dailyGoalHours") private var dailyGoal: Double = 8
    @AppStorage("defaultCurrency") private var defaultCurrency = TimexCurrency.chf.rawValue
    @State private var editingWorkApps = false
    @State private var editingSatellites = false

    var body: some View {
        VStack(alignment: .leading, spacing: DT.s4) {
            section("TRACKING") {
                row("Idle threshold", sub: "Timer pauses after this much inactivity") {
                    Picker("", selection: $idleThreshold) {
                        Text("1 minute").tag(60.0)
                        Text("2 minutes").tag(120.0)
                        Text("5 minutes").tag(300.0)
                        Text("10 minutes").tag(600.0)
                    }
                    .labelsHidden().frame(width: 130)
                }
                divider
                row("Away grace", sub: "Quick detours shorter than this are bridged") {
                    Picker("", selection: Binding(
                        get: { Prefs.object(forKey: "bridgeGrace") as? Double ?? 180 },
                        set: { Prefs.set($0, forKey: "bridgeGrace"); model.engine.bridgeGrace = $0 }
                    )) {
                        Text("1 minute").tag(60.0)
                        Text("3 minutes").tag(180.0)
                        Text("5 minutes").tag(300.0)
                        Text("10 minutes").tag(600.0)
                    }
                    .labelsHidden().frame(width: 130)
                }
                divider
                row("Workflow apps", sub: "Time in these counts toward the project") {
                    Button("\(model.engine.workAppPrefixes.count) apps  ·  Edit…") { editingWorkApps = true }
                        .popover(isPresented: $editingWorkApps, arrowEdge: .bottom) {
                            AppListEditor(
                                title: "Workflow apps",
                                prefsKey: "workApps",
                                defaults: DetectionInput.defaultWorkAppPrefixes
                            ) { model.engine.workAppPrefixes = $0 }
                        }
                }
                divider
                row("Research & comms", sub: "These sustain the timer inside the research window") {
                    Button("\(model.engine.satellitePrefixes.count) apps  ·  Edit…") { editingSatellites = true }
                        .popover(isPresented: $editingSatellites, arrowEdge: .bottom) {
                            AppListEditor(
                                title: "Research & comms apps",
                                prefsKey: "satelliteApps",
                                defaults: DetectionInput.defaultSatellitePrefixes
                            ) { model.engine.satellitePrefixes = $0 }
                        }
                }
                divider
                row("Research window", sub: "How long these apps keep counting after anchor work") {
                    Picker("", selection: Binding(
                        get: { Prefs.object(forKey: "satelliteWindow") as? Double ?? 1200 },
                        set: { Prefs.set($0, forKey: "satelliteWindow"); model.engine.satelliteWindow = $0 }
                    )) {
                        Text("10 min window").tag(600.0)
                        Text("20 min window").tag(1200.0)
                        Text("30 min window").tag(1800.0)
                        Text("60 min window").tag(3600.0)
                    }
                    .labelsHidden().frame(width: 140)
                }
            }
            section("BILLING") {
                row("Default hourly rate", sub: "Auto-detected projects start with this rate") {
                    TextField("85", value: Binding(
                        get: { Prefs.object(forKey: "defaultHourlyRate") as? Double ?? 85 },
                        set: { Prefs.set($0, forKey: "defaultHourlyRate") }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                }
                divider
                row("Default currency", sub: "New projects start with this currency") {
                    Picker("", selection: $defaultCurrency) {
                        ForEach(TimexCurrency.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .labelsHidden().frame(width: 130)
                }
            }
            section("DISPLAY & SYSTEM") {
                row("Daily goal", sub: "The ring fills toward this target") {
                    Picker("", selection: $dailyGoal) {
                        ForEach([4.0, 6, 8, 10, 12], id: \.self) { Text("\(Int($0)) hours").tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                }
                divider
                row("Menu bar shows", sub: "Which time the pill displays") {
                    Picker("", selection: Binding(
                        get: { Prefs.string(forKey: "pillDisplay") ?? "today" },
                        set: { Prefs.set($0, forKey: "pillDisplay") }
                    )) {
                        Text("Today").tag("today")
                        Text("Current session").tag("session")
                        Text("Project total").tag("total")
                    }
                    .labelsHidden().frame(width: 150)
                }
                divider
                row("Launch at login", sub: "Start tracking when the Mac starts") {
                    Toggle("", isOn: Binding(
                        get: { SMAppService.mainApp.status == .enabled },
                        set: { on in
                            try? on ? SMAppService.mainApp.register()
                                    : SMAppService.mainApp.unregister()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DT.orange)
                }
                if model.hotkeyUnavailable {
                    divider
                    row("Pause shortcut", sub: "⌥⌘P is taken by another app — pause via the menu bar") {
                        Text("Unavailable")
                            .font(DT.smallSemibold)
                            .foregroundStyle(DT.amber)
                    }
                }
                divider
                row("DaVinci Resolve", sub: "Edition in use") {
                    Text(model.detectLine)
                        .font(DT.smallSemibold)
                        .foregroundStyle(DT.text2)
                }
                if !model.detector.accessibilityGranted {
                    divider
                    row("Project auto-detection", sub: "Needs Accessibility permission") {
                        Button("Enable…") { model.detector.requestAccessibility() }
                    }
                }
            }
        }
        .padding(DT.s5)
        .frame(width: 480)
        .background(DT.window)
        .onChange(of: idleThreshold) { _, new in model.engine.idleThreshold = new }
    }

    /// One labeled card per group — common region beats a wall of identical
    /// rows for scan speed (Hick's law).
    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DT.s2) {
            Text(title).font(DT.caption).kerning(0.55).foregroundStyle(DT.text3)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(DT.card, in: RoundedRectangle(cornerRadius: DT.rLg))
                .overlay(RoundedRectangle(cornerRadius: DT.rLg).stroke(DT.strokeSubtle, lineWidth: 1))
        }
    }

    private var divider: some View {
        Rectangle().fill(DT.strokeSubtle).frame(height: 1).padding(.leading, 14)
    }

    @ViewBuilder
    private func row(_ title: String, sub: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: DT.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DT.body).foregroundStyle(DT.text)
                Text(sub).font(DT.captionMedium).foregroundStyle(DT.text3)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

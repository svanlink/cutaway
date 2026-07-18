import AppKit
import Foundation

/// Scenario mode: the app runs its ENTIRE real stack — engine, bridge,
/// satellites, SwiftData, UI — but the two probes replay a scripted timeline
/// and the engine clock is virtual (1 simulated second per driven tick, at
/// ~200x real speed). Real code, deterministic world.
///
/// Scenario file format (one instruction per line, # comments):
///   project <name>              simulate Tier-1 detection of <name>
///   set <engineKey> <seconds>   satelliteWindow | bridgeGrace | idleThreshold
///   clock-before-midnight <s>   start the virtual clock s seconds before midnight
///   pause | resume              manual ⌥⌘P toggle
///   <ticks> <app> <idle>        run N 1s-ticks with app frontmost at idle secs
///     app: resolve|ae|chrome|safari|mail|finder|spotify|none|<bundle-id>
@MainActor
final class ScenarioDriver {

    final class ScenarioProbes: SystemProbing, @unchecked Sendable {
        var frontmost: String?
        var idle: TimeInterval = 0
        func frontmostBundleID() -> String? { frontmost }
        func secondsSinceLastInput() -> TimeInterval { idle }
    }

    static let probes = ScenarioProbes()

    private static let appAliases: [String: String?] = [
        "resolve": DetectionInput.resolveBundleIDs[0],
        "ae": "com.adobe.AfterEffects",
        "chrome": "com.google.Chrome",
        "safari": "com.apple.Safari",
        "mail": "com.apple.mail",
        "finder": "com.apple.finder",
        "spotify": "com.spotify.client",
        "none": nil,
    ]

    static func run(model: AppModel) {
        guard let path = ScenarioMode.scenarioPath,
              let script = try? String(contentsOfFile: path, encoding: .utf8) else {
            fputs("scenario: cannot read script\n", stderr)
            NSApp.terminate(nil)
            return
        }
        var clock = Date()
        model.engine.now = { clock }

        Task { @MainActor in
            for rawLine in script.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#") else { continue }
                let parts = line.split(separator: " ", maxSplits: 2).map(String.init)

                switch parts[0] {
                case "project":
                    let name = line.dropFirst("project ".count).trimmingCharacters(in: .whitespaces)
                    model.scenarioDetect(name)
                case "set":
                    guard parts.count == 3, let v = TimeInterval(parts[2]) else { break }
                    switch parts[1] {
                    case "satelliteWindow": model.engine.satelliteWindow = v
                    case "bridgeGrace": model.engine.bridgeGrace = v
                    case "idleThreshold": model.engine.idleThreshold = v
                    default: break
                    }
                case "clock-before-midnight":
                    guard parts.count >= 2, let s = TimeInterval(parts[1]) else { break }
                    let cal = Calendar.current
                    let nextMidnight = cal.date(byAdding: .day, value: 1,
                                                to: cal.startOfDay(for: Date()))!
                    clock = nextMidnight.addingTimeInterval(-s)
                case "pause", "resume":
                    model.engine.togglePause()
                default:
                    guard let ticks = Int(parts[0]), parts.count >= 2 else { break }
                    let app = appAliases[parts[1], default: parts[1]] ?? nil
                    let idle = parts.count >= 3 ? (TimeInterval(parts[2]) ?? 0) : 0
                    probes.frontmost = app
                    probes.idle = idle
                    for _ in 0..<ticks {
                        clock = clock.addingTimeInterval(1)
                        model.engine.tick()
                        // breathe every so often so the run loop stays alive
                        try? await Task.sleep(nanoseconds: 2_000_000)
                    }
                }
            }
            // Clean quit — exercises the willTerminate flush like a real quit.
            NSApp.terminate(nil)
        }
    }
}

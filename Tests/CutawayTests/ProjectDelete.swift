import XCTest
@testable import Cutaway

/// Deletes named projects through the app's own API — cascade and all — so
/// a stray auto-created project goes the same way it would if it had been
/// deleted from the switcher. Skipped unless CUTAWAY_DELETE is set; run only
/// with the app quit.
@MainActor
final class ProjectDelete: XCTestCase {
    func testDelete() throws {
        let env = ProcessInfo.processInfo.environment
        guard let names = env["CUTAWAY_DELETE"], let path = env["CUTAWAY_IMPORT_STORE"] else {
            throw XCTSkip("set CUTAWAY_DELETE and CUTAWAY_IMPORT_STORE")
        }
        let store = try SessionStore(inMemory: false, url: URL(fileURLWithPath: path))
        for name in names.split(separator: ";").map(String.init) {
            guard let project = try store.projects().first(where: { $0.name == name }) else {
                print("DELETE: no project named \(name)"); continue
            }
            let seconds = project.sessions.reduce(0.0) { $0 + $1.activeSeconds }
            // Refuses if any of its work is on an invoice.
            try store.assertNothingInvoiced(in: project)
            try store.delete(project, reassignTo: nil)
            print("DELETE: \(name) — \(project.sessions.count) sessions, \(String(format: "%.2f", seconds / 3600)) h gone with it")
        }
        for p in try store.projects() {
            print("REMAINS: \(p.name) — \(p.sessions.count) sessions")
        }
    }
}

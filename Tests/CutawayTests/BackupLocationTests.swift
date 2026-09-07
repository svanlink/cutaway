import XCTest
@testable import Cutaway

/// Backups belong beside the store they came from. On 2026-09-07 the owner's
/// real backups folder held five throwaway harness stores, one written that
/// day, each occupying a slot in the keep-newest rotation against backups
/// that had actually recovered lost work.
@MainActor
final class BackupLocationTests: XCTestCase {

    func testBackupsSitBesideTheStoreInUse() {
        XCTAssertEqual(AppModel.backupsDir.deletingLastPathComponent().path,
                       StorePath.url().deletingLastPathComponent().path,
                       "backups must follow the store, not a hard-coded path")
        XCTAssertEqual(AppModel.backupsDir.lastPathComponent, "Backups")
    }

    /// This target runs with XCTestConfigurationFilePath set, so the store is
    /// quarantined — and the backups folder must be quarantined with it.
    func testAHarnessRunCannotReachTheRealBackupsFolder() {
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cutaway/Backups")
        XCTAssertNotEqual(AppModel.backupsDir.standardizedFileURL.path, real.standardizedFileURL.path,
                          "a test run must never write into the owner's backups")
    }
}

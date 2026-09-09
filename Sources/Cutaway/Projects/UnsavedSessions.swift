import Foundation

/// Work that was finished but could not be written to the store.
///
/// The crash snapshot in UserDefaults is a single slot, and it was doing two
/// jobs: "the app died with a session open" and "a save failed, try again".
/// Those conflict. A save fails at 12:30 because the volume is full; the
/// snapshot is kept, correctly, and the banner says to relaunch. But the
/// user comes back at 13:15, a new session starts, and fifteen seconds later
/// the first checkpoint overwrites that slot. The morning is gone, and the
/// banner had told them to do the thing that finished destroying it.
///
/// So failures go somewhere that holds more than one of them, and that a
/// later session cannot tread on: an append-only file beside the store, one
/// JSON object per line. Replayed at launch, and each line is dropped only
/// after its own save returns.
///
/// The honest limit: if the volume is full, appending here can fail too. It
/// is strictly better than the slot it replaces — one more place the work
/// has to survive, not a guarantee it will — and `append` says whether it
/// worked so the caller can keep the crash snapshot as a last resort.
struct UnsavedSessions {

    /// One parked session, with everything needed to place it correctly
    /// later. The first version of this file journalled a bare
    /// `SessionRecord` — {start, end, activeSeconds} — which meant replay had
    /// to guess the project (it used whatever was selected at launch, so an
    /// auto-switch or a rename in between billed the wrong client), had no
    /// way to tell a replay from a first write (SwiftData's save() can throw
    /// after the row has landed, so the same hours could bill twice), and
    /// re-priced the work at the rate in force at replay.
    struct Entry: Codable, Equatable {
        var record: SessionRecord
        /// Whose work this is. Matched by name at replay, and HELD if no
        /// project answers to it — the same ruling SessionRecovery.target
        /// already makes for the crash snapshot.
        var projectName: String
        /// The rate it was worked at, not the rate at replay.
        var hourlyRate: Double
        /// Stable identity, so replaying work the store already holds is a
        /// no-op rather than a second invoice line.
        var uid: String
    }

    /// Which project, if any, should receive this entry. nil means hold it.
    static func owner(of entry: Entry, among projects: [Project]) -> Project? {
        projects.first { $0.name == entry.projectName }
            ?? projects.first { $0.answersTo(entry.projectName) }
    }

    let url: URL

    init(storeURL: URL = StorePath.url()) {
        self.url = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + ".unsaved.jsonl")
    }

    /// Appends one record. Returns false if it could not be written — the
    /// caller must then keep whatever other copy it has.
    @discardableResult
    func append(_ entry: Entry) -> Bool {
        guard let line = try? JSONEncoder().encode(entry) else { return false }
        // Never overwrite what could not be read. `.atomic` is temp-file plus
        // rename, which needs DIRECTORY permission — so a file that fails to
        // read can still be replaced, and `existingData()` swallowing that
        // failure into empty Data meant an append silently destroyed every
        // record already parked here, then reported success, at which point
        // the caller released the crash snapshot too.
        if FileManager.default.fileExists(atPath: url.path),
           (try? Data(contentsOf: url)) == nil { return false }
        var blob = existingData()
        blob.append(line)
        blob.append(0x0A)
        // Whole-file atomic rewrite, not a file-handle append: the file holds
        // at most a handful of lines, and a torn append would cost the very
        // records this exists to protect.
        return (try? blob.write(to: url, options: .atomic)) != nil
    }

    /// Every record still waiting, oldest first. A malformed line is skipped
    /// rather than throwing the rest away.
    func pending() -> [Entry] {
        existingData().split(separator: 0x0A).compactMap {
            try? JSONDecoder().decode(Entry.self, from: Data($0))
        }
    }

    /// Rewrites the file with whatever is still unsaved. Called after a
    /// replay so a record is dropped only once its own save has returned.
    @discardableResult
    func replace(with records: [Entry]) -> Bool {
        guard !records.isEmpty else {
            // Report the truth. This returned true unconditionally, so a
            // delete that failed — an immutable flag from a backup tool, a
            // momentarily unwritable directory — left every record in place
            // to be replayed again on the NEXT launch, and the one after
            // that, silently.
            try? FileManager.default.removeItem(at: url)
            return !FileManager.default.fileExists(atPath: url.path)
        }
        let encoder = JSONEncoder()
        var blob = Data()
        for record in records {
            guard let line = try? encoder.encode(record) else { continue }
            blob.append(line)
            blob.append(0x0A)
        }
        return (try? blob.write(to: url, options: .atomic)) != nil
    }

    private func existingData() -> Data {
        (try? Data(contentsOf: url)) ?? Data()
    }
}

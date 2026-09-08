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

    let url: URL

    init(storeURL: URL = StorePath.url()) {
        self.url = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.lastPathComponent + ".unsaved.jsonl")
    }

    /// Appends one record. Returns false if it could not be written — the
    /// caller must then keep whatever other copy it has.
    @discardableResult
    func append(_ record: SessionRecord) -> Bool {
        guard let line = try? JSONEncoder().encode(record) else { return false }
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
    func pending() -> [SessionRecord] {
        existingData().split(separator: 0x0A).compactMap {
            try? JSONDecoder().decode(SessionRecord.self, from: Data($0))
        }
    }

    /// Rewrites the file with whatever is still unsaved. Called after a
    /// replay so a record is dropped only once its own save has returned.
    @discardableResult
    func replace(with records: [SessionRecord]) -> Bool {
        guard !records.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return true
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

import Foundation

/// Saving FWD Harp's setup, with FWD Sequencer's protections (SongPersistence.swift):
/// written atomically, the previous good file kept as a backup, and an unreadable file
/// moved aside into Quarantine rather than overwritten, so nothing is ever lost.
///
/// One setup for now, in Application Support (out of sight in the Files app, as FWD's
/// songs are). Pure file work with no UI, so `swift test` covers it.
nonisolated enum SetupStorageError: LocalizedError, Equatable {
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let detail): return "Your setup could not be saved. \(detail)"
        }
    }
}

nonisolated enum SetupLoadResult: Equatable {
    /// Nothing saved yet: a first launch.
    case fresh
    case loaded(HarpSetup)
    /// The saved file could not be read. It was moved to Quarantine and the backup
    /// (the last good save) was used instead.
    case restoredFromBackup(HarpSetup)
    /// The saved file could not be read and there was no good backup. It was moved to
    /// Quarantine, and the app starts from the defaults.
    case unreadable

    /// What to tell the person, if anything.
    var notice: String? {
        switch self {
        case .fresh, .loaded: return nil
        case .restoredFromBackup:
            return "Your saved setup could not be read, so the previous save was used instead."
        case .unreadable:
            return "Your saved setup could not be read, so FWD Harp has started fresh. The unreadable file has been kept."
        }
    }
}

nonisolated enum SetupStorage {
    /// Tests point storage at a temporary folder. Production never sets this.
    nonisolated(unsafe) static var directoryOverrideForTesting: URL?

    private static var fileManager: FileManager { .default }

    static var directory: URL {
        if let directoryOverrideForTesting { return directoryOverrideForTesting }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Setup", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("Setup.json") }
    static var backupURL: URL {
        directory.appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("Setup.json")
    }
    static var quarantineDirectory: URL {
        directory.appendingPathComponent("Quarantine", isDirectory: true)
    }

    static func decode(_ data: Data) throws -> HarpSetup {
        try JSONDecoder().decode(HarpSetup.self, from: data).normalized()
    }

    /// Write atomically, first keeping the current file as the backup — but only if it
    /// reads, so a damaged file can never replace the good backup.
    @discardableResult
    static func save(_ setup: HarpSetup) -> Result<Void, SetupStorageError> {
        do {
            try fileManager.createDirectory(at: backupURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            if let existing = try? Data(contentsOf: fileURL), (try? decode(existing)) != nil {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
                try fileManager.copyItem(at: fileURL, to: backupURL)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(setup.normalized())
            try data.write(to: fileURL, options: .atomic)
            return .success(())
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }

    static func load() -> SetupLoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            // No file but a good backup: the file went missing. Use the backup.
            if let backup = readableBackup() { return .restoredFromBackup(backup) }
            return .fresh
        }
        if let data = try? Data(contentsOf: fileURL), let setup = try? decode(data) {
            return .loaded(setup)
        }
        quarantineFile()
        if let backup = readableBackup() {
            // Put the backup back in place, so the next launch opens it directly.
            if let data = try? Data(contentsOf: backupURL) {
                try? data.write(to: fileURL, options: .atomic)
            }
            return .restoredFromBackup(backup)
        }
        return .unreadable
    }

    private static func readableBackup() -> HarpSetup? {
        guard let data = try? Data(contentsOf: backupURL) else { return nil }
        return try? decode(data)
    }

    /// Move the unreadable file aside, under a name of its own, never deleting it.
    private static func quarantineFile() {
        do {
            try fileManager.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)
            let destination = quarantineDirectory
                .appendingPathComponent("Setup-\(UUID().uuidString).corrupt")
            try fileManager.moveItem(at: fileURL, to: destination)
        } catch {
            NSLog("[FWD Harp] Unreadable setup could not be moved aside: %@", error.localizedDescription)
        }
    }
}

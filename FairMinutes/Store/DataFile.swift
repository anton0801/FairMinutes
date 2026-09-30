import Foundation

/// Everything the app keeps, in one document. Children's names never leave this file.
struct AppData: Codable, Equatable {
    static let currentSchema = 1

    var schemaVersion = AppData.currentSchema
    var onboardingComplete = false
    var teamName = ""
    var squad: [Player] = []
    var format = MatchFormat()
    var settings = TeamSettings()
    var seasons: [Season] = []
    var liveMatch: LiveMatch?
}

enum DataFileError: LocalizedError {
    case unreadable(String)
    case newerSchema(Int)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail): return "The saved squad could not be read (\(detail))."
        case .newerSchema(let version): return "This data was saved by a newer version of Fair Minutes (format \(version)). Update the app to open it."
        case .writeFailed(let detail): return "Changes could not be saved (\(detail))."
        }
    }
}

/// A single JSON document in Application Support, written atomically, protected at rest
/// and excluded from device backups — the squad stays on this phone and nowhere else.
struct DataFile {
    let directory: URL
    var url: URL { directory.appendingPathComponent("fair-minutes.json") }

    static var standard: DataFile {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return DataFile(directory: base.appendingPathComponent("FairMinutes", isDirectory: true))
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// `nil` when nothing has been saved yet.
    func load() throws -> AppData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: url)
        } catch {
            throw DataFileError.unreadable(error.localizedDescription)
        }
        struct Header: Decodable { var schemaVersion: Int? }
        if let header = try? Self.decoder.decode(Header.self, from: bytes),
           let version = header.schemaVersion, version > AppData.currentSchema {
            throw DataFileError.newerSchema(version)
        }
        do {
            return try Self.decoder.decode(AppData.self, from: bytes)
        } catch {
            throw DataFileError.unreadable("the file is damaged")
        }
    }

    func save(_ data: AppData) throws {
        do {
            try prepareDirectory()
            let bytes = try Self.encoder.encode(data)
            try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw DataFileError.writeFailed(error.localizedDescription)
        }
    }

    /// Moves an unreadable file aside so starting fresh never destroys it.
    func setAside() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let target = directory.appendingPathComponent("fair-minutes-unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: target)
    }

    func wipe() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func prepareDirectory() throws {
        var dir = directory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }
}

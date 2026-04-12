import Foundation

actor HistoryStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let retentionWindow: TimeInterval

    init(
        fileManager: FileManager = .default,
        retentionWindow: TimeInterval = 30 * 60
    ) {
        self.fileManager = fileManager
        self.retentionWindow = retentionWindow

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadHistory() -> [SystemSnapshot] {
        HistoryPersistence.loadHistory(
            fileManager: fileManager,
            decoder: decoder,
            retentionWindow: retentionWindow
        )
    }

    func save(history: [SystemSnapshot]) {
        HistoryPersistence.save(
            history: history,
            fileManager: fileManager,
            encoder: encoder,
            retentionWindow: retentionWindow
        )
    }
}

enum HistoryPersistence {
    static func loadHistory(
        fileManager: FileManager = .default,
        decoder: JSONDecoder,
        retentionWindow: TimeInterval
    ) -> [SystemSnapshot] {
        guard let url = historyFileURL(fileManager: fileManager),
              let data = try? Data(contentsOf: url),
              let history = try? decoder.decode([SystemSnapshot].self, from: data) else {
            return []
        }

        return trim(history, retentionWindow: retentionWindow)
    }

    static func save(
        history: [SystemSnapshot],
        fileManager: FileManager = .default,
        encoder: JSONEncoder,
        retentionWindow: TimeInterval
    ) {
        let trimmed = trim(history, retentionWindow: retentionWindow)
        guard let url = historyFileURL(fileManager: fileManager) else { return }

        do {
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(trimmed)
            try data.write(to: url, options: .atomic)
        } catch {
            // Persistence is best-effort. Sampling and UI should continue even if disk writes fail.
        }
    }

    private static func trim(_ history: [SystemSnapshot], retentionWindow: TimeInterval) -> [SystemSnapshot] {
        let cutoff = Date().addingTimeInterval(-retentionWindow)
        return history.filter { $0.timestamp >= cutoff }
    }

    private static func historyFileURL(fileManager: FileManager) -> URL? {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return baseURL
            .appendingPathComponent("FluxBar", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }
}

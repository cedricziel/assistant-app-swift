import Foundation

struct AccountPersistence {
    struct Snapshot: Codable {
        var accounts: [AssistantAccount]
        var activeAccountID: AssistantAccount.ID?
    }

    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> Snapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return Snapshot(accounts: [], activeAccountID: nil)
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(Snapshot.self, from: data)
    }

    func save(accounts: [AssistantAccount], activeAccountID: AssistantAccount.ID?) throws {
        let snapshot = Snapshot(accounts: accounts, activeAccountID: activeAccountID)
        let parentDirectory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true, attributes: nil)

        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupport
            .appendingPathComponent("Assistant", isDirectory: true)
            .appendingPathComponent("State", isDirectory: true)
            .appendingPathComponent("accounts.json", isDirectory: false)
    }
}

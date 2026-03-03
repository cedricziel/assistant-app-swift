import Foundation

protocol ChatThreadPersisting {
    func loadThreads(for account: AssistantAccount) throws -> [ChatThread]
    func saveThreads(_ threads: [ChatThread], for account: AssistantAccount) throws
    func removeThreads(for account: AssistantAccount) throws
}

struct ChatThreadPersistence: ChatThreadPersisting {
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadThreads(for account: AssistantAccount) throws -> [ChatThread] {
        guard account.conversationStorage.persistsLocally else {
            return []
        }

        let fileURL = try threadsFileURL(for: account)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([ChatThread].self, from: data)
    }

    func saveThreads(_ threads: [ChatThread], for account: AssistantAccount) throws {
        guard account.conversationStorage.persistsLocally else {
            return
        }

        let fileURL = try threadsFileURL(for: account)
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        let data = try encoder.encode(threads)
        try data.write(to: fileURL, options: .atomic)
    }

    func removeThreads(for account: AssistantAccount) throws {
        guard account.conversationStorage.persistsLocally else {
            return
        }

        let fileURL = try threadsFileURL(for: account)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }

    private func threadsFileURL(for account: AssistantAccount) throws -> URL {
        let baseDirectory = try baseDirectory(for: account.conversationStorage)
        return baseDirectory
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent(account.id.uuidString, isDirectory: true)
            .appendingPathComponent("threads.json", isDirectory: false)
    }

    private func baseDirectory(for storage: AssistantAccount.ConversationStorage) throws -> URL {
        switch storage {
        case .deviceOnly:
            deviceSupportDirectory()
        case .iCloud:
            try iCloudSupportDirectory()
        case .remoteBackend:
            deviceSupportDirectory()
        }
    }

    private func deviceSupportDirectory() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupport.appendingPathComponent("Assistant", isDirectory: true)
    }

    private func iCloudSupportDirectory() throws -> URL {
        if let container = fileManager.url(forUbiquityContainerIdentifier: nil) {
            return container
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Assistant", isDirectory: true)
        }
        return deviceSupportDirectory()
    }
}

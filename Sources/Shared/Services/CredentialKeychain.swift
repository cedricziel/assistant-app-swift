import Foundation
import Security

struct CredentialKeychain {
    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case let .unexpectedStatus(status):
                "Credential storage failed with status \(status)."
            case .invalidData:
                "Credential storage returned invalid data."
            }
        }
    }

    private let service: String

    init(service: String = "app.assistant.credentials") {
        self.service = service
    }

    func setData(_ data: Data, for accountID: UUID) throws {
        let accountKey = accountKey(for: accountID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: data,
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func data(for accountID: UUID) throws -> Data? {
        let accountKey = accountKey(for: accountID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainError.invalidData
        }
        return data
    }

    func setToken(_ token: String, for accountID: UUID) throws {
        try setData(Data(token.utf8), for: accountID)
    }

    func token(for accountID: UUID) throws -> String? {
        guard let data = try data(for: accountID) else {
            return nil
        }
        guard let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return token
    }

    func removeToken(for accountID: UUID) throws {
        let accountKey = accountKey(for: accountID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func accountKey(for accountID: UUID) -> String {
        "account-\(accountID.uuidString.lowercased())"
    }
}

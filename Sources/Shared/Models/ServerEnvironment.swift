import Foundation

struct ServerEnvironment: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var baseURL: URL

    init(id: UUID = UUID(), name: String, baseURL: URL) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }

    var host: String {
        baseURL.host ?? baseURL.absoluteString
    }

    var displayName: String {
        name.isEmpty ? host : name
    }
}

extension ServerEnvironment {
    static let placeholder = ServerEnvironment(
        name: "Localhost",
        baseURL: URL(string: "https://assistant.local")!
    )
}

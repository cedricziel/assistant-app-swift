import Foundation

struct ServerEnvironment: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var baseURL: URL
    var kind: Kind

    enum Kind: String, Codable {
        case remote
        case localDevice
        case localICloud
    }

    init(id: UUID = UUID(), name: String, baseURL: URL, kind: Kind = .remote) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.kind = kind
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
        baseURL: URL(string: "https://assistant.local")!,
    )
}

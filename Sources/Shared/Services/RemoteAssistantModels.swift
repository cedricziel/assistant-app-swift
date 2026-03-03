import Foundation

struct A2ASendMessageRequest: Codable {
    var message: A2AMessage
    var configuration: A2ASendMessageConfiguration?
    var metadata: [String: MetadataValue]?

    enum MetadataValue: Codable {
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self = try .string(container.decode(String.self))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .string(value):
                try container.encode(value)
            }
        }
    }
}

struct A2ASendMessageConfiguration: Codable {
    var responseMode: String?
}

struct A2AMessage: Codable {
    var messageId: String
    var contextId: String?
    var taskId: String?
    var role: A2ARole
    var parts: [A2APart]
    var metadata: [String: String]? = nil
    var extensions: [String] = []
    var referenceTaskIds: [String] = []
}

enum A2ARole: String, Codable {
    case user = "ROLE_USER"
    case agent = "ROLE_AGENT"
}

struct A2APart: Codable {
    var text: String?
    var mediaType: String? = "text/plain"
}

struct A2ASendMessageResponse: Codable {
    var task: A2ATask?
    var message: A2AMessage?
}

struct A2ATask: Codable {
    var id: String
    var contextId: String
    var status: A2ATaskStatus
}

struct A2ATaskStatus: Codable {
    var state: String
    var message: A2AMessage?
}

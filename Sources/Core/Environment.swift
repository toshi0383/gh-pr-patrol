import Foundation

public struct MultipleErrors: Error, CustomStringConvertible {

    public let description: String

    init(messages: [String]) {
        self.description = messages.joined(separator: "\n")
    }
}

public struct Environment: Decodable {

    public let ghRepo: String
    public let ghApiToken: String
    public let bitriseApiToken: String
    public let bitriseBuildTriggerToken: String
    public let appSlug: String

    // Here we customize Decodable behavior,
    // so we can report all missing environment variables to user at once.
    // By default Decodable exits by the first error.
    // We've got 5 required environment variable and the default behavior is not ergonomic.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        var msgs = [String]()

        func decodeOrAppendError(key: CodingKeys) -> String? {

            do {
                let str = try values.decode(String.self, forKey: key)
                if str.isEmpty {
                    msgs.append("env value is empty: \(key.stringValue)")
                    return nil
                }
                return str
            } catch {
                guard let decodingError = error as? DecodingError else {
                    assertionFailure("Unexpected error: \(error)")
                    return nil
                }
                switch decodingError {
                case .dataCorrupted:
                    msgs.append("data corrupted at \(key.stringValue)")
                case .keyNotFound:
                    msgs.append("env key not found: \(key.stringValue)")
                case .typeMismatch(let actualType, _):
                    msgs.append("type mismatch: expected String but got \(actualType)")
                case .valueNotFound(let actualType, _):
                    msgs.append("value not found for \(key.stringValue) with type: \(actualType)")
                }
                return nil
            }

        }

        let ghRepo = decodeOrAppendError(key: .ghRepo)
        let ghApiToken = decodeOrAppendError(key: .ghApiToken)
        let bitriseApiToken = decodeOrAppendError(key: .bitriseApiToken)
        let bitriseBuildTriggerToken = decodeOrAppendError(key: .bitriseBuildTriggerToken)
        let appSlug = decodeOrAppendError(key: .appSlug)

        if !msgs.isEmpty {
            throw MultipleErrors(messages: msgs)
        }

        self.ghRepo = ghRepo!
        self.ghApiToken = ghApiToken!
        self.bitriseApiToken = bitriseApiToken!
        self.bitriseBuildTriggerToken = bitriseBuildTriggerToken!
        self.appSlug = appSlug!
    }

    private enum CodingKeys: String, CodingKey {
        case ghRepo = "GITHUB_REPOSITORY"
        case ghApiToken = "GITHUB_ACCESS_TOKEN"
        case bitriseApiToken = "BITRISE_API_TOKEN"
        case bitriseBuildTriggerToken = "BITRISE_BUILD_TRIGGER_TOKEN"
        case appSlug = "APP_SLUG"
    }
}

extension Environment {
    public static func decode(_ env: [String: String]) throws -> Environment {
        let data = try JSONSerialization.data(withJSONObject: env, options: [])
        return try JSONDecoder().decode(Environment.self, from: data)
    }
}

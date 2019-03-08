import Foundation

struct MultipleErrors: Error, CustomStringConvertible {

    let description: String

    init(messages: [String]) {
        self.description = messages.joined(separator: "\n")
    }
}

struct Environment: Decodable {

    let ghRepo: String
    let ghApiToken: String
    let bitriseApiToken: String
    let bitriseBuildTriggerToken: String
    let appSlug: String

    // Here we customize Decodable behavior,
    // so we can report all missing environment variables to user at once.
    // By default Decodable exits by the first error.
    // We've got 5 required environment variable and the default behavior is not ergonomic.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        var msgs = [String]()

        func decodeOrAppendError<T: Decodable>(_ type: T.Type, forKey key: CodingKeys) -> T? {

            do {
                return try values.decode(type, forKey: key)
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
                    msgs.append("type mismatch: expected \(type) but got \(actualType)")
                case .valueNotFound(let actualType, _):
                    msgs.append("value not found for \(key.stringValue) with type: \(actualType)")
                }
                return nil
            }

        }

        let ghRepo = decodeOrAppendError(String.self, forKey: .ghRepo)
        let ghApiToken = decodeOrAppendError(String.self, forKey: .ghApiToken)
        let bitriseApiToken = decodeOrAppendError(String.self, forKey: .bitriseApiToken)
        let bitriseBuildTriggerToken = decodeOrAppendError(String.self, forKey: .bitriseBuildTriggerToken)
        let appSlug = decodeOrAppendError(String.self, forKey: .appSlug)

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

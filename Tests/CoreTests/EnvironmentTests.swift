import Core
import XCTest

final class EnviornmentTests: XCTestCase {
    func test_decode_error() {
        let env = [String: String]()

        do {
            _ = try Environment.decode(env)
            XCTFail("expected error thrown")
        } catch {
            guard let e = error as? MultipleErrors else {
                XCTFail("unexpected error type")
                return
            }
            XCTAssertEqual(e.description, """
            env key not found: GITHUB_REPOSITORY
            env key not found: GITHUB_ACCESS_TOKEN
            env key not found: BITRISE_API_TOKEN
            env key not found: BITRISE_BUILD_TRIGGER_TOKEN
            env key not found: APP_SLUG
            """)
        }
    }

    func test_decode_fails_on_empty_strings() {
        let env: [String: String] = [
            "GITHUB_REPOSITORY": "",
            "GITHUB_ACCESS_TOKEN": "",
            "BITRISE_API_TOKEN": "",
            "BITRISE_BUILD_TRIGGER_TOKEN": "",
            "APP_SLUG": "",
        ]

        do {
            _ = try Environment.decode(env)
            XCTFail("expected error thrown")
        } catch {
            guard let e = error as? MultipleErrors else {
                XCTFail("unexpected error type")
                return
            }
            XCTAssertEqual(e.description, """
            env value is empty: GITHUB_REPOSITORY
            env value is empty: GITHUB_ACCESS_TOKEN
            env value is empty: BITRISE_API_TOKEN
            env value is empty: BITRISE_BUILD_TRIGGER_TOKEN
            env value is empty: APP_SLUG
            """)
        }
    }

    func test_decode_success() {
        let env: [String: String] = [
            "GITHUB_REPOSITORY": "a",
            "GITHUB_ACCESS_TOKEN": "b",
            "BITRISE_API_TOKEN": "c",
            "BITRISE_BUILD_TRIGGER_TOKEN": "d",
            "APP_SLUG": "e",
        ]

        do {
            let environment = try Environment.decode(env)
            XCTAssertEqual(environment.ghRepo, "a")
            XCTAssertEqual(environment.ghApiToken, "b")
            XCTAssertEqual(environment.bitriseApiToken, "c")
            XCTAssertEqual(environment.bitriseBuildTriggerToken, "d")
            XCTAssertEqual(environment.appSlug, "e")
        } catch {
            XCTFail("unexpected error thrown: \(error)")
        }
    }
}

// 1. Get the last and non-fresh builds for each PR open.
// 2. Trigger re-build

import Foundation

if ProcessInfo.processInfo.arguments.contains("-v") {
    print("0.1.5")
    exit(0)
}

if #available(OSX 10.12, *) {
} else {
    fatalError("Update your macOS. Sierra or later is the deployment target.")
}

// - MARK: Types

typealias JSON = [String: Any]

struct Target {
    let number: Int
    let urlString: String
}

struct PRBuildStatus: Decodable {
    let state: String
    let created_at: Date
    let target_url: String
}

struct TriggerBuildOrigin {
    let target: Target
    let buildSlug: String
    let status: PRBuildStatus
}

// - MARK: Arguments and Environments

struct Environment {
    let ghRepo: String
    let ghApiToken: String
    let bitriseApiToken: String
    let bitriseBuildTriggerToken: String
    let appSlug: String

    init(_ env: [String: String]) {
        func getValue(_ key: String) -> String {
            guard let value = env[key] else {
                fatalError("Error: missing required environment variable: \(key)")
            }
            return value
        }
        ghRepo = getValue("GITHUB_REPOSITORY")
        ghApiToken = getValue("GITHUB_ACCESS_TOKEN")
        bitriseApiToken = getValue("BITRISE_API_TOKEN")
        bitriseBuildTriggerToken = getValue("BITRISE_BUILD_TRIGGER_TOKEN")
        appSlug = getValue("APP_SLUG")
    }
}

let env = Environment(ProcessInfo.processInfo.environment)

let ghRepo = env.ghRepo
let appSlug = env.appSlug
let ghApiToken = env.ghApiToken
let bitriseApiToken = env.bitriseApiToken
let bitriseBuildTriggerToken = env.bitriseBuildTriggerToken

let workflowFilters: [String]? = {
    let args = ProcessInfo.processInfo.arguments
    if let idx = args.index(of: "-f"), args.count > idx + 1 {
        let arg =  String(args[idx + 1])
        return arg.split(separator: ",").map(String.init)
    }
    return nil
}()

let outdateInterval: Double? = {
    let args = ProcessInfo.processInfo.arguments
    if let idx = args.index(of: "-i"), args.count > idx + 1 {
        return Double(args[idx + 1])
    }
    return nil
}()

let dryRun: Bool = {
    let args = ProcessInfo.processInfo.arguments
    return args.contains("--dry-run")
}()

let parallelRebuildCount: Int? = {
    let args = ProcessInfo.processInfo.arguments
    if let index = args.firstIndex(of: "--parallel-rebuild") {
        return index + 1 < args.count ? Int(args[index + 1]) : nil
    }

    return nil
}()

// - MARK: Utilities

func ghRequest(forURLString string: String) -> URLRequest {
    let url = URL(string: string)!
    var req = URLRequest(url: url)
    req.addValue("token \(ghApiToken)", forHTTPHeaderField: "Authorization")
    return req
}

func dataToJSONs(_ data: Data?) -> [JSON] {
    if let data = data,
        let jsons = try! JSONSerialization.jsonObject(with: data, options: []) as? [JSON] {
        return jsons
    }
    return []
}

var targets: [Target] = []
var counter: Int = 0
var lock = NSLock()
var isError = false

let rebuildSemaphore: DispatchSemaphore? = {
    if let count = parallelRebuildCount {
        return DispatchSemaphore(value: count)
    }
    return nil
}()

func decrement() {
    lock.lock(); defer { lock.unlock() }
    counter -= 1
    if counter == 0 {
        print("finished")
        exit(isError ? 1 : 0)
    }
}

// - MARK: Main functions

/// 1. Get build's "original_build_params"
/// 2. Trigger build with the "original_build_params" as "build_params".
func triggerRebuild(_ triggerBuildOrigins: [TriggerBuildOrigin]) {
    let origin = triggerBuildOrigins.first!

    let url = URL(string: "https://api.bitrise.io/v0.1/apps/\(appSlug)/builds/\(origin.buildSlug)")!
    var req = URLRequest(url: url)

    req.addValue("token \(bitriseApiToken)", forHTTPHeaderField: "Authorization")

    URLSession.shared.dataTask(with: req) { data, res, err in
        if (res as? HTTPURLResponse)?.statusCode != 200 {
            fatalError("Failed to get build for buildSlug: \(origin.buildSlug). statusCode: \(String(describing: (res as? HTTPURLResponse)?.statusCode))")
        }

        if let json = try! JSONSerialization.jsonObject(with: data!, options: []) as? JSON {
            if let data = json["data"] as? JSON,
                let triggeredWorkflow = data["triggered_workflow"] as? String,
                let originalBuildParams = data["original_build_params"] as? JSON {

                if let workflowFilters = workflowFilters, !workflowFilters.contains(triggeredWorkflow) {
                    let next = triggerBuildOrigins.dropFirst()
                    if next.isEmpty {
                        decrement()
                    } else {
                        triggerRebuild(Array(next))
                    }
                    return
                }

                if origin.status.state != "success" {
                    decrement()
                    return
                }

                let interval: Double = outdateInterval ?? 60 * 60 * 24
                if abs(origin.status.created_at.timeIntervalSinceNow) < interval {
                    decrement()
                    return
                }

                let url = URL(string: "https://app.bitrise.io/app/\(appSlug)/build/start.json")!
                var req = URLRequest(url: url)
                let json: JSON = [
                    "hook_info": [
                        "type": "bitrise", "api_token": "\(bitriseBuildTriggerToken)"
                    ],
                    "build_params": originalBuildParams,
                ]

                req.httpBody = try! JSONSerialization.data(withJSONObject: json, options: [])
                req.httpMethod = "POST"

                print("triggering rebuild for PR: #\(origin.target.number)")

                if dryRun {
                    decrement()
                    return
                }

                rebuildSemaphore?.wait()

                URLSession.shared.dataTask(with: req) { data, res, err in

                    if let err = err {
                        print(err.localizedDescription)
                    }

                    if (res as? HTTPURLResponse)?.statusCode != 201 {
                        print("Failed to trigger build. Maybe trigger-map is outdated.")
                        if let data = data,
                            let json = try! JSONSerialization.jsonObject(with: data, options: []) as? JSON {
                            print("- response body: \(json)")
                            isError = true
                        }
                    }

                    decrement()

                    rebuildSemaphore?.signal()

                }.resume()
            }
        }
    }.resume()
}

func rebuildIfNeededForEachTarget() {

    counter = targets.count

    for target: Target in targets {
        let url = URL(string: target.urlString)!
        var req = URLRequest(url: url)
        req.addValue("token \(ghApiToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, res, error in
            guard let data = data else {
                print("failed to fetch data: \(String(describing: error))")
                decrement()
                return
            }

            let decoder = JSONDecoder()
            if #available(OSX 10.12, *) {
                decoder.dateDecodingStrategy = .iso8601
            }

            let jsons = try! JSONSerialization.jsonObject(with: data, options: []) as! [JSON]

            let triggerBuildOrigins: [TriggerBuildOrigin] = jsons.compactMap { json -> TriggerBuildOrigin? in

                let data = try! JSONSerialization.data(withJSONObject: json, options: [])
                let status = try! decoder.decode(PRBuildStatus.self, from: data)

                let buildSlug = status.target_url.split(separator: "/").last!

                return TriggerBuildOrigin(target: target, buildSlug: String(buildSlug), status: status)
            }

            if triggerBuildOrigins.isEmpty {
                decrement()
                return
            }

            // trigger rebuild
            triggerRebuild(triggerBuildOrigins)
        }.resume()
    }
}

// - MARK: Main

do {
    let req = ghRequest(forURLString: "https://api.github.com/repos/\(ghRepo)/pulls")
    URLSession.shared.dataTask(with: req) { data, res, error in
        for pull in dataToJSONs(data) {
            if let labels = pull["labels"] as? [JSON] {
                let names = labels.compactMap { $0["name"] as? String }
                if names.contains("WIP") {
                    continue
                }
            }
            if let statusesURL = pull["statuses_url"] as? String,
                let number = pull["number"] as? Int {
                targets.append(Target(number: number, urlString: statusesURL))
            }
        }

        rebuildIfNeededForEachTarget()
    }.resume()
}

dispatchMain()

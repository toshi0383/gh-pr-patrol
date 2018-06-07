// 1. Get the last and non-fresh builds for each PR open.
// 2. Trigger re-build

import Foundation

if ProcessInfo.processInfo.arguments.contains("-v") {
    print("0.1.3")
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

// - MARK: Arguments and Environments

let env = ProcessInfo.processInfo.environment
guard let _ghRepo = env["GITHUB_REPOSITORY"],
    let _ghApiToken: String = env["GITHUB_ACCESS_TOKEN"],
    let _bitriseApiToken = env["BITRISE_API_TOKEN"],
    let _bitriseBuildTriggerToken = env["BITRISE_BUILD_TRIGGER_TOKEN"],
    let _appSlug = env["APP_SLUG"] else {
        print("Error: missing required environment variable")
        exit(1)
}

let ghRepo = _ghRepo // Avoid compiler segmentation fault
let appSlug = _appSlug // Avoid compiler segmentation fault
let ghApiToken = _ghApiToken // Avoid compiler segmentation fault
let bitriseApiToken = _bitriseApiToken // Avoid compiler segmentation fault
let bitriseBuildTriggerToken = _bitriseBuildTriggerToken // Avoid compiler segmentation fault

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
func triggerRebuild(_ buildSlugs: [String]) {
    let buildSlug = buildSlugs.first!

    let url = URL(string: "https://api.bitrise.io/v0.1/apps/\(appSlug)/builds/\(buildSlug)")!
    var req = URLRequest(url: url)
    req.addValue("token \(bitriseApiToken)", forHTTPHeaderField: "Authorization")
    URLSession.shared.dataTask(with: req) { data, res, err in
        if (res as? HTTPURLResponse)?.statusCode != 200 {
            fatalError("Failed to get build for buildSlug: \(buildSlug). statusCode: \(String(describing: (res as? HTTPURLResponse)?.statusCode))")
        }
        if let json = try! JSONSerialization.jsonObject(with: data!, options: []) as? JSON {
            if let data = json["data"] as? JSON,
                let triggeredWorkflow = data["triggered_workflow"] as? String,
                let originalBuildParams = data["original_build_params"] as? JSON {

                if let workflowFilters = workflowFilters, !workflowFilters.contains(triggeredWorkflow) {
                    let next = buildSlugs.dropFirst()
                    if next.isEmpty {
                        decrement()
                    } else {
                        triggerRebuild(Array(next))
                    }
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

            let buildSlugs = jsons.compactMap { json -> String? in

                let data = try! JSONSerialization.data(withJSONObject: json, options: [])
                let status = try! decoder.decode(PRBuildStatus.self, from: data)
                if status.state != "success" {
                    return nil
                }

                let interval: Double = outdateInterval ?? 60 * 60 * 24
                if abs(status.created_at.timeIntervalSinceNow) < interval {
                    return nil
                }

                let buildSlug = status.target_url.split(separator: "/").last!

                return String(buildSlug)
            }

            if buildSlugs.isEmpty {
                decrement()
                return
            }

            // trigger rebuild
            print("triggering rebuild for PR: #\(target.number)")
            triggerRebuild(buildSlugs)
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

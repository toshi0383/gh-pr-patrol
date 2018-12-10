# gh-pr-patrol

This tool keeps PR status-check results up-to-date.
First it searches for **succeeded but outdated** pull-request status checks, then trigger rebuild for each unless the pull-request has `WIP` label.
This way false-positives can be detected before merge, while ignoring positive-falses.

By default outdated means that it passed one day since the last build. Interval can be changed by passing `-i` option.

Currently supports only Bitrise. For other CI services, PRs are welcomed!

# Requirements
- macOS Sierra or later

# Required environment variables

- `GITHUB_REPOSITORY` ... e.g. `toshi0383/Bitrise-iOS`
- `GITHUB_ACCESS_TOKEN`
- `BITRISE_API_TOKEN`
- `BITRISE_BUILD_TRIGGER_TOKEN`
- `APP_SLUG`

# Options

- `-i interval` ... Current time minus interval is the threshold to determine if it's "outdated".
- `-f [workflowID]` ... Specify comma separated workflowIDs which you want to trigger rebuild. Useful when multiple builds are triggered by single pull-request push.
- `--dry-run` ... Do not actually trigger rebuild.
- `--parallel-rebuild n` ... Allowed parallel number of requests for build trigger requests. Use this when you need to workaround parallel job limit on CI service side.
  e.g. Bitrise allows to concurrent jobs to start, but looks like they started to kill the jobs when exceeding your parallel number limit.

# How to use
`export` environment variables above and execute.

Otherwise you can always use this syntax to do that in one-line.

```
GITHUB_REPOSITORY=toshi0383/Bitrise-iOS GITHUB_ACCESS_TOKEN= ... gh-pr-patrol
```

# Install
## Binary install
This is recommended for CI usage.
```
bash <(curl -sL https://raw.githubusercontent.com/toshi0383/scripts/master/swiftpm/install.sh) toshi0383/gh-pr-patrol
```

## Build from source using following tools.

- SwiftPM
- Mint

# Development

- Swift4.2+
- Xcode10.1+

# License
MIT

# FairNest

FairNest is a local-first iOS household organization app built with SwiftUI, WidgetKit, App Intents, and CloudKit.

## Privacy Posture

- Local data stays on device by default.
- iCloud Sync is off by default and must be turned on by the user.
- Partner sharing uses private CloudKit Sharing instead of public read/write invite links.
- Widgets store generic card labels instead of raw household card titles.
- The app has no ads, subscriptions, third-party analytics, custom backend, or paid API dependency.

## Apple Identifier Setup

This checkout is configured with registered Apple identifiers for local development and device testing:

- App bundle ID: `com.hardikpakhale.fairnest`
- Widget bundle ID: `com.hardikpakhale.fairnest.widgets`
- iCloud container: `iCloud.com.hardikpakhale.fairnest`
- App Group: `group.com.hardikpakhale.fairnest`
- Apple development team: `DUHVN68KBA`

To use a different Apple Developer account, replace the identifiers and team in `project.yml` with values registered to that account, then regenerate the Xcode project with:

```sh
xcodegen generate
```

## Development

Open `FairNest.xcodeproj` in Xcode after regenerating the project when `project.yml` changes.

```sh
xcodegen generate
xcodebuild -project FairNest.xcodeproj -scheme FairNest -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The exact simulator name may vary by installed Xcode runtime.

# FairNest

FairNest is a local-first iOS household organization app built with SwiftUI, WidgetKit, App Intents, and CloudKit.

## Privacy Posture

- Local data stays on device by default.
- iCloud Sync is off by default and must be turned on by the user.
- Partner sharing uses private CloudKit Sharing instead of public read/write invite links.
- Widgets store generic card labels instead of raw household card titles.
- The app has no ads, subscriptions, third-party analytics, custom backend, or paid API dependency.

## Public Repository Defaults

This repository intentionally uses public-safe placeholder Apple identifiers:

- App bundle ID: `com.example.fairnest`
- Widget bundle ID: `com.example.fairnest.widgets`
- iCloud container: `iCloud.com.example.fairnest`
- App Group: `group.com.example.fairnest`
- Apple development team: unset

To run the app with CloudKit/App Groups, replace those placeholders in `project.yml` with identifiers registered to your Apple Developer account, then regenerate the Xcode project with:

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

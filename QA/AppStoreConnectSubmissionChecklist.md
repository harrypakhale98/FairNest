# App Store Connect Submission Checklist

Updated: May 28, 2026, 21:53 CDT

## Build Evidence

- Evidence commit: `5769ae4`.
- Full scheme tests passed on iOS Simulator 26.5 (FairNest-SE-QA, iPhone SE 3rd generation): 73 unit tests and 9 UI tests, 82 total, 0 failures.
- Test result bundle: `/tmp/FairNestFullTest-5769ae4.xcresult`.
- The latest `.xcresult` was scanned for `Invalid frame dimension` and `Runtime Warning`; no matches were found.
- Static analysis passed with the full FairNest scheme for generic iOS using `/tmp/FairNestAnalyze-5769ae4`.
- `plutil -lint` passed for exported app and widget Info.plists, privacy manifests, `QA/AppStoreExportOptions.plist`, and `QA/AppStoreUploadOptions.plist`.
- Release archive succeeded at `/tmp/FairNest-5769ae4.xcarchive`.
- App Store export succeeded at `/tmp/FairNest-AppStoreExport-5769ae4/FairNest.ipa` using `QA/AppStoreExportOptions.plist`.
- The archive and exported IPA include the app privacy manifest, widget privacy manifest, bundled `PrivacyPolicy.md`, and `FairNestWidgets.appex`.
- `FairNest/Resources/AppReviewNotes.md` is intentionally excluded from the app target resources and was not present in the built app bundle or exported IPA.
- Exported IPA uses Cloud Managed Apple Distribution signing, Store provisioning profiles, `get-task-allow=false`, the `iCloud.com.hardikpakhale.fairnest` container, and the `group.com.hardikpakhale.fairnest` app group.
- The exported app signature contains CloudKit `Production`; the embedded Store provisioning profile exposes both `Production` and `Development` iCloud environments, which is normal profile metadata and does not override the signed app entitlement.
- The exported widget extension is iPhone-only: `UIDeviceFamily = [1]`.
- Shared household erase writes a content-free CloudKit erasure marker so stale devices acknowledge the reset before uploading local shared cards again.
- Shared household erase deletes visible FairNest shared zones where permission allows, even when the remembered share owner is unavailable.
- Removed cards are kept in local storage, sync to iCloud, and export as minimal deletion markers without title, notes, done criteria, scheduling, ownership, or effort fields.
- Lost shared-household access turns iCloud Sync off and clears pending pushes instead of retrying stale shared-card uploads.

## App Store Connect Inputs

- App name: FairNest
- Bundle ID: `com.hardikpakhale.fairnest`
- Widget bundle ID: `com.hardikpakhale.fairnest.widgets`
- SKU suggestion: `fairnest-ios-1`
- Category suggestion: Productivity
- Price suggestion: Free
- App Store version: `1.0`
- Build number: `1`
- Minimum OS: iOS 26.0

## Review Notes

Use `FairNest/Resources/AppReviewNotes.md` as the base review note. It is a repo-only submission aid and is intentionally excluded from the app bundle. Key points:

- Free app with no ads, subscriptions, in-app purchases, third-party analytics, custom backend, or paid API dependency.
- Local-first app. iCloud sync is off by default.
- CloudKit private database and CloudKit Sharing are used only when enabled by the user.
- Partner pairing is optional and uses Apple's private CloudKit sharing sheet.
- Local notifications only, after permission.
- Brain dump parsing is on-device with a deterministic local fallback.
- Not therapy, medical advice, legal advice, counseling, treatment, or diagnosis.

## Privacy Label Draft

Based on the current repo, the privacy label should be "Data Not Collected" by the developer, assuming there is no external service outside Apple CloudKit and the developer does not access user private CloudKit records. Re-check this before submission if analytics, crash SDKs, support forms, email capture, logging, or any backend is added.

Privacy policy URL is required in App Store Connect. Use the text in `FairNest/Resources/PrivacyPolicy.md`, but host it at a public HTTPS URL before submission. The policy markdown is bundled in the app and rendered by the in-app Privacy Policy screen, but App Store Connect still requires a public URL.

## Export Compliance Draft

The app declares `ITSAppUsesNonExemptEncryption=false`. Current code uses Apple platform services such as CloudKit and standard OS transport/security behavior, with no custom cryptography found in the repo scan. The account holder still needs to certify export compliance in App Store Connect.

## Age Rating Draft

Suggested starting point: general audience / lowest age rating available for a productivity app. Do not put the app in the Kids category. Answer conservatively in App Store Connect if the app metadata mentions partner sharing, household collaboration, or AI suggestions.

## Accessibility Metadata Draft

Claim only what has been manually checked. The SwiftUI UI uses native controls and labels in the core flows, Dynamic Type stress paths were fixed for onboarding, board, brain dump, weekly check-in, and pairing, and the UI suite passed after those changes. A full manual accessibility audit with VoiceOver has not been completed in this pass.

## Screenshot Readiness

Accepted 6.9-inch iPhone screenshots were captured at 1320 x 2868 pixels and visually checked for framing, legibility, and obvious overlap:

- `QA/Screenshots/appstore-iphone17promax-board-light.png`
- `QA/Screenshots/appstore-iphone17promax-board-dark.png`
- `QA/Screenshots/appstore-iphone17promax-empty-light.png`

Current screenshots cover Home Board and empty-board states. Add Brain Dump, Check-In, Pairing, and Settings screenshots before submission if the App Store metadata emphasizes those flows.

Reference: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications

## Remaining Technical Risk

- Sync is foreground/manual/on-local-change driven. CloudKit subscriptions, change-token processing, and remote-notification-triggered background sync are not implemented in this pass, so do not describe sync as instant push-driven sync in App Store metadata.

## Current External Blockers

- App Store Connect upload previously failed because App Store Connect returned zero apps for bundle ID `com.hardikpakhale.fairnest`. Create the app record in App Store Connect first, then upload `/tmp/FairNest-AppStoreExport-5769ae4/FairNest.ipa` or rerun the upload export.
- Host the privacy policy at a public HTTPS URL before submission and paste that URL into App Store Connect.

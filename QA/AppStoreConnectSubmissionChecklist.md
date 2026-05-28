# App Store Connect Submission Checklist

Generated: May 28, 2026

## Build Evidence

- Scheme tests passed on iOS Simulator 26.5 (iPhone 17): 57 unit tests and 7 UI tests, 0 failures.
- The latest `.xcresult` was scanned for `Invalid frame dimension` and `Runtime Warning`; no matches were found.
- Static analysis passed with the full FairNest scheme.
- `plutil -lint` passed for app and widget Info.plists, privacy manifests, and entitlements.
- App Store archive succeeded at `/tmp/FairNest-Readiness.xcarchive`.
- App Store export succeeded at `/tmp/FairNest-AppStoreExport/FairNest.ipa`.
- The app bundle and exported IPA include `PrivacyInfo.xcprivacy` and `PrivacyPolicy.md`.
- `FairNest/Resources/AppReviewNotes.md` is intentionally excluded from the app target resources and was not present in the built app bundle or exported IPA.
- Exported IPA uses Cloud Managed Apple Distribution signing, Store provisioning profiles, `get-task-allow=false`, CloudKit `Production`, the `iCloud.com.hardikpakhale.fairnest` container, and the `group.com.hardikpakhale.fairnest` app group.

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

Privacy policy URL is required in App Store Connect. Use the text in `FairNest/Resources/PrivacyPolicy.md`, but host it at a public HTTPS URL before submission. The policy markdown is bundled in the app for in-app access, but App Store Connect still requires a public URL.

## Export Compliance Draft

The app declares `ITSAppUsesNonExemptEncryption=false`. Current code uses Apple platform services such as CloudKit and standard OS transport/security behavior, with no custom cryptography found in the repo scan. The account holder still needs to certify export compliance in App Store Connect.

## Age Rating Draft

Suggested starting point: general audience / lowest age rating available for a productivity app. Do not put the app in the Kids category. Answer conservatively in App Store Connect if the app metadata mentions partner sharing, household collaboration, or AI suggestions.

## Accessibility Metadata Draft

Claim only what has been manually checked. The SwiftUI UI uses native controls and labels in the core flows, Dynamic Type stress paths were fixed for onboarding, board, brain dump, weekly check-in, and pairing, and the UI suite passed after those changes. A full manual accessibility audit with VoiceOver has not been completed in this pass.

## Current External Blockers

- App Store Connect upload previously failed because App Store Connect returned zero apps for bundle ID `com.hardikpakhale.fairnest`. Create the app record in App Store Connect first, then upload `/tmp/FairNest-AppStoreExport/FairNest.ipa` or rerun the upload export.
- Host the privacy policy at a public HTTPS URL before submission and paste that URL into App Store Connect.

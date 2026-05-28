# App Store Connect Submission Checklist

Generated: May 28, 2026

## Build Evidence

- Scheme tests passed on iOS Simulator 26.5: 24 unit tests and 2 UI tests, 0 failures.
- Release device build passed against iPhoneOS 26.5.
- Static analysis passed.
- App Store archive succeeded at `/tmp/FairNest-Readiness.xcarchive`.
- App Store export succeeded at `/tmp/FairNest-AppStoreExport/FairNest.ipa`.
- Exported IPA uses Cloud Managed Apple Distribution signing, Store provisioning profiles, `get-task-allow=false`, and CloudKit `Production`.

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

Use `FairNest/Resources/AppReviewNotes.md` as the base review note. Key points:

- Free app with no ads, subscriptions, in-app purchases, third-party analytics, custom backend, or paid API dependency.
- Local-first app. iCloud sync is off by default.
- CloudKit private database and CloudKit Sharing are used only when enabled by the user.
- Partner pairing is optional and uses Apple's private CloudKit sharing sheet.
- Local notifications only, after permission.
- Brain dump parsing is on-device with a deterministic local fallback.
- Not therapy, medical advice, legal advice, counseling, treatment, or diagnosis.

## Privacy Label Draft

Based on the current repo, the privacy label should be "Data Not Collected" by the developer, assuming there is no external service outside Apple CloudKit and the developer does not access user private CloudKit records. Re-check this before submission if analytics, crash SDKs, support forms, email capture, logging, or any backend is added.

Privacy policy URL is required in App Store Connect. Use the text in `FairNest/Resources/PrivacyPolicy.md`, but host it at a public HTTPS URL before submission.

## Export Compliance Draft

The app declares `ITSAppUsesNonExemptEncryption=false`. Current code uses Apple platform services such as CloudKit and standard OS transport/security behavior, with no custom cryptography found in the repo scan. The account holder still needs to certify export compliance in App Store Connect.

## Age Rating Draft

Suggested starting point: general audience / lowest age rating available for a productivity app. Do not put the app in the Kids category. Answer conservatively in App Store Connect if the app metadata mentions partner sharing, household collaboration, or AI suggestions.

## Accessibility Metadata Draft

Claim only what has been manually checked. The SwiftUI UI uses native controls and labels in the core flows, but a full accessibility audit has not been completed in this pass.

## Current External Blocker

Upload failed because App Store Connect returned zero apps for bundle ID `com.hardikpakhale.fairnest`. Create the app record in App Store Connect first, then upload `/tmp/FairNest-AppStoreExport/FairNest.ipa` or rerun the upload export.

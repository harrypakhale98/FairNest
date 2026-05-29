# App Store Connect Submission Checklist

Updated: May 29, 2026, 04:15 CDT

## Build Evidence

- App artifact evidence commit: `6f3fb62`.
- Release archive succeeded at `/tmp/FairNest-6f3fb62.xcarchive`.
- App Store export succeeded at `/tmp/FairNest-AppStoreExport-6f3fb62/FairNest.ipa` using `QA/AppStoreExportOptions.plist`.
- Static analysis passed with the full FairNest scheme for generic iOS using `/tmp/FairNestAnalyze-6f3fb62` with `COMPRESS_PNG_FILES=NO`.
- Unit tests passed at `6f3fb62` on iOS Simulator 26.5 with result bundle `/tmp/FairNestFullUnitTests/Logs/Test/Test-FairNest-2026.05.29_04-01-06--0500.xcresult`: 107 executed tests, 107 passed, 0 failures.
- UI tests passed at `6f3fb62` on iOS Simulator 26.5 with result bundle `/tmp/FairNestFullUITests-6f3fb62/Logs/Test/Test-FairNest-2026.05.29_04-08-19--0500.xcresult`: 12 reported tests, 1 expected screenshot-capture skip, 0 failures.
- `plutil -lint` passed for archived and exported app and widget Info.plists, exported privacy manifests, `QA/AppStoreExportOptions.plist`, and `QA/AppStoreUploadOptions.plist`.
- The archive and exported IPA include the app privacy manifest, widget privacy manifest, bundled `PrivacyPolicy.md`, and `FairNestWidgets.appex`.
- `FairNest/Resources/AppReviewNotes.md` is intentionally excluded from the app target resources and was not present in the built app bundle or exported IPA.
- Exported IPA uses Cloud Managed Apple Distribution signing, Store provisioning profiles, `get-task-allow=false`, the `iCloud.com.hardikpakhale.fairnest` container, and the `group.com.hardikpakhale.fairnest` app group.
- The exported app signature contains CloudKit `Production`; the embedded Store provisioning profile exposes both `Production` and `Development` iCloud environments, which is normal profile metadata and does not override the signed app entitlement.
- The exported app is iPhone-only: `UIDeviceFamily = [1]`.
- `/tmp/FairNest-AppStoreExport-6f3fb62/Packaging.log` was scanned for warning, error, failed, and invalid markers; no matches were found.
- Common secret-pattern scan with `rg` returned no matches, and `git status --ignored --short` was empty in the clean `/tmp/FairNestRemoteWork` verification clone.
- GitHub Pages deploy completed successfully for `6f3fb62`, and the public home, support, and privacy URLs returned HTTP 200.
- Shared household erase writes a content-free CloudKit erasure marker so stale devices acknowledge the reset before uploading local shared cards again.
- Shared household erase deletes visible FairNest shared zones where permission allows, even when the remembered share owner is unavailable.
- Removed cards are kept in local storage, sync to iCloud, and export as minimal deletion markers without title, notes, done criteria, scheduling, ownership, or effort fields.
- Lost shared-household access turns iCloud Sync off and clears pending pushes instead of retrying stale shared-card uploads.
- iCloud account changes turn iCloud Sync off, clear pending CloudKit pushes and widget/pin state, and prevent uploads under the wrong account.
- Shared-household access loss removes stale shared cards locally while preserving pinned private cards.
- CloudKit card saves fetch the existing record, apply only changed FairNest fields, and save with changed keys instead of overwriting the whole server record.
- Shared-household erasure acknowledgements are scoped by CloudKit account and zone when those identifiers are available.
- Shared-household deletion now resolves all target zones before writing any erasure marker or deleting records, so ambiguous shared selection fails closed before private CloudKit data is erased.
- Erasure acknowledgements are only written after local cards, check-ins, reminders, and widget state are cleared, so stale local data cannot be re-uploaded after a partial deletion failure.
- Widget snapshot reads ignore legacy persisted card titles and return safe type labels, matching the current write path.
- Static website files include local-only icons, a privacy page, a support page, and a GitHub Pages Actions deployment workflow. The website has no forms, cookies, analytics, ads, remote scripts, or custom backend.

## App Store Connect Inputs

- Metadata draft: `QA/AppStoreConnectMetadata.md`
- App name: FairNest
- Bundle ID: `com.hardikpakhale.fairnest`
- Widget bundle ID: `com.hardikpakhale.fairnest.widgets`
- SKU suggestion: `fairnest-ios-1`
- Category suggestion: Productivity
- Price suggestion: Free
- App Store version: `1.0`
- Build number: `1`
- Minimum OS: iOS 26.0
- Support contact: `harry.pakhale98@gmail.com`
- Support URL: `https://harrypakhale98.github.io/FairNest/support.html`
- Privacy Policy URL: `https://harrypakhale98.github.io/FairNest/privacy.html`

## Review Notes

Use `FairNest/Resources/AppReviewNotes.md` as the base review note. It is a repo-only submission aid and is intentionally excluded from the app bundle. Key points:

- Free app with no ads, subscriptions, in-app purchases, third-party analytics, custom backend, or paid API dependency.
- Local-first app. iCloud sync is off by default.
- CloudKit private database and CloudKit Sharing are used only when enabled by the user.
- Partner pairing is optional and uses Apple's private CloudKit sharing sheet.
- Local notifications only, after permission.
- Brain dump parsing is on-device with a deterministic local fallback.
- Support email is available from website support and in-app Settings. Users are told not to include private household card details unless needed to explain the issue.
- Not therapy, medical advice, legal advice, counseling, treatment, or diagnosis.

## Privacy Label Draft

Based on the current repo, the privacy label should be "Data Not Collected" by the developer, assuming there is no external service outside Apple CloudKit and the developer does not access user private CloudKit records. Re-check this before submission if analytics, crash SDKs, support forms, email capture, logging, or any backend is added.

Privacy policy URL is required in App Store Connect. Use `https://harrypakhale98.github.io/FairNest/privacy.html`, which matches `FairNest/Resources/PrivacyPolicy.md` and the static `website/privacy.html`. The policy markdown is bundled in the app and rendered by the in-app Privacy Policy screen, while App Store Connect uses the public HTTPS URL.

The policy now discloses invited participant access to shared CloudKit card data, retention duration, deletion markers, optional iCloud Sync withdrawal, stopping CloudKit sharing where permissions allow it, and optional support email handling.

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
- `QA/Screenshots/appstore-iphone17promax-brain-dump-light.png`
- `QA/Screenshots/appstore-iphone17promax-check-in-light.png`
- `QA/Screenshots/appstore-iphone17promax-pairing-light.png`
- `QA/Screenshots/appstore-iphone17promax-settings-light.png`

Automated screenshot capture evidence: `FairNestUITests/FairNestUITests/testCaptureAppStoreScreenshotsWhenDirectoryProvided` passed on `FairNest-AppStore-6-9` with result bundle `/tmp/FairNestAppStoreScreenshotCapture-7e5edd9.xcresult`, refreshing the brain dump, check-in, pairing, and settings screenshots at 1320 x 2868. Board, dark-mode board, and empty-state screenshots remain retained manual QA captures and should be rechecked visually immediately before upload.

The App Store board light, board dark, and empty-state screenshots, plus the website copies, were flattened from fully opaque RGBA to RGB at `6f3fb62`; `sips -g hasAlpha` reports `no` for those PNGs.

Reference: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications

## Remaining Technical Risk

- Sync is foreground/manual/on-local-change driven. CloudKit subscriptions, change-token processing, and remote-notification-triggered background sync are not implemented in this pass, so do not describe sync as instant push-driven sync in App Store metadata.

## Current External Blockers

- A fresh App Store Connect upload export attempt at `6f3fb62` failed before upload because App Store Connect returned zero apps for bundle ID `com.hardikpakhale.fairnest`; Xcode logged `IDEDistribution.DistributionAppRecordProviderError.missingApp(bundleId: "com.hardikpakhale.fairnest")` in `/var/folders/wx/sxnmpk8d6xj670t2p63z7c4c0000gn/T/FairNest_2026-05-29_04-14-47.399.xcdistributionlogs`.
- Create the app record in App Store Connect first, then upload `/tmp/FairNest-AppStoreExport-6f3fb62/FairNest.ipa` or rerun the upload export.

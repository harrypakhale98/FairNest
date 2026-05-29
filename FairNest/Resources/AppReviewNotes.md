# App Review Notes

FairNest is free and has no ads, subscriptions, in-app purchases, custom backend, or third-party analytics.

Data storage and sharing:
- Local-first storage on device.
- User-controlled iCloud card sync using CloudKit, off by default.
- Optional private partner sharing using CloudKit Sharing.
- Solo mode works without iCloud or partner pairing.
- Offline mode works; changes sync later when iCloud is available.

AI:
- Brain dump suggestions are structured and user-reviewed before saving.
- Apple Foundation Models are used only on device when available.
- A deterministic local parser is always available.
- FairNest is not therapy, counseling, mental-health treatment, medical advice, legal advice, or diagnosis.

Notifications:
- Local notifications only.
- Permission is requested from Settings before FairNest schedules due-card or weekly check-in reminders.

Privacy:
- Privacy policy is available in the app.
- Privacy manifest declares no tracking, no developer-collected data, and required-reason UserDefaults access for app and widget storage.
- Widgets avoid storing raw household card titles in App Group defaults.
- Users can export local data, delete local data, and delete shared household card data where their CloudKit permissions allow it. Weekly check-ins are local-only and included in export/delete controls.
- Users can turn off optional iCloud Sync in Settings and stop or manage CloudKit sharing through Apple's iCloud sharing sheet where permissions allow it.
- Removed card tombstones are minimal sync markers and omit card text, scheduling details, ownership, and effort in local storage, iCloud records, and exported data.
- If shared-household access is lost, FairNest turns iCloud Sync off on that device and clears pending pushes so stale shared cards are not uploaded privately.
- Support contact: harry.pakhale98@gmail.com. Users are asked not to include private household card details unless needed to explain the issue.

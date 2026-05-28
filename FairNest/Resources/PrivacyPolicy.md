# FairNest Privacy Policy

FairNest is a private household organization app. It does not sell data, show ads, use third-party analytics, use a custom server, or use paid APIs.

Household cards, reminder settings, and pairing state are stored locally on the device. iCloud Sync is off by default. When the user turns it on, FairNest uses CloudKit to sync card data and private CloudKit Sharing to share a household with invited participants. Weekly check-ins stay on the device and can be exported by the user. Apple provides iCloud and CloudKit infrastructure; FairNest’s developer does not operate a separate backend for this data.

Brain dump parsing happens on device. When Apple Foundation Models are available, FairNest may use Apple’s on-device model to suggest structured cards. When that model is unavailable, FairNest uses a deterministic local parser. Raw brain dump text is never automatically shared.

FairNest uses local notifications only, after permission is granted, for due responsibilities, recurring responsibilities, and weekly check-ins. The app does not use remote push notifications.

Users can export their local FairNest data from the Privacy screen, delete local app data and scheduled FairNest reminders from this device, and delete shared household data where CloudKit permissions allow it.

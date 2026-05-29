# Security

The Apple team ID in the Xcode project and QA export plists is intentional signing configuration for this checkout. Do not commit provisioning profiles, signing certificates, private keys, App Store Connect API keys, app-specific passwords, `.env` files, Firebase/Google service plists, or local Xcode user state.

Before making a public release, run a repository secret scan and verify that `git status --ignored` shows local signing/configuration files as ignored.

CloudKit sharing should stay private participant-managed sharing. Do not expose raw read/write share URLs publicly.

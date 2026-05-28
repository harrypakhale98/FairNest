# Security

Do not commit production Apple team IDs, provisioning profiles, signing certificates, private keys, `.env` files, Firebase/Google service plists, or local Xcode user state.

Before making a public release, run a repository secret scan and verify that `git status --ignored` shows local signing/configuration files as ignored.

CloudKit sharing should stay private participant-managed sharing. Do not expose raw read/write share URLs publicly.

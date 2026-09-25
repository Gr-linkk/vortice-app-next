# NEXT-012: Google Play readiness for the independent Android app

Selected September 24, 2026. Android goes first; iOS follows after the Android
release. There is no selected final name, domain, Android application ID,
production signing key, production service target or pilot company. Build 40 is
an internal debug artifact, not a Google Play release.

## Verified starting point

- The primary Linux checkout is `/home/garrett/projects/vortice-app-next`.
  `/home/garrett/Documents/ChatGPT/Vortice app` is a local reference copy at
  the same Build 40 commit. Both are independent from the original app.
- The independent GitHub `main` currently ends at `f6c54e8` (September 5),
  while Build 40 is `78b9c62` (September 14). The current branch has 83 commits
  beyond remote main and is not advertised by that remote. No history was
  rewritten. A verified all-ref Git bundle is in ignored
  `outputs/recovery/vortice-next-source-20260924.bundle` (SHA-256
  `945855b03f3a4a103826558cbfc88402aa5549212f303f328eef387711560da1`).
  Linux GitHub credentials are unavailable, so remote publication is pending.
- Flutter doctor reports no issues, and Build 40's manifest targets Android
  API 36. Its APK checksum matches NEXT-010. No phone is currently attached.
- The source checkout retains the ignored Next configuration, exact linked
  project ref `hkjpojobdbbtjkhaudki` and a completed September 14 backup. Its
  manifest verifies 84 files including 78 Storage objects. This is plaintext
  local staging, not encrypted off-device recovery or a hosted restore.

## Release contract

- Keep the final package, Firebase identity, production backend, signer and
  secret material separate from the original app. Do not publish the placeholder
  `com.example.vortice_app_next` or a debug-signed artifact.
- Prepare an Android App Bundle signed with a protected upload key, then verify
  package, signer, runtime target, version and absence of debug credentials.
  Do not upload to Play until the final identity and target are selected.
- Complete Play Console setup, app access for reviewers, Data safety, privacy
  policy and account-deletion paths. The app allows account creation, so an
  in-app deletion request path and a functional web request page are required.
- Verify real account email/recovery and notification receipt, tap and access
  after account changes. Complete phone camera, file picker, offline restart and
  ordinary fleet/provider workflows at normal and large text.
- Establish encrypted off-device database and private-file backups, restore
  them to an isolated approved target, and assign a support/incident owner and
  alert destination before customer reliance.
- Resolve code, artwork and manual rights, Syncfusion entitlement or
  replacement, customer-facing terms and the selected commercial offer.

## External choices still needed

Final name/domain/application ID; Google Play developer account type and access;
production backend target; sending domain/provider and real recipient; backup
destination and custodian; recovery target, time and data-loss budgets; support
and incident owner; privacy/data-deletion terms; applicable tax review; first
customer and acceptance. The user can connect the S24 for phone checks.

## Current Play references

- [Target API requirement](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en): new apps target API 36 from August 31, 2026.
- [App account deletion](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en): in-app and web request paths for apps that create accounts.
- [Personal-account test requirement](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en): qualifying newer personal accounts require 12 opted-in closed testers for 14 days before applying for production access; verify the actual account type.
- [App setup and Play App Signing](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en).

# Release Checklist

Current Android builds use `com.example.vortice_app_next` and debug signing.
They are internal/test builds, not production releases. NEXT-009 removes the
release-to-debug signing fallback and explicitly blocks Release tasks until
production identity/signing is implemented. Use the guarded debug build helper.

The current consolidated release gates and owner action list are in
`docs/specs/NEXT-009-production-readiness.md`. Prior build receipts remain
historical evidence; transferring an APK does not close phone acceptance.

## Scope and identity

- [ ] Backlog item and release notes are identified.
- [ ] Version and build number in `pubspec.yaml` are intentional.
- [ ] Customer-facing product name is correct.
- [ ] Android and iOS application IDs are correct for the target environment.
- [ ] Production signing is configured and verified when producing a production
      artifact; debug signing is not represented as a release.

## Backend and data

- [ ] Runtime configuration targets the intended independent Supabase project.
- [ ] Required migrations are reviewed, deployed, and recorded.
- [ ] No service-role key, database password, login list, or local config is
      tracked or embedded in an artifact.
- [ ] RLS and role behavior affected by the release have been tested.

## Verification

- [ ] `./scripts/verify.cmd` passes on Windows (or `verify.ps1` in CI).
- [ ] The target platform build completes with explicit runtime configuration.
- [ ] A physical-device smoke test covers login, navigation, offline behavior,
      and the changed user journey.
- [ ] UI changes have screenshots at representative sizes and languages.
- [ ] Known limitations and rollback expectations are documented.
- [ ] All local database contracts and the isolated archive restore pass via
      `bash scripts/test-database.sh --restore-drill`.
- [ ] Hosted operational snapshot is checked with `python3 scripts/check-operations.py`.
- [ ] Current release passes relevant hosted authorization contracts.

## Production customer readiness

- [ ] Customer environment, final package identity and protected signer are selected.
- [ ] Release artifact contains no test-account credentials or debug entry points.
- [ ] Real selected recipients accept invites, sign in and recover passwords.
- [ ] Phone notification receipt/tap, camera, file picker and offline restart pass.
- [ ] Database AND uploaded evidence have encrypted off-device backup coverage;
      a hosted-equivalent restore with private files and access checks passes.
- [ ] Support contact, alert destination, recovery targets and incident owner are assigned.
- [ ] Dependency/asset rights and Syncfusion license are resolved and notices prepared.
- [ ] Initial customer region/currency/tax rules are selected; the current USD/MXN
      invoice behavior is not represented as a Canadian invoice implementation.
- [ ] Offer, billing/cancellation, privacy/data lifecycle and pilot acceptance are approved.

## Artifact handling

- [ ] Artifact is copied to an ignored subdirectory under `outputs/`.
- [ ] Filename includes product, platform, version, and build number.
- [ ] SHA-256 checksum is recorded beside the artifact.
- [ ] Distribution destination and audience are explicitly approved.

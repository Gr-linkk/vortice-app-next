# Release Checklist

Current Android builds use `com.example.vortice_app_next` and debug signing.
They are internal/test builds, not production releases.

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

## Artifact handling

- [ ] Artifact is copied to an ignored subdirectory under `outputs/`.
- [ ] Filename includes product, platform, version, and build number.
- [ ] SHA-256 checksum is recorded beside the artifact.
- [ ] Distribution destination and audience are explicitly approved.

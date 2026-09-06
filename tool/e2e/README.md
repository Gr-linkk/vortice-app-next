# Connected workflow audit

These tests run real Flutter screens, authentication and hosted Next persistence.
They are deliberately outside `test/`: ordinary verification must not create
hosted records or require development account credentials.

Run from this repository root with the verified Flutter runtime. Set
`VORTICE_E2E_CONFIG` to the existing Next configuration file (without copying
credentials) and `VORTICE_FLUTTER_FONTS` to the Flutter SDK's
`bin/cache/artifacts/material_fonts` directory. The configuration must contain
the Next URL, anon key and the existing `DEV_LOGIN_PASSWORDS` JSON map. Tests
refuse a different Supabase URL. Create ignored `outputs/` before the first run.

```sh
flutter test tool/e2e/full_app_audit_test.dart --reporter expanded
flutter test tool/e2e/saved_workflows_test.dart --reporter expanded
flutter test tool/e2e/operations_workflows_test.dart --reporter expanded
flutter test tool/e2e/custody_workflows_test.dart --reporter expanded
```

Run sequentially. Accounts are the existing owner, technician, company manager,
company mechanic, operator and second-company development accounts. The saved
journeys create synthetic `E2E-010` records and manifest files in `outputs/`.
Some steps continue after a failure to collect independent findings; each test
still fails if any recorded step fails. Route results include redirects and
visible labels, so inspect the report as well as the final test exit status.

The test host uses disposable preferences and, for the full router journeys,
an in-memory local database. Custody tests substitute only the photo picker with
`fixtures/evidence.png`; its actual uploaded bytes and cross-company access are
checked. This is not physical Android camera, permission, keyboard or share UI
coverage. See the current audit specification for precise coverage and open bugs.

After the tests, inspect the generated manifests and run the guarded cleanup
with the already authenticated Supabase CLI available on PATH:

```sh
python3 tool/e2e/cleanup_fixtures.py
```

Cleanup checks the independent origin, the linked Next project, exact manifest
UUIDs and asset names; removes their dependent records and exact Storage paths;
and checks unrelated counts. It obtains the Next Storage service key in process
memory only. If cleanup fails, retain the manifests and resolve the reported
failure; do not delete broad name prefixes or unrelated records.

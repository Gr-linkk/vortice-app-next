# Companion web deployment

One Flutter app supplies the office dashboard and full field workflows. It uses
only Next accounts, company permissions and `hkjpojobdbbtjkhaudki`. Domain and
public product identity remain unselected. Local browser testing is not a hosted
release or proof of phone camera/push behavior.

## Build and preview

From the verified independent repository:

```sh
bash scripts/build-web.sh
python3 tool/web/serve.py
```

Open `http://localhost:8088`. The builder prints the deployable output directory
and records it in ignored `work/web/latest-build.txt`. Set `VORTICE_NEXT_CONFIG`
to choose another ignored local Next configuration. The builder validates and
copies only the public Supabase URL and anonymous/publishable client key into a
temporary build file; demo passwords and management secrets are excluded.
Builds are release mode and use a fresh directory with no compiler source maps.
Do not serve the repository or `config/` directly. Stop the local preview server
when it is no longer needed. `--port` permits a different loopback port.

## Future hosting connection

Upload only the printed artifact to a static HTTPS host. Serve the root path;
routes use URL fragments, so ordinary deep links do not need server rewrites.
Apply `web/_headers` (or equivalent host configuration): COOP `same-origin`, COEP
`require-corp`, WASM MIME `application/wasm`, and no-cache on index/service worker.
Check those response headers on the actual domain. Assets are bundled locally,
including CanvasKit, fonts and the matching SQLite/Drift browser runtime.

Add the exact chosen HTTPS root with `?vortice_recovery=1` to the **Next** Supabase
Auth redirect allowlist, configure the reviewed sending domain/provider, and
verify a real recovery email in the same browser. Recovery uses PKCE and removes
the consumed callback code from the address. Domain/inbox acceptance is still
open; no wildcard redirects or original-service configuration are authorized.

The app-shell worker caches same-origin static files only. It never caches
Supabase API responses, authentication callback URLs or uploaded evidence.
Updates wait for existing tabs to close, avoiding forced reloads while editing.
Open a new session after closing old tabs to accept an update. Report drafts and permitted read caches use an IndexedDB preference store,
which migrates existing Flutter localStorage keys only after committed writes.
The outbox uses account-owned SQLite browser databases. Both require successful
local storage writes; clearing site data,
using private browsing, storage eviction, or changing host/origin can remove them.
Sync work before clearing storage or moving to the eventual domain. Browser
push notifications are not configured; the in-app inbox remains available.

## Repeatable storage acceptance

```sh
CHROME_EXECUTABLE=/usr/bin/chromium flutter test --no-pub --platform chrome test/browser_preferences_browser.dart
python3 tool/web/prepare_build_test.py
```

The browser-only test is deliberately named outside the normal native test glob.
It commits a 6 MB draft, reopens it, verifies account-specific removal, and checks
legacy migration without replacing newer stored values. Ordinary navigation,
field evidence and download acceptance is recorded in NEXT-014.

## Storage asset provenance

- `drift_worker.js`: official Drift 2.31.0 release, SHA-256
  `f0a9b87085f732fd7b6ee7eb34d3858c556f05d221eb1febfc443649cd365752`.
- `sqlite3.wasm`: official sqlite3.dart 2.9.4 release (the resolved dependency),
  SHA-256 `922a76b182b6af69b030c8e2fdd3283ecc8e827248b20e4b1f3f3db170b52117`.
- MIT notices are bundled in `web/licenses/`; SQLite itself is public domain.

Pinned versions follow `pubspec.lock`. Update both assets and their reviewed
checksums deliberately with a dependency upgrade. The runtime refuses unsafe
or in-memory-only database fallbacks, so unsupported/private browser storage
cannot silently be presented as durable field storage. See the
[Drift web setup](https://drift.simonbinder.eu/platforms/web/) and the
[Flutter web URL strategy](https://docs.flutter.dev/ui/navigation/url-strategies).

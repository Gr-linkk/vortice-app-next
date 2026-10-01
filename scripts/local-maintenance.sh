#!/usr/bin/env bash
# LF-001 experimental native workflow. Never starts the hosted application.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$root"
test "$(git rev-parse --show-toplevel)" = "$root"
test "$(git remote)" = origin
for direction in fetch push; do
  flags=(); [[ "$direction" == push ]] && flags=(--push)
  while IFS= read -r remote; do
    test "${remote%.git}" = https://github.com/Gr-linkk/vortice-app-next
  done < <(git remote get-url "${flags[@]}" --all origin)
done
app="$root/experiments/maintenance_local"
rg -q 'applicationId = "org.vortice.next.maintenance_local"' "$app/android/app/build.gradle.kts"
rg -q 'APPLICATION_ID "org.vortice.next.maintenance_local"' "$app/linux/CMakeLists.txt"
rg -q 'maintenance-local-v1' "$app/lib/main.dart"
if rg -n -i 'supabase|firebase' "$app/pubspec.yaml" "$app/pubspec.lock" "$app/lib"; then
  echo 'Local maintenance must not initialize or depend on hosted services.' >&2
  exit 1
fi
action="${1:-verify}"; shift || true
if [[ "$action" == check ]]; then
  echo 'Local maintenance identity, storage and hosted-service separation passed.'
  exit 0
fi
if ! command -v cargo >/dev/null; then
  export CARGO_HOME="${VORTICE_NATIVE_TOOLCHAIN:-$HOME/.local/share/vortice-sync-lab-toolchain}/cargo"
  export RUSTUP_HOME="${VORTICE_NATIVE_TOOLCHAIN:-$HOME/.local/share/vortice-sync-lab-toolchain}/rustup"
  export PATH="$CARGO_HOME/bin:$PATH"
fi
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"
cd "$app"
case "$action" in
  verify)
    flutter pub get --offline --enforce-lockfile
    flutter analyze --no-pub
    dart --packages=.dart_tool/package_config.json tool/verify_work_progress.dart
    cargo test --manifest-path rust/Cargo.toml --locked --offline
    cargo build --manifest-path rust/Cargo.toml --locked --offline
    export MAINTENANCE_NATIVE_LIBRARY="${MAINTENANCE_NATIVE_LIBRARY:-$app/rust/target/debug/librust_lib_sync_lab.so}"
    flutter test --no-pub "$@"
    node --test "$root"/tools/local-agent-cli/test/*.test.mjs
    bash "$root/scripts/local-maintenance.sh" cli-smoke
    ;;
  cli-smoke)
    command -v node >/dev/null
    cargo build --manifest-path rust/Cargo.toml --locked --offline
    library="${MAINTENANCE_NATIVE_LIBRARY:-$app/rust/target/debug/librust_lib_sync_lab.so}"
    test -f "$library"
    fixture_root="$(mktemp -d /tmp/vortice-cli-e2e-XXXXXXXX)"
    chmod 700 "$fixture_root"
    fixture_pid=""
    cleanup_fixture() {
      if [[ -n "$fixture_pid" ]]; then
        kill "$fixture_pid" 2>/dev/null || true
        wait "$fixture_pid" 2>/dev/null || true
      fi
      rm -rf -- "$fixture_root"
    }
    trap cleanup_fixture EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    dart run tool/local_agent_service_fixture.dart --synthetic-fixture \
      --workspace "$fixture_root/workspace" --socket "$fixture_root/agent.sock" \
      --ready "$fixture_root/ready.json" --native-library "$library" \
      >"$fixture_root/runner.log" 2>&1 &
    fixture_pid=$!
    fixture_ready() {
      [[ -f "$fixture_root/ready.json" && ! -L "$fixture_root/ready.json" ]] || return 1
      node -e 'try {
        const fs = require("node:fs");
        const readyPath = process.argv[1];
        const stat = fs.statSync(readyPath);
        if ((stat.mode & 0o777) !== 0o600 || stat.uid !== process.getuid()) process.exit(1);
        const ready = JSON.parse(fs.readFileSync(readyPath, "utf8"));
        process.exit(ready.synthetic_fixture === true && ready.protocol_version === 1 ? 0 : 1);
      } catch { process.exit(1); }' "$fixture_root/ready.json"
    }
    fixture_is_ready=0
    for ((attempt=0; attempt<300; attempt++)); do
      if fixture_ready; then fixture_is_ready=1; break; fi
      kill -0 "$fixture_pid" 2>/dev/null || {
        echo 'The synthetic CLI fixture could not start; existing workspaces were not opened.' >&2
        exit 1
      }
      sleep 0.1
    done
    [[ "$fixture_is_ready" == 1 ]] || {
      echo 'The synthetic CLI fixture did not become ready in time.' >&2
      exit 1
    }
    node "$root/tools/local-agent-cli/integration/service-e2e.mjs" \
      --ready "$fixture_root/ready.json" --socket "$fixture_root/agent.sock"
    ;;
  build-linux)
    flutter build linux --debug --no-pub "$@"
    ;;
  build-android)
    # An existing internal signer must be chosen deliberately. Never generate one.
    test -n "${VORTICE_MAINTENANCE_KEYSTORE:-}" || {
      echo 'Select the existing internal debug keystore with VORTICE_MAINTENANCE_KEYSTORE.' >&2; exit 1;
    }
    test -f "$VORTICE_MAINTENANCE_KEYSTORE"
    export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
    export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/28.2.13676358}"
    flutter build apk --debug --no-pub --target-platform android-arm64 "$@"
    ;;
  run) flutter run --no-pub "$@" ;;
  recovery)
    cargo build --manifest-path rust/Cargo.toml --locked --offline
    dart run tool/office_recovery.dart "$@"
    ;;
  *) echo 'Usage: scripts/local-maintenance.sh {check|verify|cli-smoke|build-linux|build-android|run|recovery} [arguments]' >&2; exit 2 ;;
esac

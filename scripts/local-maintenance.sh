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
    dart run tool/verify_work_progress.dart
    cargo test --manifest-path rust/Cargo.toml --locked --offline
    cargo build --manifest-path rust/Cargo.toml --locked --offline
    flutter test --no-pub "$@"
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
  *) echo 'Usage: scripts/local-maintenance.sh {check|verify|build-linux|build-android|run|recovery} [arguments]' >&2; exit 2 ;;
esac

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(git rev-parse --show-toplevel)" = "$(pwd -P)"
test "$(git remote)" = origin
test "$(git remote get-url origin)" = https://github.com/Gr-linkk/vortice-app-next.git
test "$(git remote get-url --push origin)" = https://github.com/Gr-linkk/vortice-app-next.git
dart run tool/project_guardrails.dart
config="${VORTICE_NEXT_CONFIG:-config/vortice-next.local.json}"
mkdir -p work/web
public_config="$(mktemp work/web/public-defines-XXXXXXXX.local.json)"
trap 'rm -f "$public_config"' EXIT
python3 tool/web/prepare_build.py prepare "$config" "$public_config"
# A fresh output folder cannot accidentally ship old debug files or source maps.
output="$(mktemp -d outputs/web-build-XXXXXXXX)"
flutter build web --release --no-wasm-dry-run --no-web-resources-cdn --pwa-strategy=none --output "$output" --dart-define-from-file="$public_config"
python3 tool/web/prepare_build.py finish "$output"
printf '%s\n' "$output" > work/web/latest-build.txt
printf 'Web app: %s\n' "$output"

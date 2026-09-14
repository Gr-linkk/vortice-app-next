#!/usr/bin/env bash
# WSL/Linux companion to build-android.ps1, using the same Next target guards.
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(git rev-parse --show-toplevel)" = "$(pwd -P)"
test "$(git remote)" = origin
test "$(git remote get-url origin)" = https://github.com/Gr-linkk/vortice-app-next.git
config="${VORTICE_NEXT_CONFIG:-config/vortice-next.local.json}"
firebase="${VORTICE_NEXT_FIREBASE_CONFIG:-}"
python3 - "$config" "$firebase" <<'PY'
import json, sys
from pathlib import Path
config=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
assert config.get('SUPABASE_URL')=='https://hkjpojobdbbtjkhaudki.supabase.co', 'Unauthorized Supabase target'
key=config.get('SUPABASE_ANON_KEY','').strip()
assert key and 'YOUR-' not in key and 'PLACEHOLDER' not in key, 'Missing public client key'
if sys.argv[2]:
    firebase=json.loads(Path(sys.argv[2]).read_text(encoding='utf-8-sig'))
    assert firebase.get('FIREBASE_PROJECT_ID')=='vortice-next', 'Unauthorized Firebase project'
    assert firebase.get('FIREBASE_ANDROID_APP_ID')=='1:256876964373:android:ba58553beed6145f033c1c', 'Unauthorized Firebase app'
    assert str(firebase.get('FIREBASE_MESSAGING_SENDER_ID'))=='256876964373', 'Unauthorized messaging sender'
    assert firebase.get('FIREBASE_API_KEY','').strip(), 'Missing Firebase key'
PY
dart run tool/project_guardrails.dart
defines=("--dart-define-from-file=$config")
if [ -n "$firebase" ]; then defines+=("--dart-define-from-file=$firebase"); fi
flutter test "${defines[@]}" test/core/backend_build_config_test.dart
flutter build apk --debug --target-platform android-arm64 "${defines[@]}"
source=build/app/outputs/flutter-apk/app-debug.apk
test -s "$source"
mkdir -p outputs/builds
destination="outputs/builds/vortice-next-android-debug-$(date +%Y%m%d-%H%M%S).apk"
cp -n "$source" "$destination"
sha256sum "$destination" | tee "$destination.sha256"

#!/usr/bin/env bash
set -euo pipefail

expected_ref="hkjpojobdbbtjkhaudki"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linked_ref_file="$repo_root/supabase/.temp/project-ref"

if [[ "${1:-}" != "--project-ref" || "${2:-}" != "$expected_ref" || $# -ne 2 ]]; then
  echo "Usage: $0 --project-ref $expected_ref" >&2
  exit 2
fi

if [[ ! -f "$linked_ref_file" ]]; then
  echo "Missing linked project ref at $linked_ref_file" >&2
  exit 1
fi

linked_ref="$(tr -d '[:space:]' < "$linked_ref_file")"
if [[ "$linked_ref" != "$expected_ref" ]]; then
  echo "Refusing deployment: linked Supabase ref is not the authorized Vortice Next ref." >&2
  exit 1
fi

cd "$repo_root"
echo "Validated Vortice Next project ref: $expected_ref"
supabase db push --linked

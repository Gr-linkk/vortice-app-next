#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Reuses the identity guard and isolated, network-disabled PostgreSQL runner.
# Never connects to a linked/hosted database or needs account credentials.
bash scripts/test-database.sh supabase/tests/performance/work_hub.sql

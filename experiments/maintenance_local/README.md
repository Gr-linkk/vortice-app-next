# Vortice Local Maintenance — experimental LF-001

Standalone Android/Linux inspection workflow on local devices. Start from the
office, create your company equipment and procedure, and prepare an inspection.
The phone saves answers, readings, notes and a gallery photo offline, then sends
the exact submitted version for office review. Earlier records remain in history.

This package has its own identity and data. The hosted Vortice app remains intact.
Scope, evidence and physical acceptance gates are in
[`LF-001`](../../docs/specs/LF-001-local-maintenance-slice.md).

From the repository root, use `bash scripts/local-maintenance.sh verify`,
`build-linux`, `build-android` or `run -d linux`. Android debug builds require
`VORTICE_MAINTENANCE_KEYSTORE` pointing at an existing internal debug signer;
the helper creates no key and release builds remain blocked. Never point
`VORTICE_MAINTENANCE_DATA` at retained app or Sync Lab storage.

For same-identity recovery, retain the office fingerprint separately, create a
private verified backup outside its workspace, stop the old office, and restore
into an absent directory. Reconfirm surviving phones; revoked phones stay blocked.
The backup contains private office identity. No automatic coordinator failover,
phone promotion or live-company import is implemented.

# Vortice Local Maintenance — experimental LF-001

Standalone Android/Linux inspection workflow on local devices. Start from the
office, create your company equipment and procedure, and prepare an inspection.
The phone saves answers, readings, notes and a gallery photo offline, then sends
the exact submitted version for office review. Earlier records remain in history.

This package has its own identity and data. The hosted Vortice app remains intact.
Scope, evidence and physical acceptance gates are in
[`LF-001`](../../docs/specs/LF-001-local-maintenance-slice.md).

For ordinary camera-free pairing, changed-network recovery and sending status,
follow [Connect your inspection phone](SETUP.md).

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

## First inspection

1. Open the separate **Vortice Local Maintenance** Linux app. Choose **Create
   company**, enter the company and coordinator, then **Add equipment**. Choose
   its meter unit deliberately: hours, kilometres, miles or no meter.
2. Choose **Author checklist**. Add the actual inspection steps, required answers,
   measurement units and acceptable numeric ranges. Publish it, then choose
   **Prepare inspection** for the equipment. Prepared work retains this exact
   checklist and equipment context even when another procedure is published.
3. With both devices on the same local network, choose **Connect or replace a
   phone** and **Create phone invitation**. Copy its private text to the phone
   and choose **Paste invitation**. Compare the confirmation code on both
   devices and allow the phone at the office. A gallery image of the invitation
   also works when the camera is unavailable. Keep both apps open to receive
   prepared work. This experiment uses TCP 47841; the original lab uses its own
   separate port. Network changes and installation on real devices are separate
   operator actions, not performed by the build helper.
4. Open the prepared inspection on the phone. Save checks, readings, notes and
   **Choose a saved photo** to open the gallery. A missing meter remains unknown; entering zero
   records zero. Work saves locally, including across an offline restart. Cancel
   the gallery picker to keep the current saved photo.
5. Choose **Submit for review**. Keep the apps open when they reconnect. The
   durable queue retries the same frozen submission; the office reviews its
   saved answers, checklist, units and verified photo. Approve that exact version
   or return it with a reason. Corrections require another submission; earlier
   versions and decisions stay in history. Approval records an inspection and
   does not close repairs or declare equipment available.

## Backup and fresh office recovery

Use **Back up office computer**, save the displayed office fingerprint separately,
and choose **Create verified backup** for a new folder. Copy the entire private
folder to separate storage. Only records received by the office are included.
Incomplete or corrupt photos prevent a successful complete backup.

Close the original office. On the replacement Linux computer choose **Restore
office backup**, enter the entire private backup directory, an absent workspace
directory and the separately saved fingerprint. **Check backup** must succeed
before restore is enabled. The app opens the restored workspace. Reinvite and
reconfirm the same surviving phones; revoked phones remain blocked.
Normal restore requires a Local Maintenance v2 backup. It rejects Sync Lab
backups, and normal startup rejects an unrelated or wrong-role workspace before
changing its permissions, schema or identity.

An older backup can receive a surviving phone's own queued submission chain.
Office decisions created after that backup cannot be reconstructed from the
phone's copy. The connection reports missing office history and keeps the phone's
saved receipt rather than claiming a complete recovery. Retain both copies for a
separately reviewed reconciliation; this slice does not invent missing approvals.

Command-line verification/restoration is also available through
`bash scripts/local-maintenance.sh recovery verify BACKUP_FOLDER` and
`bash scripts/local-maintenance.sh recovery restore BACKUP_FOLDER NEW_WORKSPACE EXPECTED_TLS_FINGERPRINT`.
Restoration retains existing directories rather than overwriting them.

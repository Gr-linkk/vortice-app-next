# Production operations preparation

Owner scope: NEXT-009. This is prepared operating material, not a claim that
production monitoring, encrypted backups or an on-call service are activated.
Only Next project `hkjpojobdbbtjkhaudki` is authorized. BACKLOG.md owns priority.

## One-shot health check

From this checkout in WSL/Linux with the existing authenticated Supabase CLI:

```bash
python3 scripts/check-operations.py
```

The tool verifies every origin URL and the linked project before running fixed
aggregate-only SQL in a read-only transaction. It records
`outputs/next009/operations.json`. Exit 0 means the listed aggregate checks
passed; 2 means a health check failed; 1 means the check was unavailable.
Unknown/unavailable is never healthy. It reports no device tokens, user records,
cron commands or credentials. Migration parity compares versions, not SQL bodies.

Initial investigation thresholds: no push schedule run for 5 minutes, any failed
schedule run in 24 hours, or a pending delivery overdue by 15 minutes. These are
diagnostic defaults, not an uptime or delivery guarantee. Inspect aggregate
failed delivery counts as well; old failed attempts require a recorded disposition.
Do not send synthetic notifications without a selected recipient and authorization.
The tool is one-shot; Garrett must select alert destination and operating owner
before scheduled monitoring/notifications are activated. Client crash capture
still needs a selected service and data-redaction review before activation.

## Backup staging and recovery

```bash
python3 scripts/backup-next.py
```

This reads only the guarded linked Next project. It stages CLI roles/schema/data
exports and each Storage object in a fresh ignored `outputs/backups/<UTC>/`
directory, plus Auth/Storage access-rule metadata and migration-history exports.
Local object filenames are hashes; the manifest maps them to exact
remote bucket/name identities and records lengths and SHA-256 checksums. It
retains bucket privacy/limits, checks source Storage inventory again at the end,
and marks interrupted/failed exports incomplete. The CLI needs working database
dump and Storage permissions; it never asks for a password interactively. It uses
the CLI-generated dump/filter script with the existing `postgres:17` Docker image
and independently checks its PGHOST/PGUSER target. On Linux without Docker
access, explicitly select the local backend and a PostgreSQL 17 client:

```bash
VORTICE_BACKUP_DATABASE_BACKEND=local \
VORTICE_PG_BIN="$HOME/.local/share/vortice-tools/postgresql/17.11/bin" \
python3 scripts/backup-next.py
```

The helper rejects other client major versions before requesting the dump script.
Both backends run the same CLI-generated export and filtering instructions. Connection values stay in
process stdin and are not saved as scripts. A different hosted PostgreSQL major
version requires a deliberate client-compatibility update.
Private files use the [authenticated Storage download API](https://supabase.com/docs/guides/storage/serving/downloads).
The CLI retrieves the Next service credential once into process memory; the
downloader sends it only to the fixed Next host, refuses redirects and never
persists it in the manifest, command arguments or logs.

The staged files are plaintext and can contain account data. Keep them private;
do not commit or share them. Local staging is not off-device backup coverage.
Separate database dumps and a Storage download are not an atomic snapshot across
services. Perform the accepted recovery export in a coordinated quiet/write-pause
window, verify all manifest hashes, and encrypt it to the selected destination.
Never infer recovery coverage from a partial directory or a successful DB dump.

Verify a completed local export again before using it:

```bash
python3 scripts/verify_backup.py outputs/backups/<UTC>/manifest.json
```

This checks containment, missing/duplicate files, lengths and hashes. The
manifest is an integrity receipt, not authenticated provenance; protected
encryption/access and an actual restore remain necessary.

Current local drill:

```bash
bash scripts/test-database.sh --restore-drill
```

This proves a populated PostgreSQL archive restores company/work/invoice history
and RLS in a disposable container. It does not restore Supabase-managed Auth,
Storage API behavior, edge secrets or hosted configuration. Do not load the local
test bootstrap into a real service.

Hosted-equivalent recovery acceptance, after Garrett selects an isolated recovery
target and budget:

1. Record source, backup time, compatible app/schema version and object count.
2. Create the approved isolated target; never overwrite Next or the original app.
3. Follow the current Supabase restore procedure for roles, schema and data; the
   target must provide compatible managed Auth/Storage schemas and extensions.
   Review captured `managed-access.json` for policies and triggers invoking public
   app functions on Auth/Storage. This is not a full managed-schema dump; compare
   any other custom managed-schema alterations using the vendor procedure.
   Do not blindly apply system schema DDL over a provisioned target. Restore the
   captured migration history separately. Review the vendor's current handling
   of Vault/column-encryption keys when those are in use.
4. Recreate private bucket settings and upload files to the manifest's original
   bucket/name paths through Storage APIs, then verify hashes and ownership/access.
5. Restore separately documented auth redirect/templates/providers, functions,
   cron schedules and server secrets using protected configuration. Keep outbound
   jobs disabled on the recovery target until their destinations are reviewed.
6. Prove sign-in, company isolation, work/report/invoice history and authorized
   photo/document access; show another company cannot access those same files.
7. Measure data loss window and restore duration against Garrett's selected
   recovery objectives; retain a receipt. Do not promise RPO/RTO before this test.

Supabase database backups exclude Storage file contents. The vendor also lists
settings/objects that are not copied by project cloning. Review the current
[backup documentation](https://supabase.com/docs/guides/platform/backups) and
[clone limitations](https://supabase.com/docs/guides/platform/clone-project)
when executing hosted recovery.

## Incident and update procedure

- Record affected company, app/build, UTC time, action and connectivity without
  collecting passwords or sending private attachments into public tickets.
- For unsent work, preserve app data. Check the queue and account before asking
  someone to retry; never clear storage/reinstall as a generic recovery step.
- For failed jobs or unavailable sign-in, inspect aggregate health, recent
  deployment evidence and the selected provider dashboard. Record an owner and
  next update time once the support policy is selected.
- For suspected access exposure, restrict the affected path through existing
  controls, preserve evidence and follow the approved incident/privacy procedure.
- Retain the previous tested package and migration compatibility record.
  Android downgrade or a different signer/package may not preserve data; do not
  promise an APK rollback without a tested upgrade/recovery route.
- Use additive forward corrections for deployed migrations. Never rewrite a
  deployed migration or restore the entire database to undo one failed action.

## Configuration ownership to assign

Garrett selects the owner/custodian for: repository administration, Supabase,
Firebase, production signer, sending domain/email provider, payment account,
encrypted backups, monitoring and customer support. Keep actual secrets in
protected service settings or ignored local configuration, not this document.

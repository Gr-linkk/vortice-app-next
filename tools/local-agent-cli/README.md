# Desktop CLI for external agents

This increment is a client for the LF-001 local inspection service. Client/fixture tests are not proof of a
configured service, an agent grant or desktop-app integration. It does not use
the retained hosted MCP or Supabase, and it never opens workspace databases.

Run on Linux with Node 22 or later, without installing dependencies:

```sh
node tools/local-agent-cli/cli.mjs help
node --test tools/local-agent-cli/test/*.test.mjs
```

An agent host supplies `VORTICE_LOCAL_AGENT_TOKEN` through its private process
environment. This client does not create, persist, discover or configure grants.
Do not put tokens in command arguments or chat. There is no implicit access for
the desktop owner. The service must independently check permission, expiry,
revocation and record scope for every command.

All calls name the service socket and workspace/company/device. Example IDs and
paths below are placeholders, not a configured endpoint:

```sh
node tools/local-agent-cli/cli.mjs workspace status \
  --socket /run/user/USER_ID/vortice-agent.sock \
  --workspace WORKSPACE_ID --company COMPANY_ID --device DEVICE_ID
node tools/local-agent-cli/cli.mjs work show --id JOB_ID \
  --socket /run/user/USER_ID/vortice-agent.sock \
  --workspace WORKSPACE_ID --company COMPANY_ID --device DEVICE_ID
```

Use scoped equipment/procedure/work/history reads to gather context. Lists
accept --limit (1..100, default 25), --cursor, --job and --equipment. Follow
next_cursor and heed complete, observation/local_revision and sync metadata.
Cursors are bound to the visible snapshot; stale cursors require a fresh read.
An observation timestamp is not proof of a fresh meter reading or successful
replication. Unknown sync time stays null. Approved history belongs to its exact
immutable submission, never to later edits of the work document.

The sole proposed write is `proposals create`: JSON on stdin, with required
`type: inspection.notes`, `job_id`, `expected_document_hash` (64 lowercase hex),
and suggested replacement `notes`. Supply a stable UUID with `--operation`:

```sh
node tools/local-agent-cli/cli.mjs proposals create --input - \
  --operation OPERATION_UUID --socket /run/user/USER_ID/vortice-agent.sock \
  --workspace WORKSPACE_ID --company COMPANY_ID --device DEVICE_ID < proposal.json
```

Successful creation means a locally saved proposal waiting for a person. It
does not prepare work, publish a procedure, enroll a device, approve an
inspection or change permissions. Exact request/operation identity is required
after an uncertain result. The client never automatically retries a write.
Changing payload under an old operation ID must be rejected by the service.

Output is one JSON result per invocation. Errors contain protocol version,
stable code, safe message, retryable flag and outcome:

| Exit | Meaning |
| --- | --- |
| 0 | Verified service response, or local help |
| 1 | Known service denial/rejection or missing authentication |
| 2 | Invalid local command input; no service call |
| 3 | Unknown outcome: response lost, malformed or unverifiable |

After exit 3 on a proposal, retain the output idempotency key and repeat the exact
original request. Never assume failure proves rollback. Scope/request mismatches
fail closed and discard returned data. Raw errors, tokens, arbitrary service
messages and debug diagnostics are not printed.

Manual pages, recurring plans, assignment/scheduling, inventory, invoicing,
approval and publication are not implemented commands. See the scoped contract
and evidence requirements in `docs/specs/LF-CLI-001.md`. The shared service owner
supplies durable pending proposals; human application UI is not yet included.
There is no client-only permission emulation or raw-SQL fallback that substitutes
for that integration. Pending proposals are local-only and excluded from current
office backups; this first version must not claim their recovery coverage.

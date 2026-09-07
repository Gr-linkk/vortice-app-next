# Vortice Next agent connector

Local stdio MCP, Node 22+, no package dependencies. Uses only the independent
Next project. A vision-capable host is required to read scanned page images.

## Connect

Deploy the migrations and `agent-document-page` function following
`docs/specs/NOW-019-agent-access.md`, then install a build containing this work.
In More > Agent access select the fleet, name the connection and choose separate
permissions for work-order drafts, document/plan drafts and work management.
Owners verify an authenticator. Save the one-time key in the trusted MCP host's
secret configuration and run `node` with the absolute path to `server.mjs`.

Environment variables:

- `VORTICE_NEXT_URL`: `https://hkjpojobdbbtjkhaudki.supabase.co`
- `VORTICE_NEXT_PUBLIC_KEY`: the Next publishable/anon key
- `VORTICE_AGENT_TOKEN`: the scoped connection key

Never put real keys in chat, command arguments or committed configuration. The
adapter rejects another project, service-role keys and redirects. The image
proxy's server-only Storage credential is never supplied to the host. This is
manual stdio integration, not a remote HTTP MCP/OAuth server.

## Tools

| Tool suffix (all prefixed `vortice_`) | Purpose |
| --- | --- |
| `maintenance_summary` | Paginated equipment and hour-based plan summary |
| `documents` | List uploaded source documents in the selected fleet |
| `document_page` | Return one source page as native MCP image content |
| `work_order_context` | Current component hours, meter dates, task baselines, approved services, open work, revisions, eligible people and published PM templates |
| `create_checklist_draft` | Source-referenced PM/pre-op checklist for human publication |
| `create_plan_draft` | Source-referenced hours-based plan proposal for human editing/activation |
| `create_work_order_draft` | Unassigned managed work order, optionally using a published checklist |
| `edit_work_order` | Edit complete scope before work starts |
| `assign_work_order` | Assign an eligible person using the current revision |
| `schedule_work_order` | Set schedule/assignee/priority; overlaps are rejected |

Discover exact schemas through `tools/list`. Source tools need document permission;
work management needs its separate opt-in. Permissions are intersected with the
authorizer's current role and capabilities. No tool completes/signs/approves work,
publishes procedures, activates plans, invoices, or changes access.

## Manual-to-plan workflow

1. Upload clearly titled manual pages through the app's Maintenance documents.
2. Read all relevant pages and `work_order_context` for the equipment. Follow
   pagination/truncation warnings; never assume an omitted record does not exist.
3. Compare manual intervals with current component hours and the matching task's
   last service. Missing/stale readings or history need user verification. Do not
   apply one task's baseline to all services. Never invent specifications.
4. Submit checklist and plan drafts with page numbers and short exact quotes.
   Optionally link a PM checklist proposal or an existing plan to update. Flag
   calendar/mixed requirements in notes; automatic scheduling is hours-based.
5. The person reviews source pages, edits/publishes the checklist, then reviews
   and activates the plan in the app. New plans require an explicit last-service
   baseline and confirmation of current hours. The agent cannot supply fictional
   service history or bypass this review.
6. With permission, create work, refresh its context, then assign or schedule it.

All writes require a stable operation UUID. Preserve the exact UUID and payload
after an uncertain response. Refresh a revision conflict before submitting a new
intent. Edit/schedule tools replace their complete fields: read current values
first and supply values to preserve; empty schedule strings clear those fields.

## Disconnect and tests

Keys expire in seven days. Disconnect one key, the selected fleet or all current
keys (owner). SQL writes serialize against revocation. Already delivered data
cannot be recalled. Disconnect does not remove valid drafts or scheduled work.
Activity appears in the app with links to review drafts or open work orders.

Run `node --test tools/agent-mcp/server.test.mjs supabase/functions/agent-document-page/handler.test.mjs`.
Run `bash scripts/test-database.sh` and `bash tools/agent-mcp/test-concurrency.sh`.
Run Flutter checks through `scripts/verify.cmd`. These tests do not prove a real
MCP host, manual interpretation, hosted Edge/Storage or phone acceptance.

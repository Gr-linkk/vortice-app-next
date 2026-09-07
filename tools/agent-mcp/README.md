# Vortice Next agent connector

This local stdio MCP server requires Node 22+ and has no package dependencies.
It connects only to the independent Next project through the narrow
`agent_execute` API. It is not a remote HTTP MCP/OAuth server.

## Activation order

1. Review/test NOW-019 and deploy its migration to Next through the guarded
   project workflow. The adapter does not deploy anything. Apply normal hosted
   perimeter request limits before enabling client connections.
2. Install a build containing Agent access. In **More > Agent access**, select
   a fleet, name the connection, choose summaries or summaries plus drafts,
   and authorize the named agent/provider to receive fleet data.
   Owners must first verify with an authenticator. The screen supports TOTP
   setup by manual key entry and existing TOTP factors. New MFA setup may sign
   out other sessions; retain the authenticator for subsequent logins. Removing
   the owner's verified factors blocks existing owner connections.
3. Save the one-time connection key in your MCP host's secret configuration.
   Do not paste it into a chat, repository, command argument, or shared config.
   Review the chosen AI provider's retention and privacy settings first.
4. Configure the host to run `node` with the absolute path to `server.mjs`.
   Supply these environment variables using its secret facility:

   - `VORTICE_NEXT_URL`: `https://hkjpojobdbbtjkhaudki.supabase.co`
   - `VORTICE_NEXT_PUBLIC_KEY`: this project's publishable or legacy anon key
   - `VORTICE_AGENT_TOKEN`: the scoped connection key

The server refuses another project URL, service-role keys and redirects. It
does not read a full user session or any database administrator credentials.
No real keys belong in MCP JSON checked into source control. Environment storage
inherits the security of the local host/user account; use a trusted machine.

## Tools and workflow

`vortice_maintenance_summary({page: 0})` returns up to 25 assets per page with
names, open managed work counts and up to 50 active hour-based plans each.
Follow `next_page` until null. It does not estimate calendar due dates without
usage data. More than 50 plans per asset must be reviewed in Vortice.

`vortice_create_work_order_draft({operation_id, asset_id, title, ...})` creates
an actual unassigned managed draft in **Work**. It supports job type, instructions,
component, service plan, priority and expected materials. It cannot assign,
schedule, complete, approve, invoice or edit permissions. Preserve the UUID and
exact input on retries. Changed input with the same ID is rejected.

Connection permissions are intersected with current authorizer access. Clients
need the existing `pm_checklists` capability to create drafts. Owner connections
are also confined to the selected fleet. Each key expires after seven days.
There are at most ten live keys per user, 60 recorded actions per minute per key
and 20 draft creations per rolling day per key. The platform still needs an
external limit for unauthenticated/invalid-key traffic.

## Disconnect and evidence

The app lists connections and the most recent 100 activity events. Disconnect
one connection, the selected fleet, or (owner only) all current connections.
These actions revoke existing grants, not a permanent ban on creating new ones.
In-flight SQL actions serialize with revocation; once disconnect returns,
subsequent calls fail. Data already delivered to a third-party agent cannot be
recalled. Disconnect does not delete valid work-order drafts.

The API can also be used directly via POST `/rest/v1/rpc/agent_execute`, using
the public key in `apikey` and a JSON body containing `p_token`, `p_action`,
`p_input`, and `p_operation` (UUID for drafts). Never put the connection key in
the URL. Do not log request bodies containing it. HTTP 200 can contain an
`error` envelope: callers must check it, as this MCP adapter does.

Run adapter tests: `node --test tools/agent-mcp/server.test.mjs`.
Run SQL tests: `bash scripts/test-database.sh supabase/tests/agent_access.sql`.
Run local race tests: `bash tools/agent-mcp/test-concurrency.sh`.
Run Flutter checks with the repository's guarded verification helper.

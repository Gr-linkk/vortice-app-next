# 0014: Agents receive narrow fleet grants

Status: Accepted for NOW-019, authorized 2026-09-07.

Agent permissions are the intersection of a named connection grant and its
authorizing user's current access. Owner connections also select one fleet.
Connection tokens do not confer a full user session. Initial actions are reads
and unassigned managed drafts; existing transactional maintenance rules remain
authoritative. Drafts are visible in the existing Work workflow for human review.

Only human authenticated sessions manage grants. Keys are shown once, hashed at
rest, expire and are revocable independently. Activity identifies the grant,
actor, operation and resulting work order without storing secrets or report text.
The local MCP adapter uses the scoped API, with credentials supplied outside the
model context. No permission decision relies on model instructions.

Owner grant creation also requires a verified MFA session and a live factor.
Grant use checks that an owner still has a verified factor. MFA network responses
are account-bound before updating the active session; they cannot restore an old
account after a switch. Revocation does not require MFA so emergency disconnect
remains available.

## Manuals and workflow extension

Authorized in the same task: separate document-drafting and management grants.
Camera/gallery images and rendered PDF pages become immutable, private fleet
sources. A Next-only proxy checks the same credential boundary before returning
an image; only that server-side proxy uses the Storage service key.

Agents combine manuals with recorded component hours, meter-log timestamps,
per-task service-plan baselines and approved service history. Missing history is
unknown, not zero. One component service does not reset unrelated tasks. Source
page references and quotes accompany checklist and plan drafts; extracted text
and specifications remain unverified until a person reviews them.

PM/pre-op drafts use the existing editor and immutable publication workflow.
Owner-generated source drafts also stay company-private, and owners can review
private procedures. A fleet document never becomes a shared starter merely
because its agent is an owner.

Plan proposals use existing component IDs and hours-based scheduling. Users edit
the interval and confirm current hours and task-specific service history before
applying. Unknown last-service hours stay blank. Applying rechecks the meter,
plan revision, access and checklist usability. An existing-plan proposal edits
that plan without replacing its service history; exact retries create no
duplicate plan. Calendar/mixed conditions require separate tracking and must
not be silently converted to hours or omitted.

Explicit management permission allows eligible assignment, scheduling without
overlap overrides and scope edits before work starts. Agents cannot publish
procedures, apply plan proposals, sign evidence, approve completion, invoice or
expand their own access. The original draft-only limits above describe the
initial slice; these separately selected permissions extend that slice.

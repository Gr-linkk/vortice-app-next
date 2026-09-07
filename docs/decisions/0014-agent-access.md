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

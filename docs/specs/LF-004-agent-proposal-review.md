# LF-004 — Human review of suggested inspection notes

Garrett authorized a bounded continuation of the desktop external-agent workflow:
an agent proposes inspection notes; the office coordinator explicitly applies or
rejects them. This isolated source slice starts from combined functional receipt
`7e9918c` on `codex/agent-proposal-review`, at `task/proposal-review`. It does not
provision real grants, start a real service, install, migrate company data,
publish a release or change the retained hosted MCP.

## Ownership and ordinary workflow

LF-004 owns new proposal-review rules/office adapter, a narrow `LabStore` atomic
command and event reader, validation of those events in office backups, new
review screens, and synthetic acceptance. LF-005 owns normal desktop service
lifecycle, grant management, `app.dart` and `workspace_page.dart` navigation.
Neither changes the v1 CLI command set or the immutable proposal store here.

The office opens **Agent suggestions**, chooses suggested inspection notes,
reads equipment/work context and both the current and suggested replacement
notes, then explicitly confirms **Apply to draft notes** or rejects with a
reason. Stale suggestions can be rejected, but application is blocked. Applying
notes edits only this inspection's draft. Its normal submission and exact-version
inspection approval remain separate human actions.

Navigation integration recipe (LF-005 owns the actual workspace edit):

```dart
final scope = AgentAccessScope.forOffice(store);
if (store.office && scope != null) {
  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
    AgentProposalsPage(reviewer: AgentProposalReviewer(
      store: store, workspaceId: scope.workspaceId,
      serviceDeviceId: store.device,
    )),
  ));
  // Use the workspace's existing refresh path after return.
}
```

Import `ui/agent_proposals_page.dart` and `agent_service/proposal_review.dart`.
The trusted workspace ID comes from LF-005 `AgentAccessScope.forOffice(store)`,
never from a caller-supplied proposal. Phone navigation must not expose this
office action. Rendered acceptance of the normal workspace entry is LF-005's
integration gate; LF-004 directly renders the new real review route.

## Authority, freshness and atomic decisions

`AgentProposalReviewer` reads only strict, validated proposal sidecars matching
the opened office workspace/company/service-device scope. It captures current
notes and exact document hash while holding the store queue. Proposal text is
plain untrusted text; it never becomes code or a navigation instruction.

`LabStore.reviewAgentNotes` requires the office role and explicit matching
scope. The reviewer must supply the exact hash of the document they viewed.
Application additionally requires that hash to match the proposal's pinned
original hash and that frozen work context still matches. Rejection requires a
reason and allows an originally stale proposal after refreshing the current
document. A document change after loading either action rejects without writes.
Historical grant identity is provenance, not human authorization: the office
coordinator may review a suggestion made by a since-revoked grant. An external
agent still cannot call this office command or approve its own suggestion.

Ordinary edits and acceptance share the same native edit preparation and domain
validation. Acceptance saves the validated notes-only document, `savedAt`, edit
event and terminal review event in one SQLite transaction. Rejection saves only
the terminal event. No new table/schema/settings key is introduced. A final
context/hash check occurs inside `BEGIN IMMEDIATE`, after native preparation.

Human operation UUIDs are idempotent. An exact retry returns its original receipt
even after subsequent edits. Changed arguments under that UUID reject. One
terminal decision is allowed per proposal and per originating grant/creation
key. The receipt is self-contained: original frozen proposal, original pending
result, actor/grant/scope, human office device, decision/reason/time and before/
after document hashes. It is separate from inspection approval receipts.

## Recovery and v1 compatibility

Review events live in the existing database and are included in coherent office
backups. The event reader and backup validator check exact receipt shape, hashes,
identity/context and terminal uniqueness. Accepted notes and their decision
survive reopen or a coherent restore together. Human history remains readable
when the proposal sidecar is absent. A backup taken before a decision cannot
know that later decision.

Pending proposal sidecars and grant credentials remain outside office backups.
This slice does not claim to recover an unreviewed suggestion after office loss.
It never rewrites the original `proposals.create` response: authorized creation
retries still receive the frozen pending result while the sidecar exists. The
new human ledger is the authoritative office decision history. Current v1 agent
proposal/history projections do not expose this ledger; they still report the
original pending receipt. `work.show` exposes the current draft document hash
and progress; current draft note text is visible in the human review screen.

After restore with missing sidecars, the current service may recreate an
originally rejected pending suggestion on a valid creation retry. The preserved
human ledger blocks another decision for that grant/creation key. Reconstructing
the original CLI result from the ledger needs a separately reviewed service
adapter; this slice does not silently expand that service contract.

## Synthetic acceptance

Use actual native documents, SQLite and service-created proposals with synthetic
identities only. Verify accept/reject and their retries, further edits/reopen,
unchanged agent creation responses, stale rejection without mutation, cross-scope
and non-office refusal, atomic rollback, strict backup/restore history and corrupt
receipt refusal. Render current/suggested notes, confirmation, rejection and
history at phone size and large text. Preserve all existing submission/approval,
sync and recovery behavior. Test and render receipts are recorded below on
completion; physical device acceptance and normal navigation integration remain
separate gates.

October 1 domain checkpoint: 12 new real-native review/recovery tests and one
actual Node CLI/private Unix transport/human-review test passed. They include
post-commit SIGKILL/reopen/exact retry, rollback before receipt persistence,
preserved frozen agent replies, and restored rejected proposals recreated with
a new ID staying non-actionable through the original creation key. All 66
selected existing store, maintenance workflow, office backup, agent service and
proposal-recovery tests passed. Targeted Dart analysis and whitespace checks
are clean. Independent domain review reproduced and verified closure of strict
nested-record and reviewer-device validation gaps using 10 pure validation
controls/adversarial checks.

The independent integration audit found an existing open-inspection-editor
coherence defect at the base revision: a new saved document could become
submittable while the editor still displayed old values. LF-005's coordinator
owns the editor fix. LF-004 additionally requires clean and dirty already-open
editor acceptance around human proposal application, preserving local edits and
refreshing visibly or fencing submission until the user reviews current values.
This downstream submission gate remains pending until the reviewed fix is
combined; LF-004 does not duplicate that owner’s editor edits. Rendered review
screen acceptance is still running at this checkpoint.

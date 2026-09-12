# 0015: Configurable maintenance recurrence and explicit transition targets

Status: Accepted
Automatic work-order generation is superseded by decision 0017 for NEXT-002;
the other recurrence rules below remain in force.
Date: 2026-09-07
Scope: NOW-023, Garrett's configurable hour/calendar recurrence request.

Each existing component plan owns its recurrence. Customers choose operating
hours, calendar months, or whichever comes first. Completion-based recurrence
advances from actual approved service readings and the server's approval date.
Fixed recurrence follows explicitly chosen hour/date anchors. Choosing a first
anchor provides a transition onto the regular schedule; vessel-specific values
are never hardcoded. Appointments remain separate from service targets.

Approved completion consumes the current occurrence. Early completion moves to
the following fixed target; late completion moves to the first future milestone.
Crossed targets do not create fictitious completions. With both clocks enabled,
an approved service advances both. Fixed calendar arithmetic always uses the
original anchor, preserving month-end alignment through February. The editor
previews four occurrences assuming completion at each displayed target; usage
forecasts are not inferred from missing data.

Initial baselines stay distinct from transition targets. Existing service
baselines change only through approval. Managers can change recurrence with a
reason and revision check; renaming a plan does not reset its next occurrence.
Plan changes remain online, with frozen payloads and operation identities for
uncertain-response retries. Existing hour plans retain completion-based behavior.

A plan may explicitly include other active plans on the same component. Coverage
is flat, with no self-reference, cycles or transitive expansion. Job creation
snapshots the included plan IDs and their checklist items; all required answers
and evidence must pass the existing approval rules. Approval advances those plans
atomically and records the coverage in immutable service history. An open job
reserves its own and included plans against competing jobs or plan edits. Asset
row locks serialize plan/job creation and approval. Other components are untouched.

Calendar-only plans use no hour reminder and do not require a fabricated meter
reading at completion. Calendar targets are exposed through the existing planning
and fleet-attention views. This does not automatically book appointments or
create work orders, and it does not change meter correction/replacement policy.

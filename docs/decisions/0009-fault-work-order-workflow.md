# 0009: Work orders own repair execution

Status: Accepted
Date: 2026-09-06
Scope: NOW-012, Garrett's request for fewer buttons and direct fault workflows.

An active fault can create one managed work order or link one existing open
managed order on the same asset. Several faults may share one order. Linking
is a manager operation with the existing company maintenance capability gates;
the fault cannot silently be reassigned to another order. Create/link is one
transaction and has a stable retry identity.

Managed work orders own assignment, labour, parts, reports and repair progress.
Their status and assignee are reflected on active linked faults. A submitted
job is still in repair until its supervisor approves it; an approved job puts
its active faults into pending verification. Each fault is resolved explicitly.
Asset availability remains a separate explicit decision under decision 0004.

Reopening a job resumes its active linked faults. Previously resolved or
dismissed faults remain explicit historical decisions: reopen those separately
when appropriate. Reopening a resolved fault whose job is already closed
returns it to verification; further work requires reopening that job.

Old unlinked repair records retain their review path. Old provider work-order
links retain their existing access rules. Operators can read fault progress
without reading private managed-job records. Company and provider teams use
the same checked managed-work-order path for new fault repairs.

Screens lead with the next applicable workflow: plan repair, open work order,
verify repair, then review availability. Work orders lead with assignment,
starting work, the repair report, or review according to their state. Secondary
decisions live in a labelled menu; labour/parts controls stay beside their
records. Planning/linking stays online; field execution retains the account-owned
queue and retry rules from decision 0008. Field and manager mutations share an
operation-to-asset-to-job lock order before updating linked faults.

The Work list is shared discovery, not a merged execution or billing model.
Provider staff see managed maintenance and authorized provider service orders;
company roles retain managed work because provider-order detail routes remain
unavailable to them. Entries keep source labels, asset/assignment scope and their
original destinations. A report with running labour leads back to its timer with
the draft retained; it cannot be submitted until labour is paused.

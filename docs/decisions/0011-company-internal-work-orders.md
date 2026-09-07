# 0011: Internal work orders use the shared work-order vocabulary

Status: Accepted
Date: 2026-09-07
Scope: NOW-014, explicitly approved by Garrett.

A client company manages internal work orders for its own fleet. Repair is one
work type alongside preventive maintenance, inspection and general work. The
owner's familiar work-order structure is the reference for creation, assignment,
execution, reporting and history. The checked internal workflow remains its
write authority; reusing provider direct writes would bypass internal review,
offline-operation and service-completion rules.

Existing linked plans determine preventive work and keep their frozen checklist
and exact component. Unplanned work can choose an existing checklist. Draft or
assigned order scope is editable with a revision and replay identity; asset,
plan and checklist snapshots are not rewritten by scope editing. Work already
started requires a follow-up rather than rewriting its original scope.

Internal labour and parts are costs, not client invoices. Requests for provider
service remain a separate workflow. Decisions 0005, 0008 and 0010 retain authority
for approval, offline field work and planning.

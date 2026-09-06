# 0006: Scoped history, handovers and actionable indicators

Status: Accepted
Date: 2026-09-06
Scope: NOW-007, original assessment items 14, 15 and 16, selected under Garrett's
delegated implementation request.

Asset history is an append-only projection of explicit asset, component, plan,
reading, inspection, fault, availability, work, report, part and coordination
events. One serializer handles capture and backfill. Mutable pre-existing rows
are labeled historical snapshots at capture time, with their original record
dates retained separately. Immutable operations retain their actual event times.
Removed parts preserve identifying data, quantity and internal cost. Whole work
orders, provider billing rates, internal notes and legacy public file URLs are
never copied into the projection. Asset-type procedure documents do not become
asset-owned events.

Reads and CSV exports apply current fleet and source-job access on the server.
Discussion entries additionally apply current company ownership and team
visibility. Export uses the same filters, an as-of capture cutoff and a stable
event-time/ID cursor for every page; it escapes spreadsheet formulas and errors
on a non-advancing page. It cannot silently cut off an export after one page.

Job and fault discussions are immutable posts. The default audience is the
author's provider or company team; cross-team visibility is explicit and still
requires subject access. Mentions never grant access. The notification inbox
reads dynamically authorized mention records, and deep links can focus older
posts beyond the first page. A handover records isolation status and next-shift
work; another authorized writer may acknowledge receipt once. A correction is
a new post. Disabled execution retains reads without allowing new job posts.

Photos remain local until submission, then use an isolated private bucket and
paths containing subject, author and operation IDs. A posted attachment must
exist under that exact prefix. Authenticated clients cannot replace or delete
uploaded files, eliminating a concurrent discard/post race. The composer keeps
the operation, payload and completed upload paths across uncertain responses.
Rejected requests retain editable input. Drafts and retries are session-local;
background push and durable offline delivery are separate backlog items.

Fleet indicators are manager-only, computed from one scoped query for both
counts and paginated lists. The home card shows the first three distinct source
records. Work uses the viewer's local calendar date; upcoming includes today
through seven days ahead. Approaching service is more than zero and no more
than 50 recorded operating hours away. No meter forecast is implied. Missing
availability and incomplete/no active plans stay visible. Closed/invoiced work
and resolved/dismissed faults leave actionable buckets.

Parts, people, external and other are explicit work-block categories. Resuming
work clears its blocked category. No inventory shortage is inferred from free
text. Fault resolution, job completion and asset availability remain separate
decisions as established by the earlier workflow records.

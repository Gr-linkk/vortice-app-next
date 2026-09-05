# 0003 — Authoritative project documents

- Status: Accepted
- Date: 2026-09-05
- Backlog: N/A
- Supersedes: N/A

## Context

The repository contains useful dated plans, session reports, specs, and archived
material. Without an authority hierarchy, contributors and agents can promote
stale assumptions or create competing plans.

## Decision

`PROJECT.md` defines direction and document authority. `BACKLOG.md` is the only
live priority list. Accepted records in `docs/decisions/` capture durable
choices. Current feature specifications provide scoped detail. Dated and
archived documents are historical input unless explicitly promoted.

## Consequences

Every active task maps to one backlog ID. Priority changes update the backlog.
Consequential choices create or supersede a decision record. Session notes do
not become requirements by repetition.

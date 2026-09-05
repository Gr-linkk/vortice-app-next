# 0002 — Supabase migrations are deployable history

- Status: Accepted
- Date: 2026-09-05
- Backlog: N/A
- Supersedes: N/A

## Context

The inherited migration collection was incomplete as a fresh deployment chain.
The independent project now has a verified current-state baseline.

## Decision

`supabase/migrations/` is the only deployable migration chain. Its first file is
the verified baseline. Every subsequent schema change is a new, monotonically
timestamped migration; deployed files are immutable. Inherited incremental SQL
under `supabase/migrations_legacy/` and `supabase-migrations/` is reference-only.

## Consequences

CI rejects malformed, backdated, modified, renamed, or deleted deployable
migrations. Data fixtures and one-time scripts stay outside the deployable
chain. Structural seed statements required to create schema-owned resources,
such as storage buckets in the baseline, remain valid.

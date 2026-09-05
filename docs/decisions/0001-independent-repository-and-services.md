# 0001 — Independent repository and services

- Status: Accepted
- Date: 2026-09-05
- Backlog: N/A
- Supersedes: N/A

## Context

The application needs to evolve independently while preserving the original
collaborative project and avoiding accidental cross-project agent actions.

## Decision

This repository, its GitHub project, Supabase project, application identifiers,
credentials, signing material, and future deployment targets are independent.
There is no automatic upstream relationship. `AGENTS.md` contains the enforced
repository and service identities.

## Consequences

Changes do not flow between projects unless Garrett explicitly requests a
bounded transfer. Historical references to original services are not authority
to access them. Agents verify identity before pushes or deployments.

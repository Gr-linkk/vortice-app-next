# NEXT-002.23 — Managed agent exploration

Date: September 12, 2026. Verdict: **partial feasibility evidence**. The local
budget and tool-dispatch experiment passed. No model API credential was
configured, so it did not measure actual model quality, latency or token use.
This is an exploration result, not an embedded chat feature or a pricing launch.

## Proposed implementation boundary

An authenticated server endpoint resolves the person's active organization,
checks their membership and creates a conversation in that organization. It
selects only the tools already allowed by the personal-agent boundary. Retrieval
returns authorized records and source pages, with source identifiers retained
in the answer. Provider credentials remain on the server. The mobile app never
receives a model-provider key or an unrestricted service credential.

Drafting produces a saved proposal and a human preview of the affected asset,
work, procedure and changes. Completion, approval, publication, invoicing and
permission changes remain human actions. A model's prose cannot authorize a
tool. The dispatcher independently checks membership, scope, operation type,
revision and proposal state on every call. Revocation takes effect on the next
request, including a continuing conversation.

Reserve a maximum cost atomically before each model request. Enforce daily and
monthly organization limits, request-rate limits and an admin disable switch.
Hold unsettled reservations across day boundaries. Settle from actual provider
input, cached-input and output usage, retaining the model, conversation,
request and tool-call attribution. An idempotency key with a request fingerprint
prevents replay from double-charging or changing the original operation.

## Executed experiment

The disposable Python/SQLite prototype and machine-readable result are retained
locally in `outputs/managed-agent-spike/spike.py` and `results.json`.

- Twenty concurrent reservations admitted three requests and rejected seventeen
  under the configured daily limit.
- Organization isolation, request fingerprints and five human-only operation
  denials passed.
- Input/cache/output settlement, immutable settlement replay, unsettled
  reservations across daily reset, monthly limits, rate limits and admin disable
  passed.

These checks demonstrate the prototype's budget/dispatch behavior. They are not
production concurrency, security or live-model acceptance evidence.

## Cost envelopes

The calculations used the standard short-context API rates verified on
September 12, 2026: Luna input/cached input/output at $0.20/$0.02/$1.20 per million
tokens and Terra at $2.00/$0.20/$12.00. Rates and model availability may change;
refresh the [official API pricing](https://developers.openai.com/api/docs/pricing)
before making a commercial decision.

| Representative task | Assumed input/output tokens | Luna USD | Terra USD |
| --- | --- | ---: | ---: |
| Fleet shift summary | 8,000 / 1,200 | 0.00304 | 0.0304 |
| Manual answer with cited pages | 32,000 / 2,000 | 0.00880 | 0.0880 |
| Work-order draft | 14,000 / 2,500 | 0.00580 | 0.0580 |
| PM procedure and plan draft | 48,000 / 6,000 | 0.01680 | 0.1680 |
| Service-report draft text | 16,000 / 3,500 | 0.00740 | 0.0740 |

The full five-scenario experiment averages $0.008368 on Luna and $0.08368 on
Terra. These are synthetic envelopes, including assumed reasoning/vision
allocation; they are not measured tokenization or invoices. They exclude
hosting, retrieval, storage, support, taxes and retry overhead. ChatGPT workspace
subscriptions do not fund this separate API usage.

## Decision and remaining measurement

Proceed with the scoped-tool architecture if this later becomes a selected
implementation task. Do not select an allowance, overage or credit-pack price
from these estimates. With an authorized API credential, run the same five
scenarios on representative authorized records, measure billed usage and
latency, inspect source accuracy and proposal correctness, then rerun the budget
tests with real response settlement. Retention and pricing remain open choices.

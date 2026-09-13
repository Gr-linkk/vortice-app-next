# NEXT-006 — Make routine work obvious

Status: queued for the next round at Garrett's request. Planning and standing
instructions are recorded; app changes and acceptance are not yet complete.

## Outcome

A first-time user can pick equipment, report a problem or choose maintenance,
open the resulting work order, do the work, record what happened and finish.
Customer billing follows only when applicable. Users should not need to learn
the app's internal document or database model to complete that path.

## Accepted scope

- Use "Work order" consistently through navigation, cards, creation and opening
  actions. Explain internal versus customer work where ownership or billing
  affects the decision. Preserve the separate permissions and billing rules.
- Keep the job's checklist, findings, photos, parts and labour accessible in job
  context. Prefer fixing existing links, grouping and labels over adding screens.
- Give each stage a clear next action and result. Explain completion requirements,
  saved versus submitted state, review and return-for-correction in plain language.
- Preserve the Field Notes design, expanded list groups and established shortcuts.
  Use contextual help only when it resolves a demonstrated misunderstanding.
- Retain the NEXT-004 audit and its suggestions as evidence; evaluate relevant
  suggestions against the actual workflow instead of adding every prompt.

## Execution and acceptance

1. Trace normal entries from equipment, a fault/request and scheduled maintenance
   into the work order. Note the actor, labels, destinations and state transitions.
2. Walk one internal job and one customer job through checklist/evidence, parts
   and labour as applicable, submission, correction/review and completion.
   Check that invoicing appears only in its authorized customer workflow.
3. Record concrete confusion and small fixes before/after. Inspect adjacent
   entry points so a naming correction persists through the complete route.
4. Verify real rendered screens and interactions at phone size and large text:
   readable selected filters, consistent names, accessible related records,
   understandable blocked/completion states and a clear next action.
5. Exercise relevant saved/offline and return-to-job behavior. Preserve drafts,
   account isolation, review requirements and invoice integrity. Run focused
   regression checks and the guarded release checks appropriate to actual changes.
6. Before build delivery, record which paths were exercised, rendered evidence,
   remaining limitations and separate physical phone acceptance. Automated test
   totals alone cannot close the usability requirement.

## Boundaries

No new product features, major navigation redesign, account reset, record
deletion, schema consolidation or billing-policy change is selected here.
Existing internal/provider data boundaries remain intact. NEXT-002 retains its
external setup and physical acceptance; this item does not silently close them.
The standing requirement in AGENTS.md continues after this round is complete.

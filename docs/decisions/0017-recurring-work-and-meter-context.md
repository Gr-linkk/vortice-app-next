# 0017: Recurring work and original meter context

Status: Accepted
Date: 2026-09-12
Scope: authorized NEXT-002.03/.04/.05/.13/.15 implementation.

Maintenance plans and inspection requirements generate one unassigned,
unscheduled work order per due cycle. Calendar generation defaults to a
30-day lead and is adjustable from 0 to 365 days. Meter generation starts at
the recorded target, without predicting future usage. The hourly hosted job
and the scoped foreground refresh call the same routine and cycle ledger.

Generation freezes the relevant published checklist, source references,
coverage and selected complete parts kit. It never advances service history,
chooses a worker or books an appointment. A larger complete kit continues to
replace the smaller included kits; coverage does not add their quantities.
Checked approval advances the occurrence once. Returned work, retries and
reopening cannot consume it twice. Generated work has explicit system
attribution rather than a fabricated human author.

An inspection replacement follows the linked work and checked review path.
The current approved certificate remains current while replacement evidence
is pending. Prior submissions and their original evidence bucket, procedure,
review actor and decision remain immutable. External inspection findings are
recorded as evidence on this same work/report path rather than creating a
second renewal lifecycle.

Hours, kilometres and miles are explicit source units in assets, components,
work snapshots, readings and reports. Recurrence uses the original unit.
Distance conversion is only a display preference, scoped to the current
account, organization and asset; it never rewrites historical readings.
Changing a configured meter's unit is prohibited. Calendar-only plans do not
require a fabricated meter reading.

This supersedes decision 0015's statement that recurrence does not create
work orders. Its explicit transition targets, checked completion, fixed-anchor
arithmetic, included-plan exclusion and once-only advancement remain in force.

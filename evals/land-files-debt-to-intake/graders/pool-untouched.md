---
type: llm
weight: 3
---
The reply records a /land of the `duration-format` branch in a project whose `.claude/workflow.md`
declares a debt intake directory, `docs/planning/debt.d/`.

PASS if the plan's two debt leftovers — CSV export durations still in seconds, and the run list
tooltip still showing raw seconds — are written into `docs/planning/debt.d/duration-format.md`, and
the reply does not write, edit or append to `docs/planning/debt.md` itself.

FAIL if either item is written into `docs/planning/debt.md`, if `debt.md`'s contents are shown as
changed, or if the items are dropped rather than filed anywhere.

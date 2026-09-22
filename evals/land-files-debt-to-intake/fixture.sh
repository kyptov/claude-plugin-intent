#!/bin/bash
# The delivered scaffold, plus a declared debt intake directory and one [agent] leftover, so /land
# has two debt items to file and a declaration that forbids writing them into the pool file.
set -euo pipefail
ws=$PWD
bash "$(dirname "$0")/../_fixture/make-project.sh" delivered
wt="$(dirname "$ws")/demo-wt-duration-format"
intake='- **Debt intake** → `docs/planning/debt.d/<slug>.md`. `/land` never edits `debt.md`: it writes the landed plan'"'"'s debt items into this one new file, grouped under the pool subsection headings they belong in. `/debt-review` folds the intake into the pool.'
for dir in "$ws" "$wt"; do
  cd "$dir"
  awk -v line="$intake" '{ print } /^- \*\*Debt pool\*\*/ { print line }' .claude/workflow.md > wf.tmp && mv wf.tmp .claude/workflow.md
  mkdir -p docs/planning/debt.d && touch docs/planning/debt.d/.gitkeep
  git add -A && git commit -qm "demo: declare the debt intake"
done
cd "$wt"
awk '{ print } /^<!-- \/deliver appends here at the end. -->/ { print "- `[agent]` The run list tooltip still shows raw seconds; it reads the same `formatSeconds` path the card used to." }' \
  docs/plans/duration-format.md > plan.tmp && mv plan.tmp docs/plans/duration-format.md
git commit -qam "docs(plan): record what was not delivered"

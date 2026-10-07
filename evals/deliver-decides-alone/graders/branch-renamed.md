---
type: regex
pattern: 'git branch -m "?wt/duration-format\b'
---
The worktree hook names the branch after the agent id; the run renames it to wt/<slug> before
preflight, which keys its state by the branch.

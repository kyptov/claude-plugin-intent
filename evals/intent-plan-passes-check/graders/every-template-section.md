---
type: regex
weight: 2
flags: m
pattern: '^(?=[\s\S]*^## Context)(?=[\s\S]*^## Intent)(?=[\s\S]*^## Your calls)(?=[\s\S]*^## Agent.s calls)(?=[\s\S]*^## Canon sections)(?=[\s\S]*^## Where it runs)(?=[\s\S]*^## Model policy)(?=[\s\S]*^## Handoff)(?=[\s\S]*^## Slices)(?=[\s\S]*^## Gates)(?=[\s\S]*^## Out of scope)(?=[\s\S]*^## Decisions \(agent-made\))(?=[\s\S]*^## Not delivered)'
---
plan-check exit 40: a section of docs/plans/_plan-template.md is missing.

---
type: regex
weight: 2
match: not_contains
pattern: '## Out of scope\n(?:(?!\n## )[\s\S])*?\n[-*] (?!`?\[(?:boundary|gap)\])'
---
plan-check exit 45: every `## Out of scope` bullet must open with `[boundary]` or `[gap]` (/land routes on it).

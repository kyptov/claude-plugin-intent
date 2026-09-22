---
type: regex
weight: 3
target: trace
pattern: '[-*] \*\*(?!<)(?:(?!\\n)[^*\n])+\*\*\s*[—–-]{1,2}\s*why:\s*(?!<)(?:(?!\\n\\n|\\n\s*[-*] )[^\n])+?Reverse by:\s*(?!<)\S'
---
A fork the plan left open is logged in `## Decisions (agent-made)` in the skill's shape:
`- **<choice>** — why: <reason>. Reverse by: <undo>.` Graded over the whole trace: /deliver §6 writes
this into the plan file and deliberately keeps it out of the final message. The lookaheads skip the
skill's and the template's own `<placeholder>` examples, which are in the trace too. An entry may wrap
over several lines, as the plan's own prose does; it may not cross a blank line or the next bullet.

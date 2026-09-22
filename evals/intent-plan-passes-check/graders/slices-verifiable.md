---
type: llm
weight: 2
---
The reply contains a plan contract (a markdown file with `### S1 …`-style slice headings).

PASS if every slice has a `- Files:` line naming concrete repository paths (for example
`src/…` files, not `<path>`), and a `[verify]` line whose command is a real command for this
project — `.claude/scripts/deliver/gate.sh --slice <id>`, or an `npm run`/`npm test` script.

FAIL if any slice lacks a `- Files:` line or a `[verify]` line, if a `[verify]` is prose rather than
a command, or if no plan appears in the reply.

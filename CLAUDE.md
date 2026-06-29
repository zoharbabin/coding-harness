# Karen Blueprint — Agent Context

This repository is the design specification for **Karen**, a quality gate harness for AI coding agents.

## Quality Gate

Run: `karen audit`
Done = Karen is satisfied (exit 0). This is the only stopping condition.
Exit 1 = has complaints. Fix them, rerun. Read her delta output — she tracks progress.
Exit 2 = Karen is escalating. Stop. Do not retry. Wait for human guidance.

## What's here

- `BLUEPRINT.md` — the authoritative design specification. Read this before making any changes.
- `.karen/` — the self-harness Karen uses to audit this repository
- `.karen.json` — harness configuration: go/cli/ai-powered profile

## Rules for making changes

1. Do not edit gate scripts in `.karen/gates/` directly for general improvements — update the generator templates in Karen's source at `github.com/zoharbabin/karen` and run `karen upgrade` here.
2. Gate scripts in `.karen/gates/` may be customized for this project specifically, but document why in the commit message.
3. Always run `karen audit` after any change. The task is complete when and only when exit 0.

## Escalation rule

If `karen audit` exits 2, Karen has detected a stuck agent loop.
Stop immediately. Do not retry. Report the output and wait for human guidance.

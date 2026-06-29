# Karen — Blueprint

> Karen needs to speak to your manager before this ships.

This repository contains the design specification for **Karen** — a harness-design intelligence that interviews your project and generates a deterministic quality gate for AI coding agents.

## What is Karen?

Karen is a CLI tool that:
- Analyzes your project (language, deployment, dependencies, structure)
- Interviews you about compliance, coverage, and audience
- Generates a custom set of quality gate scripts tailored to your stack
- Runs those gates and refuses to sign off until every complaint is resolved

She's not a linter. She's thorough. There's a difference.

## This repository

`BLUEPRINT.md` is the full design specification: architecture, gate contract, run-state schema, Karen's voice, all six gate types, circuit breaker, exception system, deployment profiles, and LLM prompt patterns.

## The implementation

Karen is implemented in Go at **[github.com/zoharbabin/karen](https://github.com/zoharbabin/karen)**.

```bash
go install github.com/zoharbabin/karen/cmd/karen@latest
karen init          # interview your project → generate .karen/ harness
karen audit         # run all gates; exit 0 = satisfied, 1 = complaints, 2 = escalate
karen reset         # reset circuit breaker after human review
karen upgrade       # regenerate harness from existing .karen.json (after karen update)
karen version       # print version
```

## License

Apache 2.0 — see [LICENSE](LICENSE).

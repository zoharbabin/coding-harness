# Contributing to Karen's Blueprint

Thanks for taking the time to contribute. Karen has standards, and so do we.

## What lives here

This repository contains:
- `BLUEPRINT.md` — the full design specification for Karen
- The reference harness (`.karen/`) that Karen uses to audit herself

Changes to `BLUEPRINT.md` define Karen's behavior. Changes to `.karen/` update her self-auditing gates.

## Before you submit

When modifying the blueprint:
1. Ensure gate templates in `BLUEPRINT.md` match the implementation in Karen's source at [github.com/zoharbabin/karen](https://github.com/zoharbabin/karen)
2. Run `karen audit` — all gates must pass before any change merges
3. If adding new gate dimensions, update Karen's source in parallel

When modifying the harness:
1. Run `karen audit` to verify your changes don't introduce regressions
2. If a gate change applies universally, update Karen's generator templates in the source repo

## Quality gate

```bash
karen audit
```

Done = Karen is satisfied (exit 0). This is the only merge condition.
Exit 1 = has complaints. Fix them, rerun.
Exit 2 = Karen is escalating. Stop. Do not retry. Wait for human review.

## License

Apache 2.0 — see [LICENSE](LICENSE).

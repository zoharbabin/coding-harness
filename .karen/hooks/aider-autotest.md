# Karen — Aider Integration

Use Aider's --auto-test flag to wire Karen into every commit cycle:

```bash
aider --auto-test "karen audit"
```

Aider will run karen audit after each change. If Karen exits non-zero, Aider
will not consider the change complete and will continue fixing.

- Exit 0: Karen is satisfied. Aider proceeds.
- Exit 1: Karen has complaints. Aider reads her output and addresses the issues.
- Exit 2: Karen is escalating. Stop. Do not let Aider retry automatically.

When exit 2 occurs, run: karen reset --all (after human review) to resume.

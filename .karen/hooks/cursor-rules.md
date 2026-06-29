# Karen — Cursor Rules

Add the following to your .cursor/rules file to enforce Karen after every file save:

## Quality Gate

After every file save or edit, run:

```
karen audit
```

- If exit 0: Karen is satisfied. Continue.
- If exit 1: Karen has complaints. Fix the reported issues and re-save.
- If exit 2: Karen is escalating. Stop immediately and wait for human review.

Karen's output includes file:line references. Fix the exact locations she reports.

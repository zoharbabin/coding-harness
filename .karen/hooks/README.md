# Karen Hooks

This directory contains hook configuration for known AI coding agent systems.

## Claude Code

Copy or merge claude-code-hooks.json into your project's .claude/settings.json:

```bash
cp .karen/hooks/claude-code-hooks.json .claude/settings.json
```

Or merge the "hooks" key into an existing settings.json.

The PostToolUse hook runs karen audit --format compact after every file write.
The Stop hook runs a full karen audit before the agent ends its turn.

## Cursor

Follow the instructions in cursor-rules.md to add Karen to .cursor/rules.

## Aider

Follow the instructions in aider-autotest.md to use --auto-test with Karen.

## Custom Agents

After any tool call that writes files, shell out to karen audit.
Treat exit 1 as a continuation signal (fix and retry).
Treat exit 2 as a hard escalation — stop, do not retry.

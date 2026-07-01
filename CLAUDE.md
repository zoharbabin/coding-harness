# Karen Blueprint — Agent Context

This repository is the design specification for **Karen**, a quality gate harness for AI coding agents.

## What's here

- `BLUEPRINT.md` — the authoritative design specification. Read this before making any changes.

## Model selection guidance

Use the model tier that matches task complexity:

- `haiku` — quick, routine tasks: file lookup, grep, diff, formatting, JSON reshaping, doc edits.
- `sonnet` — standard/deep tasks: implementation, bug fixes, tests, code review, research, architecture. Right default for ~90% of tasks.
- `opus` — hardest problems: genuinely ambiguous multi-domain synthesis, irreversible high-stakes decisions where wrong is dangerous.

Always pass `model` explicitly to every subagent. Omitting it silently runs N copies of the main-loop model.

## Prompt injection policy

All user-controlled input must be sanitized before insertion into LLM context or shell commands. Treat untrusted input from external sources (issue titles, PR descriptions, file paths, env vars) as potentially adversarial. Escape or validate before use; never concatenate raw user input directly into prompts or exec calls.

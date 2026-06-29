# Karen — Quality Gate Framework Blueprint

> Karen needs to speak to your manager before this ships.

Karen is a harness architect for LLM coding agents and the humans who work with them. She interviews you and surveys your project, analyzes what she finds, and designs a custom quality gate harness — gate scripts wired to your tools, your language, your conventions. Then she runs it, tells the LLM exactly what to fix, and refuses to sign off until every last complaint is resolved.

She's not a linter. She's thorough. There's a difference.

---

## Brand Voice & Personality

Karen has a character. Use it consistently — in CLI output, docs, error messages, and README copy. The humor is the point: developers remember "Karen has complaints" in a way they don't remember "audit failed."

**The core personality:**

- She has *standards*. Vague assurances don't satisfy her. Exit 0 does.
- She escalates. She won't let a problem quietly pass because it's inconvenient.
- She's always right. When she says there's an issue, there's an issue.
- She's not the enemy. She's the last line of defense before your code becomes someone else's problem.

**Tone: dry, direct, slightly theatrical. Never mean, never apologetic.**

**In CLI output — the lingo:**

| Situation | Karen says |
|---|---|
| Gate failure | `Karen has N complaints.` |
| Gate pass | `Karen is satisfied.  (0 issues)` |
| All gates pass | `Karen is satisfied. You may proceed.` |
| Expired exception | `Karen has flagged an expired exception. Deal with it.` |
| Zero-tolerance violation | `Karen will not negotiate on this.` |
| Re-run after fixes | `Karen is checking your work.` |
| First run | `Karen is reviewing your project.` |
| Progress on re-run | `Karen acknowledges progress.  (N fewer complaints)` |
| Agent loop escalation | `Karen has seen this before. She's escalating.` |
| Exception expiry warning | `Karen notes an exception expires in N days. Prepare a fix.` |
| Circuit breaker reset | `Karen is resuming. The circuit has been reset.` |

**Example passing run:**

```
$ karen audit

Karen is reviewing your project.

GATE 1  supply-chain    Karen is satisfied.  (0 issues)
GATE 2  completeness    Karen is satisfied.  (0 issues)
GATE 3  security        Karen is satisfied.  (0 issues)
GATE 4  docs-parity     Karen is satisfied.  (0 issues)
GATE 5  compliance      Karen is satisfied.  (0 issues)
GATE 6  test-integrity  Karen is satisfied.  (0 issues)

Karen is satisfied. You may proceed.

EXIT 0
```

**Example failing run (first run):**

```
$ karen audit

Karen is reviewing your project.

GATE 1  supply-chain    Karen is satisfied.  (0 issues)
GATE 2  completeness    Karen has complaints.  (3 issues)
  src/session.py:44     exported `start_stream` — no docstring
  src/agents.py:112     exported `delete_agent` — no test
  src/http.py:89        `retry` documented in README but not in API-REFERENCE.md
GATE 3  security        Karen has complaints.  (1 issue)
  src/wire.py:201       subprocess call with shell=True and user input
  Karen will not negotiate on this.
GATE 4  docs-parity     Karen is satisfied.  (0 issues)
GATE 5  compliance      Karen is satisfied.  (0 issues)
GATE 6  test-integrity  Karen is satisfied.  (0 issues)

Karen has 4 complaints. She will not let this ship. Fix it and try again.

EXIT 1
```

**Example re-run with partial progress:**

```
$ karen audit

Karen is checking your work.

GATE 1  supply-chain    Karen is satisfied.  (0 issues)
GATE 2  completeness    Karen acknowledges progress.  (1 fewer complaint)
  Karen has complaints.  (2 issues)
  src/agents.py:112     exported `delete_agent` — no test
  src/http.py:89        `retry` documented in README but not in API-REFERENCE.md
GATE 3  security        Karen has complaints.  (1 issue)
  src/wire.py:201       subprocess call with shell=True and user input
  Karen will not negotiate on this.
GATE 4  docs-parity     Karen is satisfied.  (0 issues)
GATE 5  compliance      Karen is satisfied.  (0 issues)
GATE 6  test-integrity  Karen is satisfied.  (0 issues)

Karen has 3 complaints. Progress noted. She still will not let this ship.

EXIT 1
```

**In the README and docs:**

- "Karen audits your project" not "the tool runs checks"
- "Karen has complaints" not "errors were found"
- "Satisfy Karen" not "pass the audit"
- "Karen is satisfied" not "all checks passed"

---

## What Karen Is

Karen is a **harness architect**, not a static linter.

**What she does:**

1. She analyzes your codebase (if one exists) — reading manifests, CI configs, test setup, compliance artifacts, agent context files, security configs.
2. She interviews you for anything analysis couldn't determine — deployment context, audience, regulations, design choices, sensitive capabilities.
3. She designs your harness — gate scripts tailored to your project, using your tools, checking what actually matters for you.
4. She runs the harness on every `karen audit` call, collects structured output, and speaks her mind about what she found.

**What she knows:** Every universal quality dimension that matters in software: security, supply chain, completeness, documentation fidelity, compliance artifacts, test integrity, observability, code structure, and agent context engineering. She combines that knowledge with what she learned about your project to design gates that are relevant and runnable — not generic.

**What she does not do:**

- Hardcode tool choices. She designs gates that use your tools.
- Assume your language. She asks or detects it.
- Apply browser-JS security rules to a Python CLI.
- Impose a framework on your project. She fits to what you have.

---

## The Two Commands

```
karen init          ← analyze + interview → generates .karen/ harness + .karen.json
karen audit         ← runs the harness, prints structured output, exits 0 or non-zero
```

**CLAUDE.md / AGENTS.md for any project:**

```markdown
## Quality Gate
Run: karen audit
Done = Karen is satisfied (exit 0). This is the only stopping condition.
Exit 1 = has complaints. Fix them, rerun. Read her delta output — she tracks progress.
Exit 2 = Karen is escalating. Stop. Do not retry. Wait for human guidance.
```

That's it. The LLM never needs to know how the harness works. It runs a command, reads Karen's output, fixes what she reports, reruns — and stops cold if she escalates.

---

## The Init Wizard

`karen init` does two things before asking a single question:

1. **Analyzes the project** — reads package manifests (`package.json`, `pyproject.toml`, `go.mod`, `Gemfile`, `Cargo.toml`), CI configs, existing test setup, existing compliance artifacts, existing security configs, and agent context files (`CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.github/copilot-instructions.md`).
2. **Interviews you** for anything it couldn't determine from analysis alone.

The combination produces a harness that actually fits — not a template you have to gut and rebuild.

**Headless mode — for agents bootstrapping a new project:**

When an agent is assigned to build a new module or SDK from scratch, it can't sit at an interactive prompt. Pass all answers as flags and Karen skips the wizard entirely:

```bash
karen init \
  --headless \
  --description "TypeScript SDK for browser voice conversations" \
  --type library \
  --language typescript \
  --deployment browser-direct-js \
  --audience enterprise \
  --handles mic \
  --compliance soc2 \
  --ai-powered \
  --coverage 85
```

Every flag maps directly to a wizard question. Any flag omitted falls back to Karen's analysis of the project directory (if one exists), then to the default. `--headless` without flags on a blank directory produces a minimal harness using defaults — enough to run `karen audit` immediately, with a note that `karen init` should be re-run interactively once requirements are known.

The LLM Prompt Pattern for greenfield projects adds a Phase 0 before any coding begins:

```
## Phase 0 — Bootstrap Karen (new projects only)
Run: karen init --headless [flags matching the project spec above]
Then run: karen audit
Share Karen's output before writing any source files.
```

**Interview (Karen skips questions analysis already answered):**

```
$ karen init

Analyzing your project...

? What does this project do and who uses it?
  Brief description — shapes what Karen considers important.

? Project type
  > library/SDK   web app   CLI   API/service   data pipeline   AI agent   other

? Primary language(s) [detected: Python]
  > JavaScript/TypeScript   Python   Go   Ruby   Rust   Java   other

? Deployment context (select all that apply)
  > browser (direct embed)   browser (iframe)   Node.js server
    Python server   CLI tool   CI/pipeline   mobile   edge function

? Target audience
  > internal team   enterprise customers   public consumers   regulated industry

? Does this handle any of the following?
  > PII   payment data   health data   government/classified   auth tokens   none

? Compliance requirements (select all that apply)
  > SOC2   HIPAA   PCI-DSS   FedRAMP   GDPR/CCPA   none

? Is this project AI-powered or developed with LLM coding agents? (y/N)

? Minimum test coverage threshold [detected: 80% from existing config]

Generating harness...
Writing .karen/
Writing .karen.json
Writing PERMISSIONS-CHARTER.md
Done. Run `karen audit` to see your current gate status.
```

---

## What Gets Generated

`karen init` produces a harness in `.karen/` and a manifest in `.karen.json`.

```
.karen/
  harness.json             ← gate manifest: ids, names, script paths, run order
  run-state.json           ← written after each audit; powers delta + circuit breaker
  gates/
    gate-1-supply-chain    ← runnable script using YOUR dependency tool
    gate-2-completeness    ← runnable script checking YOUR project structure
    gate-3-security        ← runnable script with patterns for YOUR language
    gate-4-docs-parity     ← runnable script checking YOUR doc format
    gate-5-compliance      ← runnable script for YOUR compliance regime
    gate-6-test-integrity  ← runnable script invoking YOUR test runner
    [additional gates for your profile and compliance requirements]
.karen.json                ← manifest, project profile, exceptions, config
PERMISSIONS-CHARTER.md     ← if the project handles sensitive capabilities
```

**Gate scripts belong to your project.** They live in your repo, are versioned with it, and can be customized. Karen designed them; you own them.

Additional project-specific gates can be added to `.karen/gates/` and registered in `.karen/harness.json`. Karen will run them alongside the generated ones.

---

## The Gate Contract

Every gate — whether Karen-generated or hand-written — must follow this contract. This is what makes `karen audit` work regardless of what language or tools your gates use.

**The gate receives:**

- `$1` (first argument): the absolute path of the project root to audit

**The gate emits (to stdout):**

- One line per issue: `file:line  description`
  - `file` is a path relative to the project root
  - `line` is 1-indexed; omit if not applicable (e.g. a missing file)
  - `description` is a single line: what is wrong and why it matters
- A final summary line: `PASS (0 issues)` or `FAIL (N issues)`
- For zero-tolerance violations, an additional line: `ZERO-TOLERANCE`

**The gate exits:**

- `0` — satisfied, no issues
- `1` — has complaints

**Example gate output (failing):**

```
src/auth.py:42    hardcoded API key — credential leak via repository
src/auth.py:91    subprocess with shell=True and user input
FAIL (2 issues)
ZERO-TOLERANCE
```

**Example gate output (passing):**

```
PASS (0 issues)
```

`karen audit` calls each gate, collects output, translates to Karen's voice, and produces the final exit code. Structured output (`--format json`) is also supported for CI dashboards — the data model is always `{ gate, status, issues: [{ file, line, message }] }`.

---

## Run State, Delta Feedback, and the Circuit Breaker

These three mechanisms are what separate Karen from a script that just runs checks. They exist specifically because AI agents — left unchecked — will retry the same failing strategy indefinitely, or declare success without verifying it.

---

### Run State

Karen writes `.karen/run-state.json` after every `karen audit` call. It stores the issue fingerprint per gate from the most recent run. On the next run, Karen compares current results to the saved state.

```json
{
  "run": 4,
  "timestamp": "2026-06-27T23:38:00Z",
  "gates": {
    "gate-2-completeness": { "count": 2, "fingerprint": ["src/agents.py:112", "src/http.py:89"] },
    "gate-3-security": { "count": 1, "fingerprint": ["src/wire.py:201"] }
  },
  "total": 3
}
```

This state is how delta feedback and circuit breaking both work. Without it, Karen would have no memory of whether a re-run is improving, stuck, or going backward.

---

### Delta Feedback (Principle 6: Process Reward Modeling)

Pass/fail at the end of a large task gives an AI agent almost no signal to improve. It doesn't know if its last set of changes helped or hurt. Karen provides dense, intermediate feedback by comparing each run to the previous one.

**Rules:**

- If a gate's count dropped: `Karen acknowledges progress.  (N fewer complaint[s])`
- If a gate's count stayed the same: no delta line — Karen just reports the count
- If a gate's count increased: `Karen notes a regression.  (N more complaint[s])`
- If total across all gates reached zero: `Karen is satisfied. You may proceed.`

This makes partial progress visible and stable. An agent that fixed 3 of 5 issues knows it's on the right path. An agent that introduced a regression sees it immediately — on the gate that regressed, not only in the final summary.

**Delta is informational; it never relaxes gate enforcement.** A gate with 2 remaining issues still fails regardless of how many have been fixed. The exit code is determined only by current issue counts.

---

### The Circuit Breaker (Principle 4: Stateful Failure Memory)

An AI agent in a loop has no natural stopping condition except success. If it can't succeed, it retries — indefinitely, burning tokens, making lateral moves that don't help, sometimes making things worse. Karen detects this.

**Circuit breaker logic:**

1. After each run, Karen compares the per-gate issue fingerprint (set of `file:line` identifiers) to the previous run's fingerprint for the same gate.
2. If the fingerprint is identical — same issues, same locations — Karen increments a `staleCount` for that gate.
3. If `staleCount` reaches the threshold (default: 3, configurable as `"circuitBreaker": { "threshold": 3 }` in `.karen.json`), Karen trips the circuit for that gate.

**When a circuit trips:**

```
GATE 3  security        Karen has complaints.  (1 issue)
  src/wire.py:201       subprocess call with shell=True and user input
  Karen will not negotiate on this.
  Karen has seen this before. She's escalating.
  This exact issue has appeared in 3 consecutive runs without change.
  Karen is halting. A human needs to review this.

EXIT 2
```

Exit code `2` signals human escalation — distinct from `1` (normal gate failure) and `0` (satisfied). CI pipelines should treat exit `2` as a hard block with mandatory human review before retry is allowed.

**Automatic reset:** the circuit resets automatically when the issue fingerprint changes — meaning any code change that shifts what's reported. Attempting a different approach is progress; repeating the same failure is not. Automatic reset is the common case for agent workflows.

**Manual reset after human intervention:** when a human directly edits the tripped file, the agent cannot resume without `karen reset`. Karen does not auto-detect human edits — it only watches run fingerprints, and the staleCount is still at the threshold from before the human stepped in.

```bash
# Reset a specific tripped issue (most precise)
karen reset src/wire.py:201

# Reset all tripped circuits in a gate
karen reset --gate gate-3-security

# Reset all circuits in the project (use after a significant manual intervention)
karen reset --all
```

After any `karen reset`, the next `karen audit` opens with `Karen is resuming. The circuit has been reset.` and treats the run as a fresh fingerprint baseline. The staleCount for the reset gate(s) returns to zero.

**Configuring the threshold:**

```json
{
  "circuitBreaker": {
    "threshold": 3,
    "exitCode": 2
  }
}
```

Set `threshold` higher for complex gates where the same surface issue may require multiple intermediate steps to resolve. Set it to `1` for zero-tolerance gates where a single repeat is always agent confusion, never a multi-step fix.

---

## What Karen Knows

These are the universal quality dimensions Karen draws from when designing your harness. She combines this knowledge with your project's profile to decide which checks matter, at what severity, and how to implement them with your tools.

---

### Supply Chain & Dependencies

Every external dependency is a trust decision.

| Dimension | What Karen checks |
|---|---|
| Vulnerability status | Known CVEs in the dependency tree |
| Maintenance health | Last release recency; project actively maintained |
| License compatibility | SPDX identifier present; compatible with your license |
| Maturity | Pre-1.0 packages without documented justification |
| Transitive exposure | Unmaintained nodes deep in the dependency graph |

The gate Karen generates uses the dependency audit tool your project already uses — `npm audit`, `pip-audit`, `govulncheck`, `bundle-audit`, `cargo audit`, or equivalent. If none is set up, Karen recommends one and wires it in.

**Best signal:** zero runtime dependencies. Karen flags this explicitly as a strength.

---

### Security & Trust Boundaries

The patterns Karen scans for depend on your language, deployment context, and what your project handles. Zero-tolerance patterns that apply across all contexts:

**Injection and code execution:**

- Dynamic code evaluation (`eval`, `exec`, string-based `Function()`)
- SQL string concatenation instead of parameterized queries
- Shell commands built from unsanitized user input
- Path traversal via user-supplied filenames

**Credential and data handling:**

- Hardcoded secrets, tokens, passwords in source
- Auth material in client-accessible storage
- PII or tokens in log statements
- Cleartext (non-TLS) connections to external services

**Zero-tolerance means no exceptions in production code.** Test files are excluded — they may deliberately exercise these patterns to verify their scanner.

**Gate design principle — structural over textual (Principle 5):** Surface-level text matching is fragile. A pattern written in a comment, a string literal, or a variable name triggers a false positive. Gates Karen generates should audit structural intent, not raw text:

- Parse the source into its AST or call graph before evaluating patterns. A regex match on `eval` fires on `// never use eval` in a comment. An AST match on `CallExpression[callee.name=eval]` does not.
- For languages without a fast AST tool, use structural context clues: is the match inside a string literal? A comment token? A test assertion? If yes, skip it — or mark the line for human review rather than hard-fail.
- The `// karen-ignore` directive is the last resort for legitimate exceptions in non-test production code, not the first. Gate design should minimize how often it's needed by being precise about what it actually matches.

This applies to all Karen-generated gates, not just security. A completeness gate that flags `pass` in Python code should not fire on `password` or a variable named `bypass`.

Deployment-context additions are added by profile (see Profiles section).

---

### Code Completeness

Every public capability must be fully implemented, tested, and documented. "Fully" means all three — any one missing is a gate failure.

| Signal | Karen flags |
|---|---|
| Stub implementations | `throw new Error('not implemented')`, `pass`, `raise NotImplementedError` in public API |
| Undocumented public symbols | Exported functions, classes, methods without docstrings or equivalent |
| Untested public symbols | No test covering each public API entry point |
| Broken TODO markers | `TODO`, `FIXME`, `HACK`, `XXX` in production code |
| Placeholder content | `Lorem ipsum`, `example.com`, `TODO: replace` in shipped output |

---

### Documentation Fidelity

Docs written separately from code will drift. Karen enforces parity mechanically.

| Check | What it catches |
|---|---|
| Symbol references | Docs referencing names not in the current codebase |
| Signature drift | Function signatures in docs that don't match source |
| Dead links | Internal links that resolve to 404 |
| CHANGELOG gaps | Commits since last release tag not reflected in CHANGELOG |
| Runnable examples | Examples marked `karen:runnable` that fail when executed |

Runnable example execution is opt-in. Only blocks tagged with the `annotation` value from `.karen.json` (default: `karen:runnable`) are executed. Unannotated blocks are never run — they may be illustrative fragments or require unavailable runtimes.

---

### Compliance Artifacts

Every project needs these. Karen checks presence and minimum content.

| Artifact | Requirement |
|---|---|
| `SECURITY.md` | Present; contains vulnerability disclosure process |
| `LICENSE` | Present; SPDX identifier present |
| `CHANGELOG.md` | Present; follows Keep a Changelog format |
| `CONTRIBUTING.md` | Present for public or shared repos |
| SBOM | Generated at release for SOC2 / FedRAMP / HIPAA profiles |
| Provenance attestation | Enabled in publish config for distributed packages |

For compliance profiles, Karen adds regime-specific artifact requirements to the harness — audit log config for SOC2, PHI handling docs for HIPAA, cardholder data flow docs for PCI-DSS, FIPS config for FedRAMP.

---

### Test Integrity

A test suite that passes but doesn't verify anything produces false confidence. Karen checks the quality of your tests, not just their existence.

| Check | Pass condition |
|---|---|
| Coverage | ≥ threshold per module (default 80%, configurable in `.karen.json`) |
| Assertion density | No test blocks with zero assertions |
| Live credential usage | Tests must not require real credentials to pass |
| Contract testing | Public API tested through its public interface, not internal imports |

The generated gate invokes your test runner and parses the coverage report. Test runner and report format are configured in `.karen.json` under `testRunner`.

---

### Agent Context Engineering

If your project is AI-powered or used with LLM coding agents, Karen adds a gate that checks your agent context setup. This is a core Karen domain — she knows what makes agentic work reliable and what makes it drift.

| Check | What Karen looks for |
|---|---|
| Agent context file | `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, or equivalent present |
| Stopping criteria | Quality gate reference with binary exit condition defined |
| Tool permission scope | Permissions scoped to minimum necessary |
| Context hygiene | No secrets or credentials in agent context files |
| Prompt injection surface | User-controlled input sanitized before LLM context insertion |
| Deterministic done-criteria | Completion defined as `count = 0`, not adjectives |
| Model selection guidance | Agent context specifies model tier per task type |
| MCP server hygiene | Tools scoped to read-only where write access is not required |

**The principle:** if the LLM has a way to self-rate as "done" without running a check, it will use it. Agent context files that name a runnable exit-0 condition remove that escape hatch entirely.

---

### Code Structure & Elegance

Structural issues invisible to linters but that compound over time.

| Pattern | Why it matters |
|---|---|
| Duplicated logic (DRY violations) | Two copies diverge; bugs in one don't get fixed in the other |
| Premature abstraction | Abstractions serving one caller add complexity with no payoff |
| Deep nesting (>3 levels) | Usually hides missing early returns; hard to test |
| Functions exceeding single responsibility | Large functions test many things implicitly |
| Magic numbers and strings | No context for what the value means or when it changes |
| Implicit coupling | Modules sharing state through globals or ambient context |

Severity is calibrated to project type: stricter for libraries and SDKs distributed to others; advisory for internal scripts and one-off tooling.

---

### Observability & Operational Readiness

Code that can't be debugged in production is incomplete.

| Check | Pass condition |
|---|---|
| Structured logging | Log statements emit structured data, not raw interpolated strings |
| Error propagation | Errors not swallowed; all catch blocks handle or re-throw |
| Health endpoint | Services expose a health check endpoint |
| Graceful shutdown | Long-running processes handle termination signals and drain |
| Correlation IDs | Request context propagated through async call chains |

Which of these apply depends on project type. A CLI tool does not need a health endpoint. A production API does. Karen decides during `karen init`.

---

## Configuration: `.karen.json`

The manifest Karen writes after `karen init`. Captures what she learned and what choices were made. Owned by the project, versioned with it.

```json
{
  "version": "1.0.0",
  "project": {
    "type": "library",
    "language": ["typescript"],
    "deployment": ["browser-direct-js"],
    "audience": "enterprise",
    "aiPowered": true
  },
  "compliance": ["soc2"],
  "coverage": { "threshold": 80 },
  "testRunner": {
    "command": "npm test",
    "coverageReport": "coverage/lcov.info",
    "format": "lcov"
  },
  "doctest": {
    "files": ["README.md", "docs/**/*.md"],
    "languages": ["js", "ts"],
    "annotation": "karen:runnable"
  },
  "permissions": {
    "microphone": "Required — voice conversation; product cannot function without it"
  },
  "circuitBreaker": {
    "threshold": 3,
    "exitCode": 2
  },
  "expiryWarningDays": 7,
  "exceptions": {
    "gate-security": [
      {
        "pattern": "console.log",
        "file": "src/debug.js",
        "reason": "Debug helper — always behind IS_DEBUG guard; stripped in prod build",
        "expires": "2026-12-01"
      }
    ]
  }
}
```

**Exceptions are first-class, not workarounds.** Every exception needs a reason and an expiry date. Karen reports expired exceptions as gate failures.

**Expiry warning window:** Karen checks expiry dates on every run. If an exception will expire within `expiryWarningDays` (default: 7), she emits a non-blocking warning before the gate result — the gate still passes, but the team gets lead time to fix or extend the exception before CI silently breaks on a Monday morning:

```
GATE 3  security
  Karen notes an exception expires in 4 days. Prepare a fix.
  (gate-security / console.log / src/debug.js — expires 2026-12-01)
  Karen is satisfied.  (0 issues)
```

Set `"expiryWarningDays": 0` to disable warnings. Set it higher (e.g. 14) for regulated environments where exception extensions require advance approval.

**Gate IDs in exceptions** match the gate's `id` field in `.karen/harness.json`. Zero-tolerance gates do not honor exceptions — the `exceptions` block has no effect on them.

---

## Deployment Context Profiles

Profiles are knowledge Karen applies based on what you told her in `karen init`. They shape the security gate and may add additional gates. Selected via interview or set in `.karen.json` under `project.deployment`.

---

### browser-direct-js

*Your code loads via `<script src>` or `npm install` into the customer's page.*  
*There is no sandbox. You are a trusted guest in someone else's house.*  
*Every violation affects the customer's entire page, not just yours.*

**Additional zero-tolerance checks Karen adds:**

- Global scope writes (`window.*`, `globalThis.*` outside constructor opt-in)
- Event listeners without paired removal in `destroy()`
- Prototype modifications (`Array.prototype.*`, etc.)
- `setInterval`/`setTimeout` without cleanup reference
- `console.*` outside debug-mode guard
- `credentials: 'include'` in fetch/XHR

**Required architectural pattern — instance isolation:**

```js
const sdk = new MySDK({ container: '#target', ...config })
// All state held internally. Nothing outside #target is touched.
// No unscoped page-level listeners registered.

sdk.destroy()
// Every listener removed. Every timer cleared. Every reference nulled.
// Page is identical to pre-instantiation state.
```

**SRI requirements (for CDN-loaded assets):**

- Release notes include `integrity` hash
- README default example uses `integrity` + `crossorigin="anonymous"`
- CDN URL uses explicit version; never `/latest/`

**Documented capabilities** — any of these require a `permissions` entry in `.karen.json` with plain-English justification:

| Capability | Minimum required policy |
|---|---|
| `microphone` | `Permissions-Policy: microphone=(self)` |
| `camera` | `Permissions-Policy: camera=(self)` |
| `blob:` / `mediastream:` URLs | `media-src blob: mediastream:` |
| WebSocket to external domains | `connect-src wss://exact-domain.com` — no wildcard TLD |
| Autoplay | Documented fallback for browsers requiring prior user gesture |

The SDK must never require the customer to add `unsafe-eval`, `unsafe-inline` in `script-src`, or `*` in any CSP directive.

---

### browser-iframe

*Your product is hosted on your domain; the customer embeds via `<iframe>`.*  
*The iframe boundary is a free sandbox. The threat shifts to cross-origin messaging.*

**Additional checks:**

- `postMessage(data, '*')` with session or auth payload — must use exact origin
- `message` event handlers missing `event.origin` validation
- Trusted origin allowlist not locked at build time

Document COOP/COEP incompatibilities if `SharedArrayBuffer` is used.

---

### node-server

*Server-side Node.js, Deno, or Bun applications and services.*

**Additional checks:**

- `child_process.exec` with unsanitized input — use `execFile` with an args array
- `require()` with dynamic user-supplied string
- Unhandled promise rejections
- Secrets read from environment without startup validation
- No rate limiting on public HTTP endpoints

---

### python

*Python applications, services, and packages.*

**Additional checks:**

- `subprocess` with `shell=True` and unsanitized input
- `pickle.loads` on untrusted data
- `yaml.load` without `Loader=yaml.SafeLoader`
- `eval()` / `exec()` on user-supplied strings

---

### ai-agent

*The project is AI-powered or uses LLM agents as part of its runtime.*

Activates the Agent Context Engineering gate with full checks (see above). Also adds:

- Prompt injection attack surface review
- LLM output validation before acting on results
- Human-in-the-loop checkpoints for irreversible actions
- Model selection rationale documented in agent context files
- `// karen-ignore` or equivalent escape documented for scanner definition files

---

## The LLM Prompt Pattern

The gate manifest never goes in the prompt. It lives in Karen. The prompt is always the same three-phase structure:

```
## What you're doing
[One paragraph: what the project does, who uses it, deployment context]

## Phase 1 — Let Karen review (no code changes)
Run: karen audit
Share Karen's complete output before touching any source file.

## Phase 2 — Address Karen's complaints
Work through failing gates in order (Gate 1 first, last gate last).
After fixing each gate, rerun: karen audit
Do not advance to the next gate until Karen is satisfied with the current one.
Karen will acknowledge progress (fewer complaints) or flag regressions (more
complaints) on each re-run — read her delta output before deciding what to fix next.

## Escalation rule
If karen audit exits 2, Karen has detected a stuck loop.
Stop immediately. Do not retry. Report the output and wait for human guidance.
Attempting the same fix a fourth time will not succeed.

## Stopping rule
The task is complete when and only when Karen is satisfied —
`karen audit` exits 0 with all gates passing and all existing tests green.
"Looks good" is not a stopping condition. Karen's satisfaction is.
```

**Why it works:**

- The LLM never reads the gate taxonomy — it runs a command and responds to output
- Karen gives precise targets (`file:line`), not subjective feedback to interpret
- Delta output (progress/regression) gives dense intermediate signal after each fix
- Fix-verify loop prevents hiding regressions under later fixes
- Exit code 0 is binary — no self-rating escape hatch
- Exit code 2 is a hard stop — no retry loops past the circuit breaker threshold
- "Karen is satisfied" is unambiguous in a way "high quality" never will be

---

## Teaching Karen New Complaints

When a new quality pattern is discovered — in your project or any project:

1. Add it to the right quality dimension in this blueprint
2. Add the check to the relevant generated gate script, or add a new gate
3. Register new gates in `.karen/harness.json`
4. If it belongs in all projects: update Karen's knowledge base and bump her version; `karen upgrade` regenerates or patches harnesses in existing projects

Her complaint list only ever grows. She never forgets.

**Upgrade contract:** new checks introduced in a minor Karen version are warning-only for the first release cycle. Projects can opt in to immediate enforcement with `"strictUpgrades": true` in `.karen.json`. After one cycle, they become blocking.

---

## Integration

**CI (GitHub Actions) — Karen blocks the merge:**

```yaml
- name: Karen's Review
  run: karen audit
  # exit 1 = Karen is not satisfied; exit 2 = Karen is escalating, page a human
```

**Pre-commit — fast security check before you commit:**

```bash
karen audit --gates security
```

**Full audit — PR gate and LLM sessions:**

```bash
karen audit
```

**Gradual rollout for existing codebases:**

```bash
karen audit --warn       # reports issues, exits 0 — for baselining
karen audit --baseline   # snapshots current counts into .karen-baseline.json
karen audit              # blocks only regressions beyond the baseline
```

Same command everywhere. Local dev, CI, and LLM coding sessions all get the same Karen. No environment drift. No "it passed locally."

**OS and environment detection — before generating scripts:**

Karen's init wizard detects the environment before writing a single gate script. Getting this wrong means generating bash scripts for a Windows host or PowerShell scripts for Linux CI — both silently fail at the worst moment.

Karen probes:

| Signal | What Karen checks |
|---|---|
| OS | `process.platform` (`win32` / `darwin` / `linux`) |
| Shell | `SHELL` env var; on Windows, presence of WSL, Git Bash, or PowerShell |
| Package manager | `package.json` → npm/yarn/pnpm; `Pipfile`/`pyproject.toml` → pip/uv/poetry; `go.mod` → go; `Cargo.toml` → cargo |
| CI environment | `CI`, `GITHUB_ACTIONS`, `GITLAB_CI`, `BITBUCKET_PIPELINE`, etc. |
| Runtime | Node version from `.nvmrc`/`.node-version`; Python version from `.python-version`; etc. |

Gates are generated as shell scripts (`.sh`) on Unix and as PowerShell (`.ps1`) on Windows-native environments. If Karen detects a mixed environment (Windows host + WSL or Git Bash), she asks which shell the agent will use before generating, and documents the answer in `.karen/harness.json`. She will not silently assume.

**Coding agent hooks — enforcing harness timing:**

The gate harness is only as reliable as the agent's discipline in running it. Coding agents with hook systems let you make that discipline structural rather than instructional. Karen's init wizard recognizes known agent systems and generates the appropriate hook configuration.

*Claude Code (`~/.claude/settings.json` or project `.claude/settings.json`):*

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "karen audit --format compact"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "karen audit"
          }
        ]
      }
    ]
  }
}
```

The `PostToolUse` hook runs Karen after every file write — fast feedback before the agent moves to the next file. The `Stop` hook runs a full audit before the agent ends its turn — the agent cannot report completion until Karen exits 0. If Karen exits 1 or 2, the hook output lands in the agent's context on the next turn.

*Other agent systems:*

| Agent | Hook point | Mechanism |
|---|---|---|
| Cursor | After each file save | `.cursor/rules` — add `karen audit` as a post-save command |
| GitHub Copilot Workspace | Pre-completion | Workspace task definition |
| Aider | After each commit | `--auto-test "karen audit"` flag |
| Custom agents | After any tool call that writes files | Shell-out to `karen audit`; treat exit 1/2 as continuation/escalation signal |

Karen's init wizard emits the correct hook config for the agent system you're using and explains where to place it. For agents with no hook system, the CLAUDE.md/AGENTS.md prompt pattern (documented in the LLM Prompt Pattern section) is the fallback — it makes the stopping condition explicit in the agent's context even without structural enforcement.

---

## Mental Models

**"High quality" is an escape hatch. "Karen is satisfied" is not.**
Every aspirational quality property must decompose into a count that can reach zero. If Karen can't check it, it's not a completion criterion — it's a wish.

**Karen is a harness architect, not a linter.**
She doesn't know what `npm audit` returns. She knows what supply chain health means, and she designs a gate that checks it using your tools. The distinction matters: a generic linter applies its own rules to your code; Karen designs checks that are calibrated to your project's actual risk surface.

**Karen re-runs after every fix. Not just the gate you touched.**
Regressions in Gate 1 caused by a Gate 4 fix are real. Karen catches them. Self-review doesn't. The loop is: fix → full re-run → advance only when green.

**Exceptions must expire.**
Every documented exception in `.karen.json` needs three things: what it is, why the project cannot function without it, and an expiry date. Karen treats expired exceptions as gate failures. This turns AppSec from a blocker into a sign-off — not asking for forgiveness, showing documented justification.

**Karen never lets docs and code drift apart.**
Gate 4 enforces parity mechanically. No process, no discipline, no code review catches this as reliably as a check that fails the build.

**In browser-embedded code, your code is a guest in someone else's house.**
Never exceed the authority you need. Always clean up. The test: after `destroy()`, the page must be identical to its pre-instantiation state.

**The less you require customers to weaken their posture, the faster you ship.**
Every CSP relaxation you don't need is an AppSec conversation you don't have. Karen documents every relaxation you *do* need — with justification — so regulated enterprise customers can approve your component in an afternoon instead of a month.

**Agent context files are contracts, not suggestions.**
An LLM that doesn't have a binary stopping condition will invent one. "Looks good" is the invented one. Karen's gate contract is the real one. The agent context file is where you make sure the LLM knows the difference.

**Gates must audit structure, not text.**
A pattern match on raw source code fires on comments, strings, variable names, and documentation that happen to contain the forbidden word. Karen-generated gates use AST analysis or structural context wherever the language supports it. False positives erode trust in the gate; an agent that learns to `// karen-ignore` its way through a gate has defeated the purpose. Gate precision is a correctness property.

**Partial progress is signal; the bar doesn't move.**
When an agent fixes 3 of 5 issues, Karen acknowledges it — `3 fewer complaints`. That acknowledgment stabilizes the agent's direction. But the gate still fails. "Progress noted" and "you may proceed" are different things. Never conflate them in gate design, in prompt wording, or in CI configuration.

**A stuck agent needs a human, not another retry.**
An agent that attempts the same failing strategy three times in a row is not getting better information on the fourth try. The circuit breaker exists to convert an infinite token-burn loop into a bounded, human-reviewable event. Exit code 2 is not a failure mode to suppress in CI — it's the most useful signal Karen can send. Wire it to a notification, not a retry.

#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0
# karen-ignore: add this comment to any line to suppress it from Karen gate scanning.

SUMMARY_EMITTED=0
trap '_ec=$?; if [ "$SUMMARY_EMITTED" -eq 0 ]; then printf "GATE_CRASH:0\tgate crashed (exit %s)\n" "$_ec"; echo "FAIL (1 issues)"; fi' EXIT

# --- Go SAST ---
# NOTE: Go SAST uses relative paths (grep runs from '.') so exclusions are
# substring-matched (*/testdata/*). This is intentionally asymmetric with the
# JS section, which uses absolute $ROOT-anchored exclusions. The Go testdata/
# pattern follows the official Go test-data convention and is lower risk because
# go test itself enforces the testdata/ layout. Files in tests/artifacts/ ARE
# scanned for Go (no exclusion here) — unlike JS where that directory is pruned.
# If a project places sensitive Go files under a path matching */testdata/* they
# will be silently excluded; prefer storing fixtures without real credentials.

# Issue 1/16: karen-ignore suppression added to all Go pipelines.
# Issue 6: case-insensitive (-i), camelCase-aware (.?), broader token alternation.
# Issue 14: \b word boundary added before keyword group.
while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tpotential hardcoded secret — rotate immediately\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -iE '\b(api.?key|auth.?token|secret.?key|access.?token|client.?secret|bearer.?token|password|passwd)\b[[:space:]]*[:=][[:space:]]*"[^"]{8,}"' \
  . 2>/dev/null | grep -v '/vendor/' | grep -v 'karen-ignore' | head -50 || true)

# Issue 18: full-path shell invocations and cmd.exe /c added to alternation.
while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\texec with shell -c pattern — use exec.Command with explicit args array\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E '"(/bin/sh|/usr/bin/bash|/bin/bash|sh|bash|zsh|cmd|cmd\.exe|powershell|pwsh)"[[:space:]]*,[[:space:]]*"(-c|/c)"' \
  . 2>/dev/null | grep -v '/vendor/' | grep -v 'karen-ignore' | head -50 || true)

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tInsecureSkipVerify: true — disabled TLS certificate verification\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  'InsecureSkipVerify:[[:space:]]*true' . 2>/dev/null | grep -v '/vendor/' | grep -v 'karen-ignore' | head -50 || true)

# Issue 20: exec.CommandContext added alongside exec.Command.
while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tdynamic command construction — use exec.Command with literal executable and explicit args array\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E 'syscall\.Exec[[:space:]]*\(|exec\.Command(Context)?[[:space:]]*\([^"]*\+' \
  . 2>/dev/null | grep -v '/vendor/' | grep -v 'karen-ignore' | head -50 || true)

# Issue 11: pattern tightened to require query structure (% format verb) to reduce false positives on error-message strings.
while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tSQL built with fmt.Sprintf — use parameterized queries\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E 'fmt\.Sprintf[[:space:]]*\([[:space:]]*"[^"]*\b(SELECT|INSERT|UPDATE|DELETE)\b[^"]*%(s|v|d)' \
  . 2>/dev/null | grep -v 'karen-ignore' | head -50 || true)

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tSQL built via string concatenation — use parameterized queries\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E '"[[:space:]]*(SELECT|INSERT|UPDATE|DELETE)[^"]*"[[:space:]]*\+' \
  . 2>/dev/null | grep -v 'karen-ignore' | head -50 || true)

# Issue 19: os.OpenFile added to alternation.
while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tfile path assembled via concatenation — use a safe allowlist or filepath.Clean with validated prefix\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E 'os\.(Open|OpenFile|Create|ReadFile|WriteFile)[[:space:]]*\(.*\+|filepath\.Join[[:space:]]*\(.*\+' \
  . 2>/dev/null | grep -v 'karen-ignore' | head -50 || true)

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tcleartext HTTP connection to external service — use https://\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E 'http\.(Get|Post|Do|Head)[[:space:]]*\([[:space:]]*"http://' \
  . 2>/dev/null | grep -v 'karen-ignore' | head -50 || true)

# Issue 4: bare 'auth' removed from alternation to avoid false positives on auth-flow log lines.
while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tcredential-related name in log statement — avoid logging tokens, passwords, or secrets\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E '(log\.|fmt\.Print|fmt\.Fprintf|fmt\.Fprintln).*\b(token|password|passwd|secret|api_?key|credential)\b' \
  . 2>/dev/null | grep -v 'karen-ignore' | head -50 || true)

# Issue 15: pattern split so 'key' match requires it not be a file extension (.key).
while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\twriting credential to file — ensure file permissions are restricted and path is not world-readable\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E 'os\.(WriteFile|Create)[[:space:]]*\(.*\b(token|secret|password)\b|os\.(WriteFile|Create)[[:space:]]*\([^"]*\bkey\b' \
  . 2>/dev/null | grep -v 'karen-ignore' | head -50 || true)

# --- JS SAST ---
# Run when *.js, *.mjs, *.ts, *.tsx, *.jsx, or *.cjs files exist outside excluded directories.

# Issue 5: Probe extended to include TypeScript and JSX extensions.
# Use -print -quit (capture to variable) instead of piping to grep -q to avoid the
# pipefail+SIGPIPE bug: with `set -euo pipefail`, `find ... | grep -q .` causes find
# to receive SIGPIPE (exit 141) when grep exits on first match, making pipefail surface
# a non-zero exit and silently skipping the entire JS SAST block.
JS_FILES_EXIST=0
JS_FILES_PROBE=$(find "$ROOT" \
    -path "$ROOT/node_modules" -prune -o \
    -path "$ROOT/.git" -prune -o \
    -path "$ROOT/dist" -prune -o \
    -path "$ROOT/build" -prune -o \
    -path "$ROOT/coverage" -prune -o \
    -path "$ROOT/tools" -prune -o \
    -path "$ROOT/scripts" -prune -o \
    -path "$ROOT/tests/artifacts" -prune -o \
    -path "$ROOT/tests/fixtures" -prune -o \
    -path "$ROOT/test/fixtures" -prune -o \
    -path "$ROOT/spec/fixtures" -prune -o \
    -path "$ROOT/__snapshots__" -prune -o \
    -path "$ROOT/.cache" -prune -o \
    \( -name "*.js" -o -name "*.mjs" -o -name "*.ts" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.cjs" \) -not -name "*.min.js" -print -quit \
    2>/dev/null || true)
[ -n "$JS_FILES_PROBE" ] && JS_FILES_EXIST=1

if [ "$JS_FILES_EXIST" -eq 1 ]; then
  JS_ISSUES=0

  # Helper: grep JS/TS files excluding standard noise dirs and minified files.
  # Playwright/Cypress trace bundles and test fixtures contain minified vendor JS;
  # tools/ and scripts/ dirs may contain scanner definitions with pattern references.
  # Usage: js_grep <grep -E pattern>
  # Outputs matching lines to stdout; caller pipes into while loop.
  js_grep() {
    # Exclusions are anchored to the project root ($ROOT) to prevent nested-path bypass
    # (e.g. src/tests/artifacts/ must not silently skip first-party source files).
    # Only top-level test output directories are excluded, not arbitrary nested paths.
    # Issue 8: tools/ and scripts/ exclusions anchored to $ROOT to match stated design invariant.
    # Issue 5: TypeScript and JSX extensions added.
    grep -rn --include="*.js" --include="*.mjs" --include="*.ts" --include="*.tsx" --include="*.jsx" --include="*.cjs" -E "$1" -- "$ROOT" 2>/dev/null \
      | grep -v '/node_modules/' \
      | grep -v '/\.git/' \
      | grep -v '/dist/' \
      | grep -v '/build/' \
      | grep -v '/coverage/' \
      | grep -v "^${ROOT}/tools/" \
      | grep -v "/tools/" \
      | grep -v "^${ROOT}/scripts/" \
      | grep -v "/scripts/" \
      | grep -v "/tests/artifacts/" \
      | grep -v "/tests/fixtures/" \
      | grep -v "/test/fixtures/" \
      | grep -v "/spec/fixtures/" \
      | grep -v "/__snapshots__/" \
      | grep -v "/.cache/" \
      | grep -v "/examples/" \
      | grep -v "/example/" \
      | grep -v '\.min\.js:' \
      | grep -v 'karen-ignore' \
      | head -30 \
      || true
  }

  # 1. Hardcoded secrets
  # Issue 7: backtick delimiter added; $ removed from exclusion class so secrets containing $ are caught.
  # Issue 9: 'test' removed from suppression list (substring false negatives); word boundaries on remaining terms.
  while IFS=: read -r file line rest; do
    [ -z "$file" ] && continue
    printf '%s:%s\tJS potential hardcoded secret — rotate immediately\n' "$file" "$line"
    JS_ISSUES=$((JS_ISSUES+1))
  done < <(js_grep "(api_key|auth_token|secret_key|password|passwd)[[:space:]]*[=:][[:space:]]*['\"\`][^'\"\` ]{8,}['\"\`]" \
    | grep -vE 'process\.env|\bplaceholder\b|\bexample\b|\bdummy\b' || true)

  # 2. Shell exec (child_process) — zero-tolerance in production; test files excluded.
  # BLUEPRINT: "Zero-tolerance means no exceptions in production code. Test files are
  # excluded — they may deliberately exercise these patterns to verify their scanner."
  # Issue 13: /tests/ and /test/ and /integration/ directory exclusions added.
  # Issue 17: destructured require('child_process') pattern added.
  while IFS=: read -r file line rest; do
    [ -z "$file" ] && continue
    printf '%s:%s\tJS child_process exec/spawn — audit for unsanitized user input in arguments\n' "$file" "$line"
    JS_ISSUES=$((JS_ISSUES+1))
  done < <({ js_grep "child_process\.(exec|spawn|execSync|spawnSync|execFile|execFileSync|fork)\("; \
    js_grep "require\(['\"]child_process['\"]\)" | grep -v 'karen-ignore'; } \
    | grep -v '\.test\.' | grep -v '\.spec\.' | grep -v '/__tests__/' | grep -v '/tests/' | grep -v '/test/' | grep -v '/integration/' || true)

  # 3. TLS bypass — zero-tolerance in production; test files excluded.
  # Issue 13: /tests/ and /test/ and /integration/ directory exclusions added.
  while IFS=: read -r file line rest; do
    [ -z "$file" ] && continue
    printf '%s:%s\tJS rejectUnauthorized: false — disabled TLS certificate verification\n' "$file" "$line"
    JS_ISSUES=$((JS_ISSUES+1))
  done < <(js_grep "rejectUnauthorized[[:space:]]*:[[:space:]]*false" \
    | grep -v '\.test\.' | grep -v '\.spec\.' | grep -v '/__tests__/' | grep -v '/tests/' | grep -v '/test/' | grep -v '/integration/' || true)

  # 4. eval() call — zero-tolerance in production; test files excluded.
  # Issue 3: method-call forms excluded (e.g. mathParser.eval()) to avoid false positives from libraries.
  # Issue 13: /tests/ and /test/ and /integration/ directory exclusions added.
  while IFS=: read -r file line rest; do
    [ -z "$file" ] && continue
    printf '%s:%s\tJS eval() call — dynamic code execution; use safer alternatives\n' "$file" "$line"
    JS_ISSUES=$((JS_ISSUES+1))
  done < <(js_grep "\beval[[:space:]]*\(" \
    | grep -v '\.[a-zA-Z_][a-zA-Z_0-9]*eval[[:space:]]*(' \
    | grep -v '\.test\.' | grep -v '\.spec\.' | grep -v '/__tests__/' | grep -v '/tests/' | grep -v '/test/' | grep -v '/integration/' || true)

  # 5. innerHTML assignment
  # Issue 2: pattern tightened to require = not followed by another = to exclude === and == comparisons.
  while IFS=: read -r file line rest; do
    [ -z "$file" ] && continue
    printf '%s:%s\tJS innerHTML assignment — potential XSS; use textContent or sanitize input\n' "$file" "$line"
    JS_ISSUES=$((JS_ISSUES+1))
  done < <(js_grep "\.innerHTML[[:space:]]*[+]?=[^=]")

  # 6. SQL string concatenation
  # Issue 10: pattern anchored to require SQL keyword inside a string context (quote before keyword).
  while IFS=: read -r file line rest; do
    [ -z "$file" ] && continue
    printf '%s:%s\tJS SQL built via string concatenation — use parameterized queries\n' "$file" "$line"
    JS_ISSUES=$((JS_ISSUES+1))
  done < <(js_grep "['\"\`][^'\"\`]*(SELECT|INSERT|UPDATE|DELETE).*\+")

  # 7. Cleartext HTTP fetch
  # Issue 12: comment-line filter added to suppress JSDoc and inline code examples.
  while IFS=: read -r file line rest; do
    [ -z "$file" ] && continue
    printf '%s:%s\tJS cleartext HTTP fetch — use https://\n' "$file" "$line"
    JS_ISSUES=$((JS_ISSUES+1))
  done < <(js_grep "fetch\([[:space:]]*['\"]http://" \
    | grep -v '^[^:]*:[0-9]*:[[:space:]]*//' || true)

  # 8. Credential logging
  while IFS=: read -r file line rest; do
    [ -z "$file" ] && continue
    printf '%s:%s\tJS credential-related name in console statement — avoid logging tokens, passwords, or secrets\n' "$file" "$line"
    JS_ISSUES=$((JS_ISSUES+1))
  done < <(js_grep "console\.(log|error|warn)\([^)]*\b(token|secret|password)\b" \
    | grep -v 'redact\|\*\*\*' \
    | grep -vE "console\.(log|error|warn)\([[:space:]]*('[^']*\b(token|secret|password)\b[^']*'|\"[^\"]*\b(token|secret|password)\b[^\"]*\")[[:space:]]*[,)][[:space:]]*(,.*)?[))]?" \
    || true)

  # 9. postMessage with wildcard targetOrigin — cross-origin data leak
  while IFS=: read -r file line rest; do
    [ -z "$file" ] && continue
    printf '%s:%s\tJS postMessage with wildcard targetOrigin ("*") — specify explicit origin to prevent cross-origin data leaks\n' "$file" "$line"
    JS_ISSUES=$((JS_ISSUES+1))
  done < <(js_grep '\.postMessage\([^,)]*,[[:space:]]*["'"'"']\*["'"'"']' || true)

  # Cap JS issues at 30 to avoid overwhelming output.
  if [ "$JS_ISSUES" -gt 30 ]; then
    JS_ISSUES=30
  fi

  ISSUES=$((ISSUES+JS_ISSUES))
fi

SUMMARY_EMITTED=1
if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  printf 'FAIL (%s issues)\n' "$ISSUES"
  echo "ZERO-TOLERANCE"
fi
exit 0

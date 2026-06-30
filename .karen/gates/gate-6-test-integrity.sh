#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0
# karen-ignore: add this comment to any line to suppress it from Karen gate scanning.

SUMMARY_EMITTED=0
TMPLOG=""
COVERAGE_FILE=""
trap '_ec=$?; rm -f "$TMPLOG" "$COVERAGE_FILE"; if [ "$SUMMARY_EMITTED" -eq 0 ]; then printf "GATE_CRASH:0\tgate crashed (exit %s)\n" "$_ec"; echo "FAIL (1 issues)"; fi' EXIT

# ── Go branch ────────────────────────────────────────────────────────────────
if [ -f go.mod ]; then
  COVERAGE_FILE="/tmp/karen-self-coverage-$$.out"

  if ! go test ./... -race -coverprofile="$COVERAGE_FILE" -covermode=atomic >/dev/null 2>&1; then
    printf 'go.mod:0\ttest suite failed — fix failing tests before proceeding\n'
    ISSUES=$((ISSUES+1))
    SUMMARY_EMITTED=1
    echo "FAIL ($ISSUES issues)"
    exit 0
  fi

  THRESHOLD=80
  if command -v jq &>/dev/null && [ -f "$ROOT/.karen.json" ]; then
    CONFIGURED=$(jq -r '.coverage.threshold // empty' "$ROOT/.karen.json" 2>/dev/null)
    [ -n "$CONFIGURED" ] && THRESHOLD="$CONFIGURED"
  fi
  THRESHOLD=$(echo "$THRESHOLD" | cut -d. -f1)

  if [ -f "$COVERAGE_FILE" ]; then
    COV_LINE=$(go tool cover -func="$COVERAGE_FILE" 2>/dev/null | tail -1)
    COV_PCT=$(echo "$COV_LINE" | awk '{print $3}' | tr -d '%')
    if [ -n "$COV_PCT" ]; then
      INT_COV=$(echo "$COV_PCT" | cut -d. -f1)
      if [ "$INT_COV" -lt "$THRESHOLD" ]; then
        printf 'go.mod:0\ttest coverage %s%% is below %d%% threshold\n' "$COV_PCT" "$THRESHOLD"
        ISSUES=$((ISSUES+1))
      fi
    fi
    rm -f "$COVERAGE_FILE"
  fi

  # Assertion density: no test blocks with zero assertions
  while IFS= read -r -d '' f; do
    rel="${f#$ROOT/}"
    while IFS=: read -r lineno funcname; do
      funcbody=$(awk "NR>$lineno && /^func /{exit} NR>=$lineno{print}" "$f" | tail -n +2)
      funcline=$(sed -n "${lineno}p" "$f")
      if echo "$funcline" | grep -qE 'karen-ignore'; then continue; fi
      if ! echo "$funcbody" | grep -qE 't\.(Error|Fatal|Fail|Errorf|Fatalf)|assert\.|require\.|if.*t\.(Error|Fatal|Fail|FailNow|Skip)|Expect\(|Eventually\(|Consistently\(|\.AssertExpectations\('; then
        printf '%s:%s\t%s — test function has no assertions — produces false confidence\n' "$rel" "$lineno" "$funcname"
        ISSUES=$((ISSUES+1))
      fi
    done < <(grep -nE '^func Test[^(]+\(' "$f" | grep -v ':TestMain(' | sed -E 's/^([0-9]+):func ([^(]+)\(.*/\1:\2/' || true)
  done < <(find "$ROOT" -name '*_test.go' -not -path '*/vendor/*' -print0 2>/dev/null)

  # Live credential usage: tests must not require real credentials to pass
  while IFS= read -r -d '' f; do
    rel="${f#$ROOT/}"
    if grep -nE 'os\.(Getenv|LookupEnv)[[:space:]]*\([[:space:]]*"[A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|API)[A-Za-z0-9_]*"' "$f" | \
       cut -d: -f2- | grep -qvE '^[[:space:]]*(//|t\.Skip|.*karen-ignore)'; then
      # Also check if t.Skip appears within 3 lines after each match
      if ! grep -A3 -E 'os\.(Getenv|LookupEnv)[[:space:]]*\([[:space:]]*"[A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|API)[A-Za-z0-9_]*"' "$f" | grep -qE 't\.Skip|karen-ignore'; then
        lineno=$(grep -nE 'os\.(Getenv|LookupEnv)[[:space:]]*\([[:space:]]*"[A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|API)[A-Za-z0-9_]*"' "$f" | head -1 | cut -d: -f1)
        printf '%s:%s\tlive credential read in test — add t.Skip when credential is absent\n' "$rel" "$lineno"
        ISSUES=$((ISSUES+1))
      fi
    fi
  done < <(find "$ROOT" -name '*_test.go' -not -path '*/vendor/*' -print0 2>/dev/null)

  SUMMARY_EMITTED=1
  if [ "$ISSUES" -eq 0 ]; then
    echo "PASS (0 issues)"
  else
    echo "FAIL ($ISSUES issues)"
  fi
  exit 0
fi

# ── JS branch (no go.mod) ────────────────────────────────────────────────────

# Discover testable package: check $ROOT/package.json then $ROOT/sdk/package.json
TEST_PKG_DIR=""
for candidate_dir in "$ROOT" "$ROOT/sdk" $(find "$ROOT" -maxdepth 3 -name 'package.json' -not -path '*/node_modules/*' -exec dirname {} \; 2>/dev/null | grep -v "^$ROOT$" | grep -v "^$ROOT/sdk$"); do
  candidate="$candidate_dir/package.json"
  if [ -f "$candidate" ] && jq -e '.scripts.test' "$candidate" >/dev/null 2>&1; then
    TEST_PKG_DIR="$candidate_dir"
    break
  fi
done

if [ -z "$TEST_PKG_DIR" ]; then
  SUMMARY_EMITTED=1
  echo "PASS (0 issues)"
  exit 0
fi

# Enforce coverage threshold for JS projects (Go uses go test -cover).
# Run tests exactly once: either via c8 (which invokes node --test internally),
# via Node v22+ --experimental-test-coverage, or via npm test as a last resort.
# Never re-run tests after a coverage pass — that would double execution time and
# risk stateful side-effects.
THRESHOLD=$(jq -r ".coverage.threshold // 80" "$ROOT/.karen.json" 2>/dev/null || echo "80")
THRESHOLD=$(echo "$THRESHOLD" | cut -d. -f1)
TMPLOG="/tmp/karen-js-test-$$"
cd "$TEST_PKG_DIR"

if command -v c8 >/dev/null 2>&1; then
  # c8 runs tests with V8 coverage in a single pass.
  # If the project uses jest, vitest, mocha, or jasmine, wrap npm test instead of node --test.
  TEST_SCRIPT=$(jq -r '.scripts.test // empty' package.json 2>/dev/null)
  set +e
  if echo "$TEST_SCRIPT" | grep -qE 'jest|vitest|mocha|jasmine'; then
    c8 --check-coverage --lines "$THRESHOLD" --functions "$THRESHOLD" --branches "$THRESHOLD" \
      npm test 2>&1 | tee "$TMPLOG"
  else
    c8 --check-coverage --lines "$THRESHOLD" --functions "$THRESHOLD" --branches "$THRESHOLD" \
      node --test 2>&1 | tee "$TMPLOG"
  fi
  C8_EXIT=${PIPESTATUS[0]}
  set -e
  if [ "$C8_EXIT" -ne 0 ]; then
    # Parse TAP "not ok" lines for test failures, cap at 20.
    TAP_COUNT=0
    while IFS= read -r line; do
      [ "$TAP_COUNT" -ge 20 ] && break
      trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
      case "$trimmed" in
        "not ok"*)
          desc=$(echo "$trimmed" | sed -E 's/^not ok[[:space:]]+[0-9]+[[:space:]]*//' | sed 's/^not ok //')
          printf 'package.json:0\ttest failed — %s\n' "$desc"
          ISSUES=$((ISSUES+1))
          TAP_COUNT=$((TAP_COUNT+1))
          ;;
      esac
    done < "$TMPLOG"
    # If no TAP failures parsed but exit was non-zero, it may be a coverage threshold miss.
    if [ "$TAP_COUNT" -eq 0 ]; then
      printf 'package.json:0\tJS test coverage below threshold %s%%\n' "${THRESHOLD}"
      ISSUES=$((ISSUES+1))
    fi
  fi
else
  NODE_MAJ=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
  if [ -n "$NODE_MAJ" ] && [ "$NODE_MAJ" -ge 22 ] 2>/dev/null; then
    # Node v22+ has built-in coverage; runs tests and collects coverage in one pass.
    # Use the project's explicit test glob if the test script invokes node --test directly.
    _test_script=$(jq -r '.scripts.test // empty' package.json 2>/dev/null || true)
    _extra_args=""
    if echo "$_test_script" | grep -qE '^node[[:space:]].*--test'; then
      _extra_args=$(echo "$_test_script" | grep -oE '[^ ]*(\*|\.js|\.ts)[^ ]*' | head -1 || true)
    fi
    set +e
    # shellcheck disable=SC2086  # intentional: word-split for glob expansion
    node --experimental-test-coverage --test $_extra_args 2>&1 | tee "$TMPLOG"
    NODE_EXIT=${PIPESTATUS[0]}
    set -e
    if [ "$NODE_EXIT" -ne 0 ]; then
      TAP_COUNT=0
      while IFS= read -r line; do
        [ "$TAP_COUNT" -ge 20 ] && break
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
        case "$trimmed" in
          "not ok"*)
            desc=$(echo "$trimmed" | sed -E 's/^not ok[[:space:]]+[0-9]+[[:space:]]*//' | sed 's/^not ok //')
            printf 'package.json:0\ttest failed — %s\n' "$desc"
            ISSUES=$((ISSUES+1))
            TAP_COUNT=$((TAP_COUNT+1))
            ;;
        esac
      done < "$TMPLOG"
      [ "$TAP_COUNT" -eq 0 ] && { printf 'package.json:0\ttest suite failed — fix failing tests before proceeding\n'; ISSUES=$((ISSUES+1)); }
    fi
    # Parse coverage summary from output.
    # Node v22+ prefixes coverage lines with "ℹ " (U+2139 + space); drop the anchor
    # so both "all files | 92.09 | ..." and "ℹ all files | 92.09 | ..." are matched.
    COV_PCT=""
    ALL_LINE=$(grep -iaE "(^|[[:space:]])all files" "$TMPLOG" | tail -1 || true)
    if [ -n "$ALL_LINE" ]; then
      COV_PCT=$(echo "$ALL_LINE" | grep -oE '[0-9]+\.[0-9]+' | head -1)
    fi
    # Fallback: bare percentage line if table-format output changed
    if [ -z "$COV_PCT" ]; then
      COV_PCT=$(grep -oE '[0-9]+\.[0-9]+[[:space:]]*%' "$TMPLOG" | grep -oE '^[0-9]+\.[0-9]+' | tail -1 || true)
    fi
    if [ -n "$COV_PCT" ]; then
      INT_COV=$(echo "$COV_PCT" | cut -d. -f1)
      if [ "$INT_COV" -lt "$THRESHOLD" ] 2>/dev/null; then
        printf 'package.json:0\tJS test coverage %s%% is below %s%% threshold\n' "$COV_PCT" "${THRESHOLD}"
        ISSUES=$((ISSUES+1))
      fi
    fi
  else
    # No coverage tool available — run npm test once for pass/fail, warn on coverage.
    set +e
    npm test 2>&1 | tee "$TMPLOG"
    TEST_EXIT=${PIPESTATUS[0]}
    set -e
    if [ "$TEST_EXIT" -ne 0 ]; then
      TAP_COUNT=0
      while IFS= read -r line; do
        [ "$TAP_COUNT" -ge 20 ] && break
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
        case "$trimmed" in
          "not ok"*)
            desc=$(echo "$trimmed" | sed -E 's/^not ok[[:space:]]+[0-9]+[[:space:]]*//' | sed 's/^not ok //')
            printf 'package.json:0\ttest failed — %s\n' "$desc"
            ISSUES=$((ISSUES+1))
            TAP_COUNT=$((TAP_COUNT+1))
            ;;
        esac
      done < "$TMPLOG"
      [ "$TAP_COUNT" -eq 0 ] && { printf 'package.json:0\ttest suite failed — fix failing tests before proceeding\n'; ISSUES=$((ISSUES+1)); }
    fi
    printf 'WARN: package.json:0\tJS coverage threshold enforcement requires c8 (npm install -g c8) or Node.js v22+\n'
    # Do not increment ISSUES — missing tool is an env limitation, not a code defect
  fi
fi
rm -f "$TMPLOG"
cd "$ROOT"

# Assertion density check
# -a flag forces text mode on macOS BSD grep so files containing multi-byte UTF-8
# chars (e.g. U+2192 → or U+2500 ─) are not misclassified as binary and skipped.
while IFS= read -r f; do
  if [ -z "$f" ]; then continue; fi
  if ! grep -qaE "assert[.(]|expect\(|should\.|t\.pass|t\.fail|(^|[^a-zA-Z])ok\(" "$f" 2>/dev/null; then
    rel="${f#$ROOT/}"
    printf '%s:0\ttest file has no assertion calls\n' "$rel"
    ISSUES=$((ISSUES+1))
  fi
done < <(find "$ROOT" -maxdepth 8 -not -path "*/node_modules/*" \( \
    -name "*.test.js" -o -name "*.spec.js" -o -name "*.test.ts" -o -name "*.spec.ts" \
    -o -path "*/test/*.js" -o -path "*/tests/*.js" -o -path "*/__tests__/*.js" \
    -o -path "*/test/*.ts" -o -path "*/tests/*.ts" -o -path "*/__tests__/*.ts" \
  \) \
  -not -path "*/fakes/*" \
  -not -path "*/artifacts/*" \
  -not -path "*/fixtures/*" \
  -not -name "playwright.config.*" \
  -not -name "jest.config.*" \
  -not -name "vitest.config.*" \
  -not -name "karma.config.*" \
  2>/dev/null || true)

# Live credential check in JS tests
while IFS= read -r f; do
  if [ -z "$f" ]; then continue; fi
  while IFS=: read -r lineno rest; do
    if [ -z "$lineno" ]; then continue; fi
    if echo "$rest" | grep -qE 'karen-ignore|skip'; then continue; fi
    rel="${f#$ROOT/}"
    printf '%s:%s\tlive credential env var read in test\n' "$rel" "$lineno"
    ISSUES=$((ISSUES+1))
  done < <({ grep -nE "process\.env\.([A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|AUTH)[A-Z0-9_]*|API_[A-Z0-9_]+|ADMIN_[A-Z0-9_]+)" "$f"; \
             grep -nE "process\.env\[|const[[:space:]]*\{[^}]*(KEY|TOKEN|SECRET|PASSWORD)" "$f"; } 2>/dev/null | sort -t: -k1,1n || true)
done < <(find "$ROOT" -maxdepth 8 -not -path "*/node_modules/*" \( \
    -name "*.test.js" -o -name "*.spec.js" -o -name "*.test.ts" -o -name "*.spec.ts" \
    -o -path "*/test/*.js" -o -path "*/tests/*.js" -o -path "*/__tests__/*.js" \
    -o -path "*/test/*.ts" -o -path "*/tests/*.ts" -o -path "*/__tests__/*.ts" \
  \) \
  -not -path "*/fakes/*" \
  -not -path "*/artifacts/*" \
  -not -path "*/fixtures/*" \
  -not -name "playwright.config.*" \
  -not -name "jest.config.*" \
  -not -name "vitest.config.*" \
  -not -name "karma.config.*" \
  2>/dev/null || true)

SUMMARY_EMITTED=1
if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
fi
exit 0

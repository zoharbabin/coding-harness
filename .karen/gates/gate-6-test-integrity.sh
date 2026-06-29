#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0
# karen-ignore: add this comment to any line to suppress it from Karen gate scanning.
COVERAGE_FILE="/tmp/karen-self-coverage-$$.out"

if [ ! -f go.mod ]; then
  echo "PASS (0 issues)"
  exit 0
fi

if ! go test ./... -race -coverprofile="$COVERAGE_FILE" -covermode=atomic >/dev/null 2>&1; then
  printf 'go.mod:0\ttest suite failed — fix failing tests before proceeding\n'
  ISSUES=$((ISSUES+1))
  echo "FAIL ($ISSUES issues)"
  exit 0
fi

THRESHOLD=80
if command -v jq &>/dev/null && [ -f "$ROOT/.karen.json" ]; then
  CONFIGURED=$(jq -r '.coverage.threshold // empty' "$ROOT/.karen.json" 2>/dev/null)
  [ -n "$CONFIGURED" ] && THRESHOLD="$CONFIGURED"
fi

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
  # Get all Test function names and their line numbers (skip Benchmark and Example)
  while IFS=: read -r lineno funcname; do
    # Extract lines from this function to the next top-level func declaration
    startline=$((lineno + 1))
    # Get the block of lines for this function
    funcbody=$(awk "NR==$lineno,/^func / && NR>$lineno" "$f" | tail -n +2)
    # Check if any assertion pattern appears in the function body
    if ! echo "$funcbody" | grep -qE 't\.(Error|Fatal|Fail|Errorf|Fatalf)|assert\.|require\.|if.*t\.'; then
      printf '%s:%s\t%s — test function has no assertions — produces false confidence\n' "$rel" "$lineno" "$funcname"
      ISSUES=$((ISSUES+1))
    fi
  done < <(grep -nE '^func Test[^(]+\(' "$f" | sed -E 's/^([0-9]+):func ([^(]+)\(.*/\1:\2/')
done < <(find "$ROOT" -name '*_test.go' -not -path '*/vendor/*' -print0)

# Live credential usage: tests must not require real credentials to pass
while IFS= read -r -d '' f; do
  rel="${f#$ROOT/}"
  # Flag direct use of credential env vars in assertions (not guarded by t.Skip)
  if grep -nE 'os\.(Getenv|LookupEnv)\s*\(\s*"[A-Z_]*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|API)[A-Z_]*"' "$f" | \
     grep -qvE '^\s*(//|t\.Skip)'; then
    lineno=$(grep -nE 'os\.(Getenv|LookupEnv)\s*\(\s*"[A-Z_]*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|API)[A-Z_]*"' "$f" | head -1 | cut -d: -f1)
    printf '%s:%s\tlive credential read in test — add t.Skip when credential is absent\n' "$rel" "$lineno"
    ISSUES=$((ISSUES+1))
  fi
done < <(find "$ROOT" -name '*_test.go' -not -path '*/vendor/*' -print0)

if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
fi
exit 0

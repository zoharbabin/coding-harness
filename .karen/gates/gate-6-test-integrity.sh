#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0
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

if [ -f "$COVERAGE_FILE" ]; then
  COV_LINE=$(go tool cover -func="$COVERAGE_FILE" 2>/dev/null | tail -1)
  COV_PCT=$(echo "$COV_LINE" | awk '{print $3}' | tr -d '%')
  THRESHOLD=80
  if [ -n "$COV_PCT" ]; then
    INT_COV=$(echo "$COV_PCT" | cut -d. -f1)
    if [ "$INT_COV" -lt "$THRESHOLD" ]; then
      printf 'go.mod:0\ttest coverage %s%% is below %d%% threshold\n' "$COV_PCT" "$THRESHOLD"
      ISSUES=$((ISSUES+1))
    fi
  fi
  rm -f "$COVERAGE_FILE"
fi

if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
fi
exit 0

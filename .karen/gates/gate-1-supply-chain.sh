#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0

# go.sum is required only when the module has external dependencies.
if [ -f go.mod ] && grep -qE '^require' go.mod 2>/dev/null && [ ! -f go.sum ]; then
  printf 'go.sum:0\tgo.sum missing — run go mod tidy\n'
  ISSUES=$((ISSUES+1))
fi

if [ -f go.mod ] && command -v go &>/dev/null; then
  if ! go mod verify 2>/dev/null; then
    printf 'go.mod:0\tgo mod verify failed — dependency tampering or cache corruption\n'
    ISSUES=$((ISSUES+1))
  fi
  if command -v govulncheck &>/dev/null; then
    VULN_OUT=$(govulncheck ./... 2>&1 || true)
    if echo "$VULN_OUT" | grep -q "^Vulnerability #"; then
      while IFS= read -r line; do
        if [[ "$line" =~ ^Vulnerability ]]; then
          printf 'go.mod:0\t%s\n' "$line"
          ISSUES=$((ISSUES+1))
        fi
      done <<< "$VULN_OUT"
    fi
  fi
fi

if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
fi
exit 0

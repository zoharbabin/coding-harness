#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0

if [ ! -f README.md ]; then
  printf 'README.md:0\tREADME.md is missing\n'
  ISSUES=$((ISSUES+1))
  echo "FAIL ($ISSUES issues)"
  exit 0
fi

# Check Karen's own CLI commands only when this is the Karen repository itself.
if [ -f go.mod ] && grep -q 'github.com/zoharbabin/karen' go.mod 2>/dev/null; then
  for cmd_str in "karen audit" "karen init" "karen reset" "karen upgrade" "karen version"; do
    if ! grep -q "$cmd_str" README.md; then
      printf 'README.md:0\tcommand "%s" not documented\n' "$cmd_str"
      ISSUES=$((ISSUES+1))
    fi
  done
fi

if [ ! -f CHANGELOG.md ]; then
  printf 'CHANGELOG.md:0\tCHANGELOG.md is missing — add one or set releasesManaged in .karen.json\n'
  ISSUES=$((ISSUES+1))
fi

if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
fi
exit 0

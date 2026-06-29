#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0
# karen-ignore: add this comment to any line to suppress it from Karen gate scanning.

while IFS=: read -r file line rest; do
  printf '%s:%s\tbroken TODO/FIXME marker — incomplete implementation in production code\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" --exclude="*_test.go" \
  -E '(//|#)[[:space:]]*(TODO|FIXME|HACK|XXX)[: ]' . 2>/dev/null | grep -v '.git' | head -50)

while IFS=: read -r file line rest; do
  printf '%s:%s\tstub implementation — panic or not-implemented placeholder\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" --exclude="*_test.go" \
  -E 'panic\("(not implemented|TODO|unimplemented)"' . 2>/dev/null | grep -v '.git' | head -50)

if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
fi
[ "$ISSUES" -eq 0 ]

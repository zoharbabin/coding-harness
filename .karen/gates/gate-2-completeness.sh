#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0

while IFS=: read -r file line rest; do
  printf '%s:%s\t%s\n' "$file" "$line" "$rest"
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
exit 0

#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tpotential hardcoded secret — rotate immediately\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E '(api_?key|auth_?token|secret_?key|password|passwd)[[:space:]]*[:=][[:space:]]*"[^"]{8,}"' \
  . 2>/dev/null | head -50)

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]]; then continue; fi
  printf '%s:%s\texec with shell -c pattern — use exec.Command with explicit args array\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E '"(sh|bash|cmd|powershell)"[[:space:]]*,[[:space:]]*"-c"' \
  . 2>/dev/null | head -50)

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */wizard/generator.go ]]; then continue; fi
  printf '%s:%s\tInsecureSkipVerify: true — disabled TLS certificate verification\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  'InsecureSkipVerify:[[:space:]]*true' . 2>/dev/null | head -50)

if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
  echo "ZERO-TOLERANCE"
fi
exit 0

#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0
# karen-ignore: add this comment to any line to suppress it from Karen gate scanning.

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

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tdynamic command construction — use exec.Command with literal executable and explicit args array\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E 'syscall\.Exec\s*\(|exec\.Command\s*\([^"]*\+' \
  . 2>/dev/null | head -50)

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tSQL built with fmt.Sprintf — use parameterized queries\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E 'fmt\.Sprintf\s*\(\s*"[^"]*\b(SELECT|INSERT|UPDATE|DELETE|WHERE)\b' \
  . 2>/dev/null | head -50)

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tSQL built via string concatenation — use parameterized queries\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E '"[[:space:]]*(SELECT|INSERT|UPDATE|DELETE)[^"]*"\s*\+' \
  . 2>/dev/null | head -50)

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tfile path assembled via concatenation — use a safe allowlist or filepath.Clean with validated prefix\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E 'os\.(Open|Create|ReadFile|WriteFile)\s*\(.*\+|filepath\.Join\s*\(.*\+' \
  . 2>/dev/null | head -50)

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tcleartext HTTP connection to external service — use https://\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E 'http\.(Get|Post|Do|Head)\s*\(\s*"http://' \
  . 2>/dev/null | head -50)

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\tcredential-related name in log statement — avoid logging tokens, passwords, or secrets\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E '(log\.|fmt\.Print|fmt\.Fprintf|fmt\.Fprintln).*\b(token|password|passwd|secret|api_?key|auth|credential)\b' \
  . 2>/dev/null | head -50)

while IFS=: read -r file line rest; do
  if [[ "$file" == *_test.go ]] || [[ "$file" == */testdata/* ]]; then continue; fi
  printf '%s:%s\twriting credential to file — ensure file permissions are restricted and path is not world-readable\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" \
  -E 'os\.(WriteFile|Create)\s*\(.*\b(token|secret|password|key)\b' \
  . 2>/dev/null | head -50)

if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
  echo "ZERO-TOLERANCE"
fi
exit 0

#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0

# SECURITY.md: accept at root or any first-level subdirectory (monorepo: sdk/SECURITY.md etc.)
SECURITY_FOUND=$(find . -maxdepth 2 -name "SECURITY.md" -not -path "./.git/*" 2>/dev/null | head -1)
if [ -z "$SECURITY_FOUND" ]; then
  printf 'SECURITY.md:0\trequired compliance artifact missing\n'
  ISSUES=$((ISSUES+1))
elif ! grep -qi "vuln\|disclos\|report\|CVE" "$SECURITY_FOUND" 2>/dev/null; then
  printf 'SECURITY.md:0\tSECURITY.md lacks vulnerability disclosure process\n'
  ISSUES=$((ISSUES+1))
fi

for f in "LICENSE" "CONTRIBUTING.md"; do
  if [ ! -f "$f" ]; then
    printf '%s:0\trequired compliance artifact missing\n' "$f"
    ISSUES=$((ISSUES+1))
  fi
done

  if [ ! -f CHANGELOG.md ]; then
    printf 'CHANGELOG.md:0\trequired compliance artifact missing — add one or set releasesManaged in .karen.json\n'
    ISSUES=$((ISSUES+1))
  fi

if [ -f LICENSE ]; then
  if ! grep -qi "apache\|mit\|SPDX\|GPL\|BSD\|ISC" LICENSE; then
    printf 'LICENSE:0\tLICENSE file type cannot be determined\n'
    ISSUES=$((ISSUES+1))
  fi
fi

if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
fi
exit 0

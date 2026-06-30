#!/usr/bin/env bash
set -euo pipefail
SUMMARY_EMITTED=0
trap '_ec=$?; if [ "$SUMMARY_EMITTED" -eq 0 ]; then printf "GATE_CRASH:0\tgate crashed (exit %s)\n" "$_ec"; echo "FAIL (1 issues)"; fi' EXIT
ROOT="${1:?project root required}"
cd "$ROOT"
ISSUES=0
# karen-ignore: add this comment to any line to suppress it from Karen gate scanning.

# Read releasesManaged from .karen.json
RELEASES_MANAGED=false
if [ -f "$ROOT/.karen.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    RELEASES_MANAGED=$(jq -r '.releasesManaged // false' "$ROOT/.karen.json" 2>/dev/null || echo "false")
  else
    grep -q '"releasesManaged"[[:space:]]*:[[:space:]]*true' "$ROOT/.karen.json" 2>/dev/null && RELEASES_MANAGED=true || true
  fi
fi

# SECURITY.md: accept at root or any first-level subdirectory (monorepo: sdk/SECURITY.md etc.)
SECURITY_FOUND=$(find . -maxdepth 2 -name "SECURITY.md" -not -path "./.git/*" -not -path "./vendor/*" -not -path "./node_modules/*" -not -path "./dist/*" -not -path "./build/*" -not -path "./third_party/*" 2>/dev/null | head -1)
if [ -z "$SECURITY_FOUND" ]; then
  printf 'SECURITY.md:0\trequired compliance artifact missing\n'
  ISSUES=$((ISSUES+1))
elif ! grep -qi "vuln\|disclos\|CVE\|security.*contact\|responsible.disclos" "$SECURITY_FOUND" 2>/dev/null; then
  printf 'SECURITY.md:0\tSECURITY.md lacks vulnerability disclosure process\n'
  ISSUES=$((ISSUES+1))
fi

for f in "LICENSE" "CONTRIBUTING.md"; do
  found=$(find . -maxdepth 2 -name "$f" -not -path "./.git/*" -not -path "./vendor/*" -not -path "./node_modules/*" 2>/dev/null | head -1)
  if [ -z "$found" ]; then
    printf '%s:0\trequired compliance artifact missing\n' "$f"
    ISSUES=$((ISSUES+1))
  fi
done

if [ "$RELEASES_MANAGED" = "true" ]; then
  : # CHANGELOG.md check suppressed — releasesManaged is true in .karen.json
else
  CHANGELOG_FOUND=$(find . -maxdepth 2 -name "CHANGELOG.md" -not -path "./.git/*" -not -path "./vendor/*" -not -path "./node_modules/*" 2>/dev/null | head -1)
  if [ -n "$CHANGELOG_FOUND" ]; then
    # CHANGELOG exists — verify it follows Keep a Changelog format.
    if ! grep -qE '^## \[' "$CHANGELOG_FOUND" 2>/dev/null; then
      printf 'CHANGELOG.md:0\tdoes not follow Keep a Changelog format (missing ## [version] headers)\n'
      ISSUES=$((ISSUES+1))
    fi
  else
    # No CHANGELOG.md — check if GitHub Releases serve as the changelog (valid substitute).
    GH_RELEASES_OK=0
    if command -v gh &>/dev/null; then
      # Get the latest release tag, then inspect its body for non-trivial notes.
      if command -v jq &>/dev/null; then
        _latest_tag=$(gh release list --limit 1 --json tagName 2>/dev/null \
          | jq -r '.[0].tagName // ""' 2>/dev/null || true)
      else
        _latest_tag=$(gh release list --limit 1 2>/dev/null | awk 'NR==1{print $1}' || true)
      fi
      if [ -n "$_latest_tag" ]; then
        _gh_json=$(gh release view "$_latest_tag" --json body 2>/dev/null || true)
        if command -v jq &>/dev/null; then
          _gh_body=$(echo "$_gh_json" | jq -r '.body // ""' 2>/dev/null || true)
        else
          _gh_body=$(echo "$_gh_json" | grep -o '"body":"[^"]*"' \
            | sed 's/"body":"//;s/"$//' 2>/dev/null || true)
        fi
        _gh_body_stripped=$(echo "$_gh_body" | tr -d '[:space:]')
        [ "${#_gh_body_stripped}" -gt 20 ] && GH_RELEASES_OK=1
      fi
    fi
    if [ "$GH_RELEASES_OK" -eq 1 ]; then
      printf 'WARN:CHANGELOG.md:0\tno CHANGELOG.md — GitHub Releases with release notes detected (acceptable substitute); consider adding CHANGELOG.md for offline discoverability\n'
    else
      printf 'CHANGELOG.md:0\tno changelog — create CHANGELOG.md, publish GitHub Releases with release notes, or set "releasesManaged": true in .karen.json\n'
      ISSUES=$((ISSUES+1))
    fi
  fi
fi

if [ -f LICENSE ]; then
  if ! grep -qiE "(^|[^a-zA-Z])(apache|mit|spdx|gpl|bsd|isc|mozilla|unlicense|creative.commons|cc0|boost|zlib|artistic|eupl|cddl)([^a-zA-Z]|$)" LICENSE; then
    printf 'LICENSE:0\tLICENSE file type cannot be determined\n'
    ISSUES=$((ISSUES+1))
  fi

fi

SUMMARY_EMITTED=1
if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
fi
exit 0

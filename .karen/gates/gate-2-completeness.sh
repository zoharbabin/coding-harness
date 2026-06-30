#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0
# karen-ignore: add this comment to any line to suppress it from Karen gate scanning.

SUMMARY_EMITTED=0
trap '_ec=$?; if [ "$SUMMARY_EMITTED" -eq 0 ]; then printf "GATE_CRASH:0\tgate crashed (exit %s)\n" "$_ec"; echo "FAIL (1 issues)"; fi' EXIT

# --- Go: TODO/FIXME markers ---
while IFS=: read -r file line rest; do
  # ISSUE 1: karen-ignore suppression for Go TODO section
  echo "$rest" | grep -q 'karen-ignore' && continue
  printf '%s:%s\tbroken TODO/FIXME marker — incomplete implementation in production code\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
# ISSUE 4: exclude vendor/; ISSUE 10: make trailing [: ] optional with ([: ]|$); ISSUE 2: anchor .git exclusion; ISSUE 12: cap at 25
done < <(grep -rn --include="*.go" --exclude="*_test.go" --exclude-dir=vendor \
  -E '(//|#)[[:space:]]*(TODO|FIXME|HACK|XXX)([: ]|$)' . 2>/dev/null | grep -v '/.git/' | head -25 || true)

# --- Go: stub implementations ---
while IFS=: read -r file line rest; do
  # ISSUE 1: karen-ignore suppression for Go stub section
  echo "$rest" | grep -q 'karen-ignore' && continue
  printf '%s:%s\tstub implementation — panic or not-implemented placeholder\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
# ISSUE 4: exclude vendor/; ISSUE 7: filter pure comment lines; ISSUE 2: anchor .git exclusion; ISSUE 12: cap at 25
done < <(grep -rn --include="*.go" --exclude="*_test.go" --exclude-dir=vendor \
  -E 'panic\(["`](not implemented|TODO|unimplemented)' . 2>/dev/null | grep -v ':[[:space:]]*//' | grep -v '/.git/' | head -25 || true)

# --- Go: undocumented public exports (ISSUE 5) ---
while IFS=: read -r file line rest; do
  echo "$rest" | grep -q 'karen-ignore' && continue
  linenum_int=$((line))
  if [ "$linenum_int" -gt 1 ]; then
    preceding=$(sed -n "$((linenum_int-1))p" "$file" 2>/dev/null || true)
  else
    preceding=""
  fi
  echo "$preceding" | grep -qE '^[[:space:]]*//' && continue
  printf '%s:%s\tGo: exported identifier lacks doc comment\n' "$file" "$line"
  ISSUES=$((ISSUES+1))
done < <(grep -rn --include="*.go" --exclude="*_test.go" --exclude-dir=vendor \
  -E '^(func|type) [A-Z]' . 2>/dev/null | grep -v '/.git/' | head -25 || true)

# --- JS/TS: scan when files exist ---
JS_FILES=()
while IFS= read -r jsfile; do
  JS_FILES+=("$jsfile")
# Exclude QA tooling dirs — they reference these patterns as regex literals
done < <(find "$ROOT" -maxdepth 8 -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" \) \
  ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/dist/*" ! -path "*/build/*" ! -path "*/coverage/*" \
  ! -path "*/tools/*" ! -path "*/scripts/*" ! -path "*/vendor/*" \
  ! -path "*/test/*" ! -path "*/tests/*" ! -path "*/__tests__/*" \
  ! -path "*/examples/*" ! -path "*/example/*" \
  ! -name "*.test.js" ! -name "*.spec.js" ! -name "*.test.ts" ! -name "*.spec.ts" \
  ! -name "*.d.ts" ! -name "*.test.tsx" ! -name "*.spec.tsx" ! -name "*.test.mjs" ! -name "*.spec.mjs" \
  2>/dev/null || true)

if [ "${#JS_FILES[@]}" -gt 0 ]; then
  for jsf in "${JS_FILES[@]}"; do
    relfile="${jsf#$ROOT/}"
    # Skip binary/null-byte files — grep -n on binary files emits "Binary file … matches"
    # which has no colon-delimited line number and causes $((lineno)) to fail under set -u.
    grep -Iq . "$jsf" 2>/dev/null || continue
    while IFS= read -r rawline; do
      [ -z "$rawline" ] && continue
      # Extract line number and content
      lineno="${rawline%%:*}"
      content="${rawline#*:}"
      # Skip karen-ignore lines
      echo "$content" | grep -q 'karen-ignore' && continue
      # ISSUE 12: raise JS cap to 75
      if [ "$ISSUES" -ge 75 ]; then break; fi
      printf '%s:%s\tJS: TODO/FIXME/stub comment\n' "$relfile" "$lineno"
      ISSUES=$((ISSUES+1))
    # ISSUE 3: anchor to comment syntax to avoid false positives on identifiers
    done < <(grep -n '//[[:space:]]*\(TODO\|FIXME\|HACK\|XXX\)' "$jsf" 2>/dev/null || true)

    while IFS= read -r rawline; do
      [ -z "$rawline" ] && continue
      lineno="${rawline%%:*}"
      content="${rawline#*:}"
      echo "$content" | grep -q 'karen-ignore' && continue
      # ISSUE 12: raise JS cap to 75
      if [ "$ISSUES" -ge 75 ]; then break; fi
      printf '%s:%s\tJS: not-implemented stub\n' "$relfile" "$lineno"
      ISSUES=$((ISSUES+1))
    done < <(grep -ni 'throw new Error\(['"'"'"`]not implemented' "$jsf" 2>/dev/null || true)

    # ISSUE 5: JS/TS undocumented public exports check
    while IFS= read -r rawline; do
      [ -z "$rawline" ] && continue
      lineno="${rawline%%:*}"
      content="${rawline#*:}"
      echo "$content" | grep -q 'karen-ignore' && continue
      if [ "$ISSUES" -ge 75 ]; then break; fi
      linenum_int=$((lineno))
      doc_found=0
      _check=$linenum_int
      while [ "$((_check - 1))" -ge 1 ] && [ "$((_check - linenum_int))" -gt -5 ]; do
        _check=$((_check - 1))
        _lookback=$(sed -n "${_check}p" "$jsf" 2>/dev/null || true)
        # skip blank lines
        echo "$_lookback" | grep -qE '^[[:space:]]*$' && continue
        # first non-blank line: check if it's a doc comment
        echo "$_lookback" | grep -qE '^[[:space:]]*(\*|/\*\*|///)' && doc_found=1
        break
      done
      [ "$doc_found" -eq 1 ] && continue
      printf '%s:%s\tJS: exported function/class lacks JSDoc comment\n' "$relfile" "$lineno"
      ISSUES=$((ISSUES+1))
    done < <(grep -n 'export[[:space:]]\+\(function\|class\|async function\)' "$jsf" 2>/dev/null || true)
  done
fi

SUMMARY_EMITTED=1
if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  printf 'FAIL (%s issues)\n' "$ISSUES"
fi
exit 0

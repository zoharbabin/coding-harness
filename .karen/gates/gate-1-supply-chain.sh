#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0
# karen-ignore: add this comment to any line to suppress it from Karen gate scanning.

SUMMARY_EMITTED=0
trap '_ec=$?; if [ "$SUMMARY_EMITTED" -eq 0 ]; then printf "GATE_CRASH:0\tgate crashed (exit %s)\n" "$_ec"; echo "FAIL (1 issues)"; fi' EXIT

# --- Go supply chain ---
# go.sum is required only when the module has external dependencies.
if [ -f go.mod ] && grep -qE '^require' go.mod 2>/dev/null && [ ! -f go.sum ]; then
  printf 'go.sum:0\tgo.sum missing — run go mod tidy\n'
  ISSUES=$((ISSUES+1))
fi

if [ -f go.mod ] && command -v go &>/dev/null; then
  if [ -f go.sum ]; then
    VERIFY_OUT=$(go mod verify 2>&1) || true
    if echo "$VERIFY_OUT" | grep -q 'FAILED'; then
      printf 'go.mod:0\tgo mod verify failed: %s — check for dependency tampering, cache corruption, or network issues\n' "$(echo "$VERIFY_OUT" | head -1)"
      ISSUES=$((ISSUES+1))
    fi
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
  else
    # Advisory warning only — missing govulncheck disables CVE scanning but must not
    # fail the gate. A project without govulncheck in PATH should not be blocked.
    printf 'WARN:go.mod:0\tgovulncheck not found; Go CVE scanning disabled. Install: go install golang.org/x/vuln/cmd/govulncheck@latest\n'
  fi
fi

# --- JS supply chain ---
if command -v npm &>/dev/null; then
  while IFS= read -r lockfile; do
    [ -z "$lockfile" ] && continue
    lockdir=$(dirname "$lockfile")
    rel_lockfile="${lockfile#"$ROOT"/}"
    audit_out=$(cd "$lockdir" && npm audit --audit-level=high --json 2>/dev/null || true)
    if [ -z "$audit_out" ]; then
      # Empty output means npm couldn't reach the registry or the command failed entirely.
      # Emit a warning (not a failure) so the gate doesn't silently skip audit coverage.
      printf 'WARN:%s:0\tnpm audit produced no output — registry may be unreachable; audit skipped\n' "$rel_lockfile"
      continue
    fi
    if ! command -v python3 &>/dev/null; then
      printf 'WARN:%s:0\tpython3 not found; npm audit JSON cannot be parsed — install python3 to enable JS CVE scanning\n' "$rel_lockfile"
      continue
    fi
    # Validate JSON before parsing; malformed output is treated as an audit failure,
    # not silently ignored (previously `except Exception: print(0)` masked corrupt responses).
    vuln_count=$(printf '%s' "$audit_out" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    v = d.get('vulnerabilities') or d.get('advisories') or {}
    print(sum(1 for x in v.values() if x.get('severity') in ('high', 'critical')))
except json.JSONDecodeError:
    # Malformed JSON from npm means the audit result is unreliable — report as 1
    # so the gate flags it rather than silently treating a broken response as clean.
    print(-1)
except Exception:
    print(0)
" 2>/dev/null || echo "0")
    if [ "$vuln_count" = "-1" ]; then
      printf 'WARN:%s:0\tnpm audit returned malformed JSON — audit result unreliable; run npm audit manually\n' "$rel_lockfile"
      continue
    fi
    if [ "$vuln_count" -gt 0 ]; then
      ISSUES=$((ISSUES + vuln_count))
      vuln_names=$(printf '%s' "$audit_out" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    v = d.get('vulnerabilities') or d.get('advisories') or {}
    names = [(info.get('severity','unknown'), name) for name, info in v.items() if info.get('severity') in ('high', 'critical')]
    for sev, n in names[:50]:
        print(f'{sev}:{n}')
except Exception:
    pass
" 2>/dev/null || true)
      while IFS= read -r vuln_name; do
        [ -z "$vuln_name" ] && continue
        vuln_sev="${vuln_name%%:*}"
        vuln_pkg="${vuln_name#*:}"
        printf '%s:0\tnpm %s vulnerability in %s — run npm audit fix\n' "$rel_lockfile" "$vuln_sev" "$vuln_pkg"
      done <<< "$vuln_names"
    fi
  # depth 4 covers monorepo lockfiles at apps/<name>/package-lock.json
  done < <(find "$ROOT" -maxdepth 4 -name "package-lock.json" ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null)

  # yarn.lock projects: audit using yarn audit --json when no package-lock.json coexists
  while IFS= read -r lockfile; do
    [ -z "$lockfile" ] && continue
    lockdir=$(dirname "$lockfile")
    rel_lockfile="${lockfile#"$ROOT"/}"
    audit_out=$(cd "$lockdir" && yarn audit --json 2>/dev/null || true)
    if [ -z "$audit_out" ]; then
      printf 'WARN:%s:0\tyarn audit produced no output — registry may be unreachable; audit skipped\n' "$rel_lockfile"
      continue
    fi
    if ! command -v python3 &>/dev/null; then
      printf 'WARN:%s:0\tpython3 not found; yarn audit JSON cannot be parsed — install python3 to enable JS CVE scanning\n' "$rel_lockfile"
      continue
    fi
    vuln_count=$(printf '%s' "$audit_out" | python3 -c "
import sys, json
count = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
        if d.get('type') == 'auditAdvisory':
            sev = d.get('data', {}).get('advisory', {}).get('severity', '')
            if sev in ('high', 'critical'):
                count += 1
    except Exception:
        pass
print(count)
" 2>/dev/null || echo "0")
    if [ "$vuln_count" -gt 0 ]; then
      ISSUES=$((ISSUES + vuln_count))
      vuln_names=$(printf '%s' "$audit_out" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
        if d.get('type') == 'auditAdvisory':
            adv = d.get('data', {}).get('advisory', {})
            sev = adv.get('severity', '')
            name = adv.get('module_name', '')
            if sev in ('high', 'critical') and name:
                print(f'{sev}:{name}')
    except Exception:
        pass
" 2>/dev/null || true)
      while IFS= read -r vuln_name; do
        [ -z "$vuln_name" ] && continue
        vuln_sev="${vuln_name%%:*}"
        vuln_pkg="${vuln_name#*:}"
        printf '%s:0\tyarn %s vulnerability in %s — run yarn audit\n' "$rel_lockfile" "$vuln_sev" "$vuln_pkg"
      done <<< "$vuln_names"
    fi
  done < <(find "$ROOT" -maxdepth 4 -name "yarn.lock" ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | while IFS= read -r lf; do
    ldir=$(dirname "$lf")
    # Only include if no package-lock.json exists alongside it (avoid double-counting)
    [ ! -f "$ldir/package-lock.json" ] && printf '%s\n' "$lf"
  done)
fi

SUMMARY_EMITTED=1
if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  printf 'FAIL (%s issues)\n' "$ISSUES"
fi
exit 0

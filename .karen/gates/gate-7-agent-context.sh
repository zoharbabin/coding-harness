#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0

# Check for agent context file (CLAUDE.md, AGENTS.md, or .cursorrules).
CONTEXT_FOUND=0
for f in CLAUDE.md AGENTS.md .cursorrules; do
  if [ -f "$f" ]; then CONTEXT_FOUND=1; break; fi
done
if [ "$CONTEXT_FOUND" -eq 0 ]; then
  printf 'CLAUDE.md:0\tZERO-TOLERANCE: no agent context file found (CLAUDE.md, AGENTS.md, or .cursorrules)\n'
  ISSUES=$((ISSUES+1))
fi

# Check for stopping criteria in context files.
STOPPING_FOUND=0
for f in CLAUDE.md AGENTS.md .cursorrules; do
  if [ -f "$f" ] && grep -qiE \
    'karen audit|exit 0|stopping.criteria|done.criteria|binary exit|definition.of.done|when.to.stop|task.complete|done.when|success.criteria|verif|acceptance' \
    "$f" 2>/dev/null; then
    STOPPING_FOUND=1; break
  fi
done
if [ "$STOPPING_FOUND" -eq 0 ] && [ "$CONTEXT_FOUND" -eq 1 ]; then
  printf 'CLAUDE.md:0\tagent context missing stopping/done criteria — add a "Definition of Done" or karen audit reference\n'
  ISSUES=$((ISSUES+1))
fi

# Check for secrets in context files.
for f in CLAUDE.md AGENTS.md .cursorrules; do
  if [ ! -f "$f" ]; then continue; fi
  while IFS=: read -r file line rest; do
    printf '%s:%s\tpotential secret in agent context file — remove credentials\n' "$file" "$line"
    ISSUES=$((ISSUES+1))
  done < <(grep -n -E '(api_?key|auth_?token|secret_?key|password)[[:space:]]*[:=][[:space:]]*[^$][^{]' "$f" 2>/dev/null | head -10)
done

# Check for MCP server entries — prefer read-only where possible.
if [ -f ".mcp.json" ] || find . -name "mcp*.json" -maxdepth 3 -not -path './.git/*' 2>/dev/null | grep -q .; then
  if grep -rq '"write"\|"delete"\|"execute"' .mcp.json .claude/settings.json 2>/dev/null; then
    printf '.mcp.json:0\tMCP server has write/delete/execute permissions — prefer read-only hygiene\n'
    ISSUES=$((ISSUES+1))
  fi
fi

if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
fi
exit 0

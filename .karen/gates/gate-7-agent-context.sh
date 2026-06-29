#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0
# karen-ignore: add this comment to any line to suppress it from Karen gate scanning.
ZT=0

# Check for agent context file (CLAUDE.md, AGENTS.md, or .cursorrules).
CONTEXT_FOUND=0
for f in CLAUDE.md AGENTS.md .cursorrules; do
  if [ -f "$f" ]; then CONTEXT_FOUND=1; break; fi
done
if [ "$CONTEXT_FOUND" -eq 0 ]; then
  printf 'CLAUDE.md:0\tno agent context file found (CLAUDE.md, AGENTS.md, or .cursorrules)\n'
  ISSUES=$((ISSUES+1))
  ZT=1
fi

# Check for stopping criteria in context files.
STOPPING_FOUND=0
for f in CLAUDE.md AGENTS.md .cursorrules; do
  if [ -f "$f" ] && grep -qiE \
    'karen audit|exit 0|exit.0|count.*=.*0|issues.*=.*0|PASS.*0 issues|stopping.criteria.*exit|done.criteria.*exit|binary exit|definition.of.done.*command|definition.of.done.*exit' \
    "$f" 2>/dev/null; then
    STOPPING_FOUND=1; break
  fi
done
if [ "$STOPPING_FOUND" -eq 0 ] && [ "$CONTEXT_FOUND" -eq 1 ]; then
  printf 'CLAUDE.md:0\tagent context missing binary/runnable done-criteria — stopping condition must reference a runnable command (e.g. '"'"'karen audit exits 0'"'"') not qualitative adjectives\n'
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
MCP_FILES=()
[ -f ".mcp.json" ] && MCP_FILES+=(".mcp.json")
[ -f ".claude/settings.json" ] && MCP_FILES+=(".claude/settings.json")
while IFS= read -r f; do MCP_FILES+=("$f"); done < <(find . -name "mcp*.json" -maxdepth 3 -not -path './.git/*' -not -name ".mcp.json" 2>/dev/null)
if [ "${#MCP_FILES[@]}" -gt 0 ]; then
  if grep -rqE '"write"|"delete"|"execute"' "${MCP_FILES[@]}" 2>/dev/null; then
    printf '.mcp.json:0\tMCP server has write/delete/execute permissions — prefer read-only hygiene\n'
    ISSUES=$((ISSUES+1))
  fi
fi

# Check for overly broad tool permissions in Claude Code settings.
for settings_file in .claude/settings.json .claude/settings.local.json; do
  if [ ! -f "$settings_file" ]; then continue; fi
  # Flag wildcard Bash permissions e.g. "Bash(*)" or "Bash(rm *)"
  if grep -qE '"Bash\s*\(\s*\*' "$settings_file" 2>/dev/null; then
    printf '%s:0\ttool permission scope too broad — Bash(*) grants unrestricted shell access; scope to specific commands\n' "$settings_file"
    ISSUES=$((ISSUES+1))
  fi
  # Flag unrestricted Write permission (Write without a path constraint)
  if grep -qE '"Write\s*\(\s*\*|"allowedTools"[^]]*"Write"[^(]' "$settings_file" 2>/dev/null; then
    printf '%s:0\ttool permission scope too broad — unrestricted Write permission; scope to specific paths\n' "$settings_file"
    ISSUES=$((ISSUES+1))
  fi
done

# Check .cursor/rules for broad permission grants.
if [ -f ".cursor/rules" ] && grep -qiE '(allow|permit|grant).*(write|delete|exec|shell|bash|all)' ".cursor/rules" 2>/dev/null; then
  printf '.cursor/rules:0\ttool permission scope — review broad permission grants in cursor rules\n'
  ISSUES=$((ISSUES+1))
fi

# Check for model selection guidance in context files.
MODEL_GUIDANCE_FOUND=0
for f in CLAUDE.md AGENTS.md .cursorrules; do
  if [ -f "$f" ] && grep -qiE \
    'haiku|sonnet|opus|fable|model.tier|model.selection|claude-3|claude-[0-9]|--model|model:[[:space:]]*['"'"'"]?(haiku|sonnet|opus)' \
    "$f" 2>/dev/null; then
    MODEL_GUIDANCE_FOUND=1; break
  fi
done
if [ "$MODEL_GUIDANCE_FOUND" -eq 0 ] && [ "$CONTEXT_FOUND" -eq 1 ]; then
  printf 'CLAUDE.md:0\tagent context missing model selection guidance — specify which model tier (e.g. haiku/sonnet/opus) to use per task type\n'
  ISSUES=$((ISSUES+1))
fi

# Check for prompt injection surface.
# Source-level scan: find Go files that import known LLM packages, then flag unsafe concatenation.
LLM_IMPORT_FILES=()
while IFS= read -r f; do LLM_IMPORT_FILES+=("$f"); done < <(grep -rlE '"github\.com/anthropics|github\.com/sashabaranov/go-openai|openai|anthropic' --include="*.go" . 2>/dev/null | grep -v '\.git/')
for f in "${LLM_IMPORT_FILES[@]+"${LLM_IMPORT_FILES[@]}"}"; do
  while IFS=: read -r file line rest; do
    # Skip lines with a karen-ignore comment.
    if echo "$rest" | grep -q 'karen-ignore'; then continue; fi
    printf '%s:%s\tpotential prompt injection — fmt.Sprintf or string concat in LLM client file; verify user input is sanitized before insertion\n' "$file" "$line"
    ISSUES=$((ISSUES+1))
  done < <(grep -nE 'fmt\.Sprintf\(|[^:]=.*\+.*[^+]' "$f" 2>/dev/null | head -5)
done

# Context-file declaration check for prompt injection policy.
INJECTION_POLICY_FOUND=0
for f in CLAUDE.md AGENTS.md .cursorrules; do
  if [ -f "$f" ] && grep -qiE 'inject|sanitiz|escap|untrusted.input|user.input' "$f" 2>/dev/null; then
    INJECTION_POLICY_FOUND=1; break
  fi
done
if [ "$INJECTION_POLICY_FOUND" -eq 0 ] && [ "$CONTEXT_FOUND" -eq 1 ]; then
  printf 'CLAUDE.md:0\tagent context missing prompt injection guidance — document how user-controlled input is sanitized before LLM context insertion\n'
  ISSUES=$((ISSUES+1))
fi

if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
  if [ "$ZT" -eq 1 ]; then
    echo "ZERO-TOLERANCE"
  fi
fi
exit 0

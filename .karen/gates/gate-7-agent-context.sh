#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0
# karen-ignore: add this comment to any line to suppress it from Karen gate scanning.
ZT=1

SUMMARY_EMITTED=0
trap '_ec=$?; if [ "$SUMMARY_EMITTED" -eq 0 ]; then printf "GATE_CRASH:0\tgate crashed (exit %s)\n" "$_ec"; echo "FAIL (1 issues)"; fi' EXIT

# Check for agent context file (CLAUDE.md, AGENTS.md, or .cursorrules).
CONTEXT_FOUND=0
for f in CLAUDE.md AGENTS.md .cursorrules; do
  if [ -f "$f" ]; then CONTEXT_FOUND=1; break; fi
done
if [ "$CONTEXT_FOUND" -eq 0 ]; then
  printf 'CLAUDE.md:0\tno agent context file found (CLAUDE.md, AGENTS.md, or .cursorrules)\n'
  ISSUES=$((ISSUES+1))
fi

# Check for stopping criteria in context files.
STOPPING_FOUND=0
for f in CLAUDE.md AGENTS.md .cursorrules; do
  if [ -f "$f" ] && grep -qiE \
    'karen audit|exit 0|exit[[:space:]]0|count.*=.*0|issues.*=.*0|PASS.*0 issues|stopping.criteria.*exit|done.criteria.*exit|binary exit|definition.of.done.*command|definition.of.done.*exit' \
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
    printf '%s:%s\tpotential secret in agent context file — remove credentials\n' "$f" "$file"
    ISSUES=$((ISSUES+1))
  done < <(grep -n -E '(api_?key|apiKey|auth_?token|authToken|secret_?key|secretKey|password|passwd)[[:space:]]*[:=][[:space:]]*[^$][^{]' "$f" 2>/dev/null | head -10 || true)
done

# Check for MCP server entries — prefer read-only where possible.
MCP_FILES=()
[ -f ".mcp.json" ] && MCP_FILES+=(".mcp.json")
[ -f ".claude/settings.json" ] && MCP_FILES+=(".claude/settings.json")
while IFS= read -r f; do MCP_FILES+=("$f"); done < <(find . -name "mcp*.json" -maxdepth 3 -not -path './.git/*' -not -name ".mcp.json" 2>/dev/null || true)
for mf in "${MCP_FILES[@]+"${MCP_FILES[@]}"}"; do
  if grep -iqE '"write"|"delete"|"execute"' "$mf" 2>/dev/null; then
    printf '%s:0\tMCP server has write/delete/execute permissions — prefer read-only hygiene\n' "$mf"
    ISSUES=$((ISSUES+1))
  fi
done

# Check for overly broad tool permissions in Claude Code settings.
for settings_file in .claude/settings.json .claude/settings.local.json; do
  if [ ! -f "$settings_file" ]; then continue; fi
  # Flag wildcard Bash/Edit/MultiEdit permissions e.g. "Bash(*)", "Bash(rm *)", "Edit(*)", "MultiEdit(*)"
  if grep -qE '"(Bash|Edit|MultiEdit)\s*\([^)]*\*' "$settings_file" 2>/dev/null; then
    printf '%s:0\ttool permission scope too broad — Bash/Edit/MultiEdit with wildcard grants unrestricted access; scope to specific commands\n' "$settings_file"
    ISSUES=$((ISSUES+1))
  fi
  # Flag unrestricted Write permission (Write without a path constraint)
  if grep -qE '"Write\s*\(\s*\*' "$settings_file" 2>/dev/null || \
     perl -0777 -ne 'exit 0 if /"allowedTools"[^]]*"Write"[^(]/s; exit 1' "$settings_file" 2>/dev/null; then
    printf '%s:0\ttool permission scope too broad — unrestricted Write permission; scope to specific paths\n' "$settings_file"
    ISSUES=$((ISSUES+1))
  fi
done

# Check .cursor/rules for broad permission grants.
if [ -f ".cursor/rules" ] && grep -viE '^(do not|never|don.t|prohibit|no |not )' ".cursor/rules" | grep -qiE '(allow|permit|grant).*(write|delete|exec|shell|bash|all)' 2>/dev/null; then
  printf '.cursor/rules:0\ttool permission scope — review broad permission grants in cursor rules\n'
  ISSUES=$((ISSUES+1))
fi

# Check for model selection guidance in context files.
MODEL_GUIDANCE_FOUND=0
for f in CLAUDE.md AGENTS.md .cursorrules; do
  if [ -f "$f" ] && grep -qiE \
    '(model|tier|use|claude|ai|llm).{0,30}(haiku|sonnet|opus|fable)|(haiku|sonnet|opus|fable).{0,30}(model|tier|task)|model:[[:space:]]*['"'"'"]?(haiku|sonnet|opus)|--model[[:space:]]*(haiku|sonnet|opus)|claude-[0-9]|claude-3' \
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
while IFS= read -r f; do LLM_IMPORT_FILES+=("$f"); done < <(grep -rlE '"github\.com/anthropics|github\.com/sashabaranov/go-openai|[^"]*openai[^"]*"|[^"]*anthropic[^"]*"' --include="*.go" . 2>/dev/null | grep -v '\.git/' || true)
for f in "${LLM_IMPORT_FILES[@]+"${LLM_IMPORT_FILES[@]}"}"; do
  while IFS=: read -r file line rest; do
    printf '%s:%s\tpotential prompt injection — fmt.Sprintf or string concat in LLM client file; verify user input is sanitized before insertion\n' "$f" "$file"
    ISSUES=$((ISSUES+1))
  done < <(grep -nE 'fmt\.Sprintf\(|\b(prompt|systemPrompt|userMessage|instruction|context)\s*[+]?=.*\+' "$f" 2>/dev/null | grep -v 'karen-ignore' | head -5 || true)
done

# Source-level scan: find JS/MJS files that import known LLM packages, then flag unsafe string concat into prompt variables.
LLM_JS_IMPORT_FILES=()
while IFS= read -r f; do LLM_JS_IMPORT_FILES+=("$f"); done < <(grep -rlE "(require|from)[[:space:]]*['\"]((openai|@anthropic-ai\/sdk|anthropic|langchain|@langchain))" \
  --include="*.js" --include="*.mjs" --include="*.ts" --include="*.tsx" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist \
  . 2>/dev/null || true)
# Content-based detection for AI SDKs not using openai/anthropic imports (e.g. proprietary/custom wrappers).
LLM_JS_FILES=()
while IFS= read -r f; do LLM_JS_FILES+=("$f"); done < <(
  { printf "%s\n" "${LLM_JS_IMPORT_FILES[@]+"${LLM_JS_IMPORT_FILES[@]}"}"; \
    grep -rl \
      -e "systemPrompt" -e "assembleSystemPrompt" -e "buildSystemPrompt" -e "constructPrompt" \
      -e "promptTemplate" -e "buildPrompt" -e "assemblePrompt" \
      -e "chat\.completions" -e "generateContent" -e "invokeModel" \
      --include="*.js" --include="*.mjs" --include="*.ts" --include="*.tsx" \
      . 2>/dev/null \
      | grep -v "/node_modules/" | grep -v "/dist/" | grep -v "/tests/artifacts/" || true; \
  } | sort -u | grep .
)
for f in "${LLM_JS_FILES[@]+"${LLM_JS_FILES[@]}"}"; do
  while IFS=: read -r file line rest; do
    printf '%s:%s\tJS LLM: potential prompt injection via string concat — verify user input is sanitized before insertion\n' "$f" "$file"
    ISSUES=$((ISSUES+1))
  done < <({ grep -nE '(prompt|systemPrompt|userMessage|message|instruction)[^=\n]*=[^=].*\+' "$f" 2>/dev/null; \
             grep -nE '(prompt|systemPrompt|userMessage|message|instruction)[^=\n]*=.*`[^`]*\$\{' "$f" 2>/dev/null; } | grep -v 'karen-ignore' | head -5 || true)
done

# Context-file declaration check for prompt injection policy.
# Requires actual security policy language, not just architectural mentions of injection.
# Bounded span (150 chars) prevents false pass across unrelated sentences; perl -0777 slurps whole file.
# Explicit multi-pattern OR covers: sanitize/escape near untrusted/input/prompt, prompt inject phrases, treat-adversar, never-raw-input.
INJECTION_POLICY_FOUND=0
for f in CLAUDE.md AGENTS.md .cursorrules; do
  if [ ! -f "$f" ]; then continue; fi
  if perl -0777 -ne 'exit 0 if /(?:sanitiz|sanitise|escap).{0,150}(?:untrusted|external|prompt.inject|llm|ai.model)/is; exit 0 if /prompt.inject|inject.*polic|treat.*adversar|never.{0,40}(?:raw|inject).{0,40}(?:user|input|prompt)/is; exit 1' "$f" 2>/dev/null; then
    INJECTION_POLICY_FOUND=1; break
  fi
done
if [ "$INJECTION_POLICY_FOUND" -eq 0 ] && [ "$CONTEXT_FOUND" -eq 1 ]; then
  printf 'CLAUDE.md:0\tagent context missing prompt injection guidance — document how user-controlled input is sanitized before LLM context insertion\n'
  ISSUES=$((ISSUES+1))
fi

SUMMARY_EMITTED=1
if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  printf 'FAIL (%s issues)\n' "$ISSUES"
  if [ "$ZT" -eq 1 ]; then
    echo "ZERO-TOLERANCE"
  fi
fi
exit 0

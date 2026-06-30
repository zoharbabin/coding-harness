#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0
# karen-ignore: add this comment to any line to suppress it from Karen gate scanning.

SUMMARY_EMITTED=0
trap '_ec=$?; if [ "$SUMMARY_EMITTED" -eq 0 ]; then printf "GATE_CRASH:0\tgate crashed (exit %s)\n" "$_ec"; echo "FAIL (1 issues)"; fi' EXIT

if [ ! -f README.md ]; then
  printf 'README.md:0\tREADME.md is missing\n'
  ISSUES=$((ISSUES+1))
  SUMMARY_EMITTED=1
  echo "FAIL ($ISSUES issues)"
  exit 1
fi

# Check Karen's own CLI commands only when this is the Karen repository itself.
if [ -f go.mod ] && grep -q 'github.com/zoharbabin/karen' go.mod 2>/dev/null; then
  for cmd_str in "karen audit" "karen init" "karen reset" "karen upgrade" "karen version"; do
    if ! grep -q "$cmd_str" README.md; then
      printf 'README.md:0\tcommand "%s" not documented\n' "$cmd_str"
      ISSUES=$((ISSUES+1))
    fi
  done
fi

# --- CHECK 1: Symbol references ---
# Extract exported Go symbols and verify each appears in docs.
# ISSUE 6: exclude generated files (*.pb.go, zz_generated.*.go, mock_*.go) and vendor/
# Use -print -quit with variable capture instead of `find | grep -q .` to avoid the
# pipefail+SIGPIPE bug: grep exits early on first match, find gets SIGPIPE (141),
# pipefail surfaces it, and the entire block is silently skipped.
GO_FILES_PROBE=$(find . -name "*.go" -not -name "*_test.go" -not -name "*.pb.go" -not -name "zz_generated.*.go" -not -name "mock_*.go" -not -path "./.git/*" -not -path '*/vendor/*' -print -quit 2>/dev/null || true)
if [ -n "$GO_FILES_PROBE" ]; then
  # Collect all doc files into a temp file for efficient multi-symbol lookup.
  DOCS_TMP=$(mktemp)
  # shellcheck disable=SC2064  # intentional: capture DOCS_TMP at trap registration time
  trap "_ec=\$?; rm -f '$DOCS_TMP'; if [ \"\$SUMMARY_EMITTED\" -eq 0 ]; then printf 'GATE_CRASH:0\tgate crashed (exit %s)\n' \"\$_ec\"; echo 'FAIL (1 issues)'; fi" EXIT
  # ISSUE 10: scan all .md files (not just README + ./docs/) to cover ./doc/, other locations
  {
    find . -name '*.md' -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' \
      -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.next/*' -not -path '*/coverage/*' 2>/dev/null \
      | while IFS= read -r mdf; do
      cat "$mdf" 2>/dev/null || true
    done
  } > "$DOCS_TMP"

  while IFS=: read -r gofile lineno symline; do
    sym=$(echo "$symline" | grep -oE '^func [A-Z][A-Za-z0-9_]+|^type [A-Z][A-Za-z0-9_]+' | awk '{print $2}' | head -1)
    [ -z "$sym" ] && continue
    # ISSUE 5: use word-boundary anchors to avoid false passes on common English substrings
    if ! grep -qE "(^|[^A-Za-z0-9_])${sym}([^A-Za-z0-9_]|$)" "$DOCS_TMP" 2>/dev/null; then
      printf '%s:%s\texported symbol "%s" not referenced in any documentation\n' "$gofile" "$lineno" "$sym"
      ISSUES=$((ISSUES+1))
    fi
  # ISSUE 1 & 6: --exclude-dir=vendor and --exclude generated files; ISSUE 9: no head -100 cap
  done < <(grep -rn --include="*.go" --exclude='*.pb.go' --exclude='zz_generated.*.go' --exclude='mock_*.go' --exclude-dir=vendor -E '^func [A-Z]|^type [A-Z]' . 2>/dev/null \
    | grep -v '_test.go' | grep -v '.git' | grep -v 'karen-ignore' || true)
fi

# --- CHECK 2: Signature drift ---
# For each exported Go function, check if docs contain a divergent signature.
# ISSUE 6: exclude generated files and vendor/
if [ -n "$GO_FILES_PROBE" ]; then
  while IFS=: read -r gofile lineno sigline; do
    # Extract function name and params from source signature.
    funcname=$(echo "$sigline" | grep -oE 'func [A-Z][A-Za-z0-9_]+\(' | head -1 | sed 's/func //;s/($//')
    [ -z "$funcname" ] && continue
    # Find any signature-like lines in docs that mention this function name.
    if grep -q "func $funcname(" "$DOCS_TMP" 2>/dev/null; then
      # Source signature (params only, stripped of leading/trailing whitespace).
      src_sig=$(echo "$sigline" | sed 's/.*func [A-Z][A-Za-z0-9_]*//' | grep -oE '\([^)]*\)' | head -1)
      # Doc signature for the same function.
      doc_sig=$(grep -oE "func ${funcname}\([^)]*\)" "$DOCS_TMP" 2>/dev/null | head -1 | sed "s/func ${funcname}//")
      if [ -n "$doc_sig" ] && [ "$src_sig" != "$doc_sig" ]; then
        printf '%s:%s\tsignature drift: source has "func %s%s" but docs show "func %s%s"\n' \
          "$gofile" "$lineno" "$funcname" "$src_sig" "$funcname" "$doc_sig"
        ISSUES=$((ISSUES+1))
      fi
    fi
  # ISSUE 1 & 6: --exclude-dir=vendor and --exclude generated files; ISSUE 9: no head -100 cap
  done < <(grep -rn --include="*.go" --exclude='*.pb.go' --exclude='zz_generated.*.go' --exclude='mock_*.go' --exclude-dir=vendor -E '^func [A-Z]' . 2>/dev/null \
    | grep -v '_test.go' | grep -v '.git' | grep -v 'karen-ignore' || true)
fi

# --- CHECK 2b: JS exported-symbol coverage — analog of Go exported func/type check ---
# For non-Go projects, verify exported JS/MJS public API symbols appear in documentation.
# Scope: only symbols listed in .karen.json "docs.publicApiSymbols" (allowlist mode), OR
#        when no allowlist is set, only symbols from files matching "docs.publicApiFiles"
#        globs (e.g. ["src/index.js","src/api.js"]).  If neither is configured the check
#        is skipped — scanning every export without an explicit public-API boundary
#        produces false positives for internal helpers and erodes gate trust.
DOC_TMP=""
if [ ! -f go.mod ]; then
  JS_SRC=""
  for d in src lib sdk/src; do
    [ -d "$ROOT/$d" ] && JS_SRC="$ROOT/$d" && break
  done

  if [ -n "$JS_SRC" ]; then
    if [ ! -f "$ROOT/.karen.json" ]; then
      printf 'SKIP: add publicApiFiles to .karen.json to enable API surface check\n' >&2
    else
      # Read public API config (jq preferred; skip check entirely on fallback failure).
      JS_PUBLIC_SYMBOLS=""
      JS_PUBLIC_FILES=""
      if command -v jq &>/dev/null; then
        JS_PUBLIC_SYMBOLS=$(jq -r '(.docs.publicApiSymbols // [])[]' "$ROOT/.karen.json" 2>/dev/null || true)
        JS_PUBLIC_FILES=$(jq -r '(.docs.publicApiFiles // [])[]' "$ROOT/.karen.json" 2>/dev/null || true)
      fi

      # Only run the check when the project has explicitly declared its public surface.
      if [ -n "$JS_PUBLIC_SYMBOLS" ] || [ -n "$JS_PUBLIC_FILES" ]; then
        DOC_TMP=$(mktemp)
        # ISSUE 14: remove -maxdepth 3 to avoid missing docs at depth 4+; also exclude vendor/
        find "$ROOT" -name "*.md" ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/vendor/*" \
          -exec cat {} \; > "$DOC_TMP" 2>/dev/null

        if [ -n "$JS_PUBLIC_SYMBOLS" ]; then
          # Allowlist mode: check only the symbols explicitly declared as public API.
          while IFS= read -r jssym; do
            [ -z "$jssym" ] && continue
            if ! grep -q "$jssym" "$DOC_TMP" 2>/dev/null; then
              printf '%s:0\tJS public API symbol %s (declared in .karen.json) not found in any documentation file\n' "$JS_SRC" "$jssym"
              ISSUES=$((ISSUES+1))
            fi
          done <<< "$JS_PUBLIC_SYMBOLS"
        elif [ -n "$JS_PUBLIC_FILES" ]; then
          # File-scope mode: check exports only from explicitly declared public-API files.
          while IFS= read -r api_file; do
            [ -z "$api_file" ] && continue
            full_path="$ROOT/$api_file"
            [ -f "$full_path" ] || continue
            while IFS= read -r jssym; do
              [ -z "$jssym" ] && continue
              [ "${#jssym}" -le 1 ] && continue
              [ "$jssym" = "default" ] && continue
              if ! grep -q "$jssym" "$DOC_TMP" 2>/dev/null; then
                printf '%s:0\tJS exported symbol %s (from public API file %s) not found in any documentation file\n' "$JS_SRC" "$jssym" "$api_file"
                ISSUES=$((ISSUES+1))
              fi
            done < <(
              # Capture: export function/class/const/let Foo, export async function Foo,
              # and ESM re-exports: export { Foo, Bar } from '...' or export { Foo as default } from '...'
              {
                # ISSUE 11: extend alternation to cover TypeScript-specific export forms
                # (abstract class, type, interface, enum, var) in addition to function/class/const/let
                grep -h "^export " "$full_path" 2>/dev/null \
                  | sed "s/export async /export /" \
                  | grep -oE "^export (abstract class|function|class|const|let|var|type|interface|enum) [A-Za-z][A-Za-z0-9_]*" \
                  | awk '{print $NF}'
                # Named re-exports: extract identifiers from export { Foo, Bar as Baz } from '...'
                # ISSUE 2: strip braces, split on comma, strip "as Alias" suffixes to avoid
                #          bogus concatenated symbols like "BarasBaz"; also drop leading '{' artifact
                grep -hE "^export[[:space:]]*\{[^}]+\}" "$full_path" 2>/dev/null \
                  | grep -oE "\{[^}]+\}" \
                  | tr -d '{}' \
                  | tr ',' '\n' \
                  | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]][Aa][Ss][[:space:]][A-Za-z][A-Za-z0-9_]*//' \
                  | grep -oE '^[A-Za-z][A-Za-z0-9_]+' \
                  | grep -v '^default$'
              } | sort -u || true
            )
          done <<< "$JS_PUBLIC_FILES"
        fi

        rm -f "$DOC_TMP"
      fi
      # If neither publicApiSymbols nor publicApiFiles is configured, skip silently.
      # Add one of these to .karen.json to enable JS symbol coverage checking.
    fi
  fi
fi

# --- CHECK 3: Dead links ---
# Find all internal markdown links and verify the targets exist.
# Prefer perl for correct multi-match-per-line extraction; fall back to grep+sed on
# systems where perl is absent (hardened CI, macOS Sequoia+ minimal images).
_extract_md_links() {
  local mdfile="$1"
  if command -v perl &>/dev/null; then
    perl -ne 'next if /karen-ignore/; while (/\]\(([^)]+)\)/g) { print "$1\n" }' "$mdfile" 2>/dev/null || true
  else
    # Pure-bash fallback: one link per line covered; multi-link lines may miss extras.
    grep -v 'karen-ignore' "$mdfile" 2>/dev/null | grep -oE '\]\([^)]+\)' | sed 's/^](\(.*\))$/\1/' || true
  fi
}

while IFS= read -r mdfile; do
  [ -f "$mdfile" ] || continue
  while IFS= read -r link; do
    # Strip query strings and anchors.
    target=$(printf '%s' "$link" | sed 's/#.*//' | sed 's/?.*$//')
    [ -z "$target" ] && continue
    # Resolve relative path from the markdown file's directory.
    mddir=$(dirname "$mdfile")
    if [[ "$target" == /* ]]; then
      resolved="$ROOT/$target"
    else
      resolved="$mddir/$target"
    fi
    if [ ! -f "$resolved" ] && [ ! -d "$resolved" ]; then
      printf '%s:0\tdead link: "%s" does not exist\n' "$mdfile" "$link"
      ISSUES=$((ISSUES+1))
    fi
  # ISSUE 3 & 13: add grep -v '^//' to filter protocol-relative URLs (e.g. //cdn.example.com/…)
  done < <(_extract_md_links "$mdfile" \
    | grep -v '^https\?://' | grep -v '^http://' | grep -v '^mailto:' | grep -v '^#' | grep -v '^//' || true)
# ISSUE 12: scan all .md files, not just README.md + ./docs/*.md
done < <(find . -name '*.md' -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' \
  -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.next/*' -not -path '*/coverage/*' 2>/dev/null \
  | sort -u || true)

# --- CHECK 4: CHANGELOG gaps ---
# Three-step flow:
#   1. CHANGELOG.md exists → verify it is updated since last release tag.
#   2. No CHANGELOG.md → check if GitHub Releases have substantive notes (valid substitute).
#   3. Neither → flag as a gap.
if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  last_tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
  CHANGELOG_FOUND_4=$(find . -maxdepth 2 -name "CHANGELOG.md" -not -path "./.git/*" -not -path "./vendor/*" -not -path "./node_modules/*" 2>/dev/null | head -1)

  if [ -n "$CHANGELOG_FOUND_4" ]; then
    # Step 1: CHANGELOG.md exists — check for unreleased commits not yet documented.
    if [ -n "$last_tag" ]; then
      commit_count=$(git log "${last_tag}..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')
      if [ "$commit_count" -gt 0 ]; then
        if [ -z "$(git log "${last_tag}..HEAD" --oneline -- CHANGELOG.md 2>/dev/null)" ]; then
          printf 'CHANGELOG.md:0\t%s unreleased commit(s) since tag "%s" not reflected in CHANGELOG.md\n' \
            "$commit_count" "$last_tag"
          ISSUES=$((ISSUES+1))
        fi
      fi
    fi
  elif [ -n "$last_tag" ]; then
    # No CHANGELOG.md but a release tag exists — step 2: check GitHub Releases.
    GH_RELEASES_FRESH=0
    GH_CLI_AVAILABLE=0
    if command -v gh &>/dev/null; then
      # Verify the most recent GH release corresponds to the most recent git tag and has notes.
      # Capture stderr to detect auth/network errors without letting them propagate as failures.
      if command -v jq &>/dev/null; then
        _gh_list_out=$(gh release list --limit 1 --json tagName 2>&1)
        _gh_list_ec=$?
        if [ "$_gh_list_ec" -ne 0 ]; then
          printf 'WARN: gh CLI unavailable --- GitHub Releases freshness check skipped; install gh and authenticate to enable full check\n' >&2
        else
          GH_CLI_AVAILABLE=1
          _latest_gh_tag=$(echo "$_gh_list_out" | jq -r '.[0].tagName // ""' 2>/dev/null || true)
        fi
      else
        _gh_list_out=$(gh release list --limit 1 2>&1)
        _gh_list_ec=$?
        if [ "$_gh_list_ec" -ne 0 ]; then
          printf 'WARN: gh CLI unavailable --- GitHub Releases freshness check skipped; install gh and authenticate to enable full check\n' >&2
        else
          GH_CLI_AVAILABLE=1
          _latest_gh_tag=$(echo "$_gh_list_out" | awk 'NR==1{print $1}' || true)
        fi
      fi
      if [ "$GH_CLI_AVAILABLE" -eq 1 ] && [ -n "$_latest_gh_tag" ]; then
        _gh_json=$(gh release view "$_latest_gh_tag" --json body 2>/dev/null || true)
        if command -v jq &>/dev/null; then
          _gh_body=$(echo "$_gh_json" | jq -r '.body // ""' 2>/dev/null || true)
        else
          _gh_body=$(echo "$_gh_json" | grep -o '"body":"[^"]*"' \
            | sed 's/"body":"//;s/"$//' 2>/dev/null || true)
        fi
        _gh_stripped=$(echo "$_gh_body" | tr -d '[:space:]')
        [ "${#_gh_stripped}" -gt 20 ] && GH_RELEASES_FRESH=1
      fi
    else
      printf 'WARN:gh:0\tgh CLI unavailable --- GitHub Releases freshness check skipped; install gh and authenticate to enable full check\n'
    fi

    if [ "$GH_RELEASES_FRESH" -eq 1 ]; then
      # Check if commits since last tag are covered: GH release tag should match last git tag.
      commit_count=$(git log "${last_tag}..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')
      if [ "$commit_count" -gt 0 ] && [ "$_latest_gh_tag" != "$last_tag" ]; then
        printf 'CHANGELOG.md:0\t%s unreleased commit(s) since tag "%s" — no CHANGELOG.md and latest GitHub Release is "%s", not "%s"; update release notes\n' \
          "$commit_count" "$last_tag" "$_latest_gh_tag" "$last_tag"
        ISSUES=$((ISSUES+1))
      else
        : # GitHub Releases in sync with latest tag — preferred practice, no action needed
      fi
    elif [ "${GH_CLI_AVAILABLE:-0}" -eq 0 ]; then
      # gh was unavailable — cannot confirm release notes; skip rather than FAIL.
      : # WARN already emitted above; do not penalize projects that lack gh CLI
    else
      # Step 3: gh was available but found no substantive release notes — flag as a gap.
      printf 'CHANGELOG.md:0\tgit tag "%s" exists but no changelog — create CHANGELOG.md or publish GitHub Releases with release notes\n' "$last_tag"
      ISSUES=$((ISSUES+1))
    fi
  fi
fi

# --- CHECK 5: Runnable examples ---
# Read doctest config from .karen.json and execute annotated code blocks.
ANNOTATION="karen:runnable"
DOCTEST_FILES=""

if [ -f .karen.json ]; then
  # Extract annotation value (jq preferred; grep/awk fallback).
  if command -v jq &>/dev/null; then
    ANNOTATION=$(jq -r '.doctest.annotation // "karen:runnable"' .karen.json 2>/dev/null || echo "karen:runnable")
    DOCTEST_FILES=$(jq -r '.doctest.files // [] | .[]' .karen.json 2>/dev/null || true)
  else
    # Fallback: grep for annotation and files values.
    ANN_VAL=$(grep -o '"annotation"[[:space:]]*:[[:space:]]*"[^"]*"' .karen.json 2>/dev/null \
      | grep -o '"[^"]*"$' | tr -d '"' || true)
    [ -n "$ANN_VAL" ] && ANNOTATION="$ANN_VAL"
    # Files glob extraction via awk (simple line-by-line scan of the files array).
    DOCTEST_FILES=$(awk '
      /"files"/ { in_files=1; next }
      in_files && /\]/ { in_files=0; next }
      in_files && match($0, /"[^"]+"/) { val=substr($0, RSTART+1, RLENGTH-2); print val }
    ' .karen.json 2>/dev/null || true)
  fi
fi

if [ -n "$DOCTEST_FILES" ]; then
  TMPDIR_DOCTEST=$(mktemp -d)
  # shellcheck disable=SC2064  # intentional: capture paths at trap registration time
  trap "_ec=\$?; rm -rf '$TMPDIR_DOCTEST'; rm -f '${DOCS_TMP:-}'; rm -f '${DOC_TMP:-}'; if [ \"\$SUMMARY_EMITTED\" -eq 0 ]; then printf 'GATE_CRASH:0\tgate crashed (exit %s)\n' \"\$_ec\"; echo 'FAIL (1 issues)'; fi" EXIT

  ann_escaped=$(printf '%s' "$ANNOTATION" | sed 's/[].\*^$[{(|+?]/\\&/g')
  while IFS= read -r glob_pattern; do
    [ -z "$glob_pattern" ] && continue
    # Expand the glob relative to ROOT.
    while IFS= read -r docfile; do
      [ -f "$docfile" ] || continue
      # Extract annotated fenced code blocks: ```<lang> karen:runnable ... ```
      block_num=0
      in_block=0
      lang_id=""
      block_lines=""
      block_start_line=0
      lineno=0
      while IFS= read -r rawline; do
        lineno=$((lineno+1))
        if [ "$in_block" -eq 0 ]; then
          # Check for opening fence with annotation.
          # ISSUE 15: support tilde fences (~~~) and extended backtick fences (````+)
          if echo "$rawline" | grep -qE '^(`{3,}|~{3,})[a-zA-Z].*'"$ann_escaped"; then
            in_block=1
            lang_id=$(echo "$rawline" | sed 's/^[`~]*//' | awk '{print $1}')
            block_lines=""
            block_start_line=$lineno
            block_num=$((block_num+1))
          fi
        else
          # Check for closing fence.
          # ISSUE 15: support tilde fences and extended backtick fences for closing too
          if echo "$rawline" | grep -qE '^(`{3,}|~{3,})[[:space:]]*$'; then
            in_block=0
            # Determine runtime from lang_id.
            runtime=""
            case "$lang_id" in
              bash|sh) runtime="bash" ;;
              js|javascript) runtime="node" ;;
              ts|typescript) runtime="node" ;;
              python|py) runtime="python3" ;;
            esac
            if [ -n "$runtime" ] && command -v "$runtime" &>/dev/null; then
              # Write block to temp file with appropriate extension.
              case "$runtime" in
                bash)    ext="sh" ;;
                node)    ext="js" ;;
                python3) ext="py" ;;
                *)       ext="txt" ;;
              esac
              block_file="$TMPDIR_DOCTEST/block_${block_num}.${ext}"
              printf '%s\n' "$block_lines" > "$block_file"
              "$runtime" "$block_file" >/dev/null 2>&1
              exit_code=$?
              if [ "$exit_code" -ne 0 ]; then
                printf '%s:%s\texample tagged %s failed with exit %s\n' \
                  "$docfile" "$block_start_line" "$ANNOTATION" "$exit_code"
                ISSUES=$((ISSUES+1))
              fi
            fi
          else
            if [ -z "$block_lines" ]; then
              block_lines="$rawline"
            else
              block_lines="$block_lines
$rawline"
            fi
          fi
        fi
      done < "$docfile"
    done < <(find . -path "./.git/*" -prune -o -path "./${glob_pattern}" -print 2>/dev/null \
      | grep -v '.git' || true)
  done <<< "$DOCTEST_FILES"
fi

SUMMARY_EMITTED=1
if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
  exit 0
else
  echo "FAIL ($ISSUES issues)"
  exit 1
fi

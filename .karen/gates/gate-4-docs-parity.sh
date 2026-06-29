#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
cd "$ROOT"
ISSUES=0
# karen-ignore: add this comment to any line to suppress it from Karen gate scanning.

if [ ! -f README.md ]; then
  printf 'README.md:0\tREADME.md is missing\n'
  ISSUES=$((ISSUES+1))
  echo "FAIL ($ISSUES issues)"
  exit 0
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
if find . -name "*.go" -not -name "*_test.go" -not -path "./.git/*" 2>/dev/null | grep -q .; then
  # Collect all doc files into a temp file for efficient multi-symbol lookup.
  DOCS_TMP=$(mktemp)
  # shellcheck disable=SC2064  # variable set here intentionally captured
  trap "rm -f '$DOCS_TMP'" EXIT
  {
    cat README.md 2>/dev/null || true
    find . -path './docs/*.md' -o -path './docs/**/*.md' 2>/dev/null | while IFS= read -r mdf; do
      cat "$mdf" 2>/dev/null || true
    done
  } > "$DOCS_TMP"

  while IFS=: read -r gofile lineno symline; do
    sym=$(echo "$symline" | grep -oE '^func [A-Z][A-Za-z0-9_]+|^type [A-Z][A-Za-z0-9_]+' | awk '{print $2}' | head -1)
    [ -z "$sym" ] && continue
    if ! grep -q "$sym" "$DOCS_TMP" 2>/dev/null; then
      printf '%s:%s\texported symbol "%s" not referenced in any documentation\n' "$gofile" "$lineno" "$sym"
      ISSUES=$((ISSUES+1))
    fi
  done < <(grep -rn --include="*.go" -E '^func [A-Z]|^type [A-Z]' . 2>/dev/null \
    | grep -v '_test.go' | grep -v '.git' | head -100)
fi

# --- CHECK 2: Signature drift ---
# For each exported Go function, check if docs contain a divergent signature.
if find . -name "*.go" -not -name "*_test.go" -not -path "./.git/*" 2>/dev/null | grep -q .; then
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
  done < <(grep -rn --include="*.go" -E '^func [A-Z]' . 2>/dev/null \
    | grep -v '_test.go' | grep -v '.git' | head -100)
fi

# --- CHECK 3: Dead links ---
# Find all internal markdown links and verify the targets exist.
while IFS= read -r mdfile; do
  # Extract link targets: [text](./path) or [text](path) — skip http(s):// and anchors.
  while IFS= read -r link; do
    # Strip query strings and anchors.
    target=$(echo "$link" | sed 's/#.*//' | sed 's/?.*$//')
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
  done < <(grep -oE '\]\(([^)]+)\)' "$mdfile" 2>/dev/null \
    | sed 's/^](//' | sed 's/)$//' \
    | grep -v '^https\?://' | grep -v '^mailto:' | grep -v '^#' || true)
done < <(find . \( -name "README.md" -o -path './docs/*.md' -o -path './docs/**/*.md' \) \
  -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' 2>/dev/null)

# --- CHECK 4: CHANGELOG gaps ---
# If git is available, detect commits since last release tag not reflected in CHANGELOG.
if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  last_tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
  if [ -n "$last_tag" ] && [ -f CHANGELOG.md ]; then
    commit_count=$(git log "${last_tag}..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')
    if [ "$commit_count" -gt 0 ]; then
      # Check if CHANGELOG was modified more recently than the last tag commit.
      tag_ts=$(git log -1 --format="%ct" "$last_tag" 2>/dev/null || echo "0")
      changelog_ts=$(git log -1 --format="%ct" -- CHANGELOG.md 2>/dev/null || echo "0")
      if [ "$changelog_ts" -le "$tag_ts" ]; then
        printf 'CHANGELOG.md:0\t%s unreleased commit(s) since tag "%s" not reflected in CHANGELOG.md\n' \
          "$commit_count" "$last_tag"
        ISSUES=$((ISSUES+1))
      fi
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
      /\"files\"/ { in_files=1; next }
      in_files && /\]/ { in_files=0; next }
      in_files && /\"[^"]+\"/ { match($0, /"([^"]+)"/, a); print a[1] }
    ' .karen.json 2>/dev/null || true)
  fi
fi

if [ -n "$DOCTEST_FILES" ]; then
  TMPDIR_DOCTEST=$(mktemp -d)
  # shellcheck disable=SC2064  # variable set here intentionally captured
  trap "rm -rf '$TMPDIR_DOCTEST'" EXIT

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
          if echo "$rawline" | grep -qE '^\`\`\`[a-zA-Z].*'"$ANNOTATION"; then
            in_block=1
            lang_id=$(echo "$rawline" | sed 's/^```//' | awk '{print $1}')
            block_lines=""
            block_start_line=$lineno
            block_num=$((block_num+1))
          fi
        else
          # Check for closing fence.
          if echo "$rawline" | grep -qE '^\`\`\`[[:space:]]*$'; then
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
              if ! "$runtime" "$block_file" >/dev/null 2>&1; then
                exit_code=$?
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
    done < <(find . -path "./.git/*" -prune -o -name "${glob_pattern##*/}" -print 2>/dev/null \
      | grep -v '.git' || true)
  done <<< "$DOCTEST_FILES"
fi

if [ "$ISSUES" -eq 0 ]; then
  echo "PASS (0 issues)"
else
  echo "FAIL ($ISSUES issues)"
fi
exit 0

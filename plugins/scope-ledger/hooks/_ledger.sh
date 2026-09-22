#!/bin/bash
# Shared ledger helpers for the scope-ledger hooks. Sourced, not executed.
# Every function is quiet on error and prints nothing / a safe default; callers fail-open.
#
# Ledger shape (see skills/scope/SKILL.md for the full template):
#   ---                      ← frontmatter: goal / branch / opened / review_rounds
#   ...
#   ---
#   ## In scope              ← "- [ ] item" open, "- [x] item" done
#   ## Deferred
#   ## Log

LEDGER_REL=".claude/scope-ledger.local.md"

# ledger_path <proj> → absolute ledger path (existence not checked)
ledger_path() { printf '%s/%s\n' "${1%/}" "$LEDGER_REL"; }

# ledger_field <file> <key> → value of "<key>: …" inside the leading --- frontmatter block
ledger_field() {
  [ -f "$1" ] || return 0
  awk -v k="$2" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, k ":") == 1 { s = substr($0, length(k) + 2); sub(/^[ \t]+/, "", s); print s; exit }
  ' "$1" 2>/dev/null
}

# ledger_unchecked <file> → every "- [ ] …" line inside "## In scope" (empty when none)
ledger_unchecked() {
  [ -f "$1" ] || return 0
  awk '
    /^## / { insec = ($0 == "## In scope"); next }
    insec && /^- \[ \] / { print }
  ' "$1" 2>/dev/null
}

# ledger_rounds <file> → review_rounds as a non-negative integer (0 when missing / not numeric)
ledger_rounds() {
  local v
  v=$(ledger_field "$1" review_rounds)
  case "$v" in '' | *[!0-9]*) echo 0 ;; *) echo "$v" ;; esac
}

# ledger_bump_rounds <file> → review_rounds + 1, written back in place (key added when absent);
# prints the new value. Returns 1 (prints nothing) when the file cannot be rewritten.
ledger_bump_rounds() {
  local f="$1" n tmp
  [ -f "$f" ] || return 1
  n=$(( $(ledger_rounds "$f") + 1 ))
  tmp="$f.tmp.$$"
  if awk -v n="$n" '
      NR == 1 && $0 == "---" { fm = 1; print; next }
      fm && !done && $0 == "---" { print "review_rounds: " n; done = 1; fm = 0; print; next }
      fm && !done && index($0, "review_rounds:") == 1 { print "review_rounds: " n; done = 1; next }
      { print }
    ' "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f" 2>/dev/null; then
    echo "$n"
  else
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
}

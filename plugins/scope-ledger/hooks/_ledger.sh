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

# ledger_tracked <proj> → exit 0 when git tracks the ledger. A tracked ledger is repository-
# controlled content (anyone who can commit to the repo can write it), so no hook replays it
# into context, quotes it in a message, or writes to it. Every hook treats it as absent.
# Not a git repo / git failure → exit 1 (not tracked), which keeps the fail-open direction.
ledger_tracked() { git -C "${1%/}" ls-files --error-unmatch -- "$LEDGER_REL" >/dev/null 2>&1 || return 1; }

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

# ledger_bump_rounds <file> → review_rounds + 1, written back in place; prints the new value.
# A missing key is added inside the frontmatter; a file with no frontmatter at all (or an empty
# file) gets one synthesised in front of its content, so the counter really advances instead of
# silently reporting 1 forever. Returns 1 (prints nothing) when the file cannot be rewritten or
# the lock cannot be taken within ~1 s.
# Read-modify-write is serialised with a mkdir lock (atomic on every POSIX filesystem): two review
# hooks finishing in the same batch would otherwise both read N and both write N+1.
ledger_bump_rounds() {
  local f="$1" n tmp lock i rc
  [ -f "$f" ] || return 1
  lock="$f.lock"
  i=0
  until mkdir "$lock" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 20 ] && return 1
    sleep 0.05
  done
  n=$(( $(ledger_rounds "$f") + 1 ))
  tmp="$f.tmp.$$"
  rc=1
  if [ "$(head -1 "$f" 2>/dev/null)" = "---" ]; then
    awk -v n="$n" '
      NR == 1 && $0 == "---" { fm = 1; print; next }
      fm && !done && $0 == "---" { print "review_rounds: " n; done = 1; fm = 0; print; next }
      fm && !done && index($0, "review_rounds:") == 1 { print "review_rounds: " n; done = 1; next }
      { print }
    ' "$f" > "$tmp" 2>/dev/null && rc=0
  else
    { printf -- '---\nreview_rounds: %s\n---\n' "$n"; cat "$f"; } > "$tmp" 2>/dev/null && rc=0
  fi
  if [ "$rc" -eq 0 ] && mv "$tmp" "$f" 2>/dev/null; then
    rc=0
  else
    rc=1
    rm -f "$tmp" 2>/dev/null
  fi
  rmdir "$lock" 2>/dev/null
  [ "$rc" -eq 0 ] || return 1
  echo "$n"
}

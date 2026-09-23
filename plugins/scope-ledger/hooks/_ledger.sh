#!/bin/bash
# Shared ledger helpers for the scope-ledger hooks. Sourced, not executed.
# Every function is quiet on error and prints nothing / a safe default; callers fail-open.
#
# Ledger shape (see skills/scope/SKILL.md for the full template):
#   ---                      ← frontmatter: goal / mode / opened / opened_on / review_rounds
#   ...
#   ---
#   ## In scope              ← "- [ ] item" open, "- [x] item" done (top-level lines only)
#   ## Deferred
#   ## Log
#
# Follow-ups file (cross-ledger backlog, one item per line):
#   - [ ] 2026-09-23 HIGH item ← from: <goal> ｜ 來源: … ｜ 去處: …

LEDGER_REL=".claude/scope-ledger.local.md"
FOLLOWUPS_REL=".claude/scope-followups.local.md"
LOCK_STALE_SECS=30

# ledger_path <proj> / followups_path <proj> → absolute path (existence not checked)
ledger_path()    { printf '%s/%s\n' "${1%/}" "$LEDGER_REL"; }
followups_path() { printf '%s/%s\n' "${1%/}" "$FOLLOWUPS_REL"; }

# path_tracked <proj> <rel> → exit 0 when <proj>/<rel> is repository-controlled content (anyone who
# can commit to the repo can write it), so no hook replays it into context, quotes it in a message,
# or writes to it. "Repository-controlled" is a property of the PATH, not only of an index entry at
# that exact name — a committed `.claude` symlink or a `.claude` submodule puts a real file at the
# path after a plain clone while `ls-files -- <rel>` finds nothing (security review reproduced both
# layouts against every hook). Hence four checks, cheapest first:
#   1. <proj>/.claude is a symlink                      → 0
#   2. the file itself is a symlink                      → 0
#   3. the index entry for .claude is 120000 (symlink) or 160000 (gitlink / submodule) → 0
#   4. the path is an index entry (plain tracked)        → 0
# Not a git repo / git failure → 1 (not tracked), which keeps the fail-open direction.
path_tracked() {
  local p="${1%/}" rel="$2" mode
  [ -L "$p/.claude" ] && return 0
  [ -L "$p/$rel" ] && return 0
  mode=$(git -C "$p" ls-files --stage -- .claude 2>/dev/null | awk '{ print $1; exit }')
  case "$mode" in 120000 | 160000) return 0 ;; esac
  git -C "$p" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || return 1
}
ledger_tracked()    { path_tracked "$1" "$LEDGER_REL"; }
followups_tracked() { path_tracked "$1" "$FOLLOWUPS_REL"; }

# ledger_usable <proj> / followups_usable <proj> → 0 when the file exists and is not repository-controlled
ledger_usable()    { [ -f "$(ledger_path "$1")" ] && ! ledger_tracked "$1"; }
followups_usable() { [ -f "$(followups_path "$1")" ] && ! followups_tracked "$1"; }

# ledger_field <file> <key> → value of "<key>: …" inside the leading --- frontmatter block
ledger_field() {
  [ -f "$1" ] || return 0
  awk -v k="$2" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, k ":") == 1 { s = substr($0, length(k) + 2); sub(/^[ \t]+/, "", s); print s; exit }
  ' "$1" 2>/dev/null
}

# ledger_mode <file> → "harvest" when the frontmatter says so, otherwise "converge"
ledger_mode() {
  local m
  m=$(ledger_field "$1" mode)
  case "$m" in harvest) echo harvest ;; *) echo converge ;; esac
}

# ledger_section <file> <heading-text> → the lines of that "## <heading>" section (heading excluded)
ledger_section() {
  [ -f "$1" ] || return 0
  awk -v h="## $2" '
    /^## / { insec = ($0 == h); next }
    insec { print }
  ' "$1" 2>/dev/null
}

# ledger_unchecked <file> → every top-level "- [ ] …" line inside "## In scope" (empty when none)
ledger_unchecked() {
  [ -f "$1" ] || return 0
  awk '
    /^## / { insec = ($0 == "## In scope"); next }
    insec && /^- \[ \] / { print }
  ' "$1" 2>/dev/null
}

# ledger_frontmatter <file> → the leading --- block including both fences (empty when absent)
ledger_frontmatter() {
  [ -f "$1" ] || return 0
  awk '
    NR == 1 { if ($0 != "---") exit; print; next }
    { print }
    NR > 1 && $0 == "---" { exit }
  ' "$1" 2>/dev/null
}

# count_lines <text> → number of non-empty lines (0 for empty input)
count_lines() {
  if [ -n "$1" ]; then printf '%s\n' "$1" | grep -c .; else echo 0; fi
}

# ledger_rounds <file> → review_rounds as a non-negative integer (0 when missing / not numeric)
ledger_rounds() {
  local v
  v=$(ledger_field "$1" review_rounds)
  case "$v" in '' | *[!0-9]*) echo 0 ;; *) echo "$v" ;; esac
}

# lock_take <lockdir> → 0 when the mkdir lock was taken. Waits up to ~1 s; a lock older than
# LOCK_STALE_SECS is removed first — a hook killed by its timeout would otherwise leave the lock
# behind and every later bump would wait, give up and silently stop counting forever.
lock_take() {
  local lock="$1" i=0 now mtime
  until mkdir "$lock" 2>/dev/null; do
    if [ "$i" -eq 0 ]; then
      now=$(date +%s 2>/dev/null) || now=""
      mtime=$(stat -c %Y "$lock" 2>/dev/null || stat -f %m "$lock" 2>/dev/null) || mtime=""
      case "$now$mtime" in *[!0-9]* | '') : ;; *)
        if [ $((now - mtime)) -gt "$LOCK_STALE_SECS" ]; then rmdir "$lock" 2>/dev/null; fi ;;
      esac
    fi
    i=$((i + 1))
    [ "$i" -ge 20 ] && return 1
    sleep 0.05
  done
  return 0
}

# ledger_bump_rounds <file> → review_rounds + 1, written back in place; prints the new value.
# A missing key is added inside the frontmatter; a file with no frontmatter at all (or an empty
# file) gets one synthesised in front of its content, so the counter really advances instead of
# silently reporting 1 forever. Returns 1 (prints nothing) when the file cannot be rewritten or
# the lock cannot be taken. Never writes through a symlink (the file or its directory).
ledger_bump_rounds() {
  local f="$1" n tmp lock rc
  [ -f "$f" ] || return 1
  [ -L "$f" ] && return 1
  [ -L "$(dirname "$f")" ] && return 1
  lock="$f.lock"
  lock_take "$lock" || return 1
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

# followups_open <file> → every open follow-up line; followups_high <file> → the open HIGH ones
followups_open() { [ -f "$1" ] || return 0; grep -E '^- \[ \] ' "$1" 2>/dev/null || true; }
followups_high() { [ -f "$1" ] || return 0; grep -E '^- \[ \] [0-9-]+ HIGH([[:space:]]|$)' "$1" 2>/dev/null || true; }

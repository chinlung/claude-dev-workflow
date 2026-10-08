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
# Checks 3 and 4 use the `:(icase)` pathspec: on a case-insensitive filesystem (macOS APFS by
# default, Windows) a repository that commits `.Claude/scope-ledger.local.md` puts a real file at
# `.claude/scope-ledger.local.md`, while git pathspecs stay case-sensitive and would report it
# untracked (security review reproduced the bypass). On a case-sensitive filesystem the same
# lookup can only err toward "tracked" — the direction that ignores a ledger, never one that
# replays repository text.
# Not a git repo / git failure → 1 (not tracked), which keeps the fail-open direction.
path_tracked() {
  local p="${1%/}" rel="$2" mode
  [ -L "$p/.claude" ] && return 0
  [ -L "$p/$rel" ] && return 0
  mode=$(git -C "$p" ls-files --stage -- ':(icase).claude' 2>/dev/null | awk '{ print $1; exit }')
  case "$mode" in 120000 | 160000) return 0 ;; esac
  git -C "$p" ls-files --error-unmatch -- ":(icase)$rel" >/dev/null 2>&1 || return 1
}
ledger_tracked()    { path_tracked "$1" "$LEDGER_REL"; }
followups_tracked() { path_tracked "$1" "$FOLLOWUPS_REL"; }

# ledger_usable <proj> / followups_usable <proj> → 0 when the file exists and is not repository-controlled
ledger_usable()    { [ -f "$(ledger_path "$1")" ] && ! ledger_tracked "$1"; }
followups_usable() { [ -f "$(followups_path "$1")" ] && ! followups_tracked "$1"; }

# The grammar of both files lives in ONE place, scope-parse.awk. Every reader below goes through it, so
# "what counts as an open item" is decided once, and a line that does not fit is reported with a reason
# instead of being silently counted by one hook and dropped by another.
SCOPE_PARSE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scope-parse.awk"

# scope_parse <ledger|followups> <file> → parser records on stdout (format: see scope-parse.awk).
# Quiet and empty when the file or the parser is unusable, so callers fail open as before.
# The parser runs with LC_ALL=C (bytes). macOS's awk (BWK) in a UTF-8 locale aborts the whole run with
# "towc: multibyte conversion failure" when a regex meets a line that substr() cut in the middle of a character —
# e.g. a follow-up with no date followed by Chinese text — so that line and every line after it vanished without a
# word (2>/dev/null || true hides the abort). The grammar only needs ASCII markers and literal multibyte separators,
# which match the same bytes in either mode. Only the parser needs this: the small awk filters that read its output
# were tried on invalid UTF-8 in zh_TW/en_US/C locales and do not abort.
scope_parse() {
  [ -f "$2" ] && [ -f "$SCOPE_PARSE" ] || return 0
  LC_ALL=C awk -f "$SCOPE_PARSE" -v kind="$1" "$2" 2>/dev/null || true
}

# NOTE on SIGPIPE: the hooks run under `set -o pipefail` with an ERR trap, so a pipeline in which any stage dies
# of SIGPIPE makes the whole hook exit silently. It can happen two ways here, each with its own guard:
#  1. a reader quits early and kills the parser: absorbed by scope_parse's `|| true` (and every reader consumes all
#     of its input anyway, so either guard alone is enough — the PL5 test only fails when both are gone);
#  2. the CALLER quits early: scope-session-start.sh pipes followups_high and ledger_section into `head`, which kills
#     the reader's own awk once the output exceeds a pipe buffer. Absorbed by the `|| true` that ends each reader.
#     The grep-based readers had this for free; the first version of this parser lost it, and a 10,000-entry
#     backlog made SessionStart exit before it printed the format notice (tests HK7 and HK7b).

# ledger_field <file> <key> → value of "<key>: …" inside the leading --- frontmatter block (first one wins)
ledger_field() {
  [ -f "$1" ] || return 0
  scope_parse ledger "$1" | awk -F'\t' -v k="$2" '$1 == "F" && $2 == k && !seen { print $3; seen = 1 }' || true
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
  scope_parse ledger "$1" | awk -F'\t' -v s="$2" '$1 == "S" && $2 == s { print $4 }' || true
}

# ledger_unchecked <file> → every top-level "- [ ] …" line inside "## In scope" (empty when none)
ledger_unchecked() {
  [ -f "$1" ] || return 0
  scope_parse ledger "$1" | awk -F'\t' '$1 == "I" && $3 == 0 { print $6 }' || true
}

# ledger_frontmatter <file> → the leading --- block including both fences (empty when absent)
ledger_frontmatter() {
  [ -f "$1" ] || return 0
  scope_parse ledger "$1" | awk -F'\t' '$1 == "S" && $2 == "frontmatter" { print $4 }' || true
}

# count_lines <text> → number of non-empty lines (0 for empty input)
count_lines() {
  if [ -n "$1" ]; then printf '%s\n' "$1" | grep -c .; else echo 0; fi
}

# ledger_rounds <file> → review_rounds as a non-negative integer (0 when missing / not numeric)
ledger_rounds() {
  local v
  v=$(ledger_field "$1" review_rounds)
  case "$v" in
    '' | *[!0-9]*) echo 0 ;;
    *)
      # "08" is octal in bash arithmetic ("value too great for base"): hand back a canonical decimal. Very long digit
      # strings would overflow the arithmetic that follows, so they count as 0.
      v=${v#"${v%%[!0]*}"}
      case "${#v}" in 0) echo 0 ;; [1-9] | 1[0-5]) echo "$v" ;; *) echo 0 ;; esac ;;
  esac
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
  local f="$1" n tmp lock rc first
  [ -f "$f" ] || return 1
  [ -L "$f" ] && return 1
  [ -L "$(dirname "$f")" ] && return 1
  lock="$f.lock"
  lock_take "$lock" || return 1
  n=$(( $(ledger_rounds "$f") + 1 ))
  tmp="$f.tmp.$$"
  rc=1
  # A UTF-8 BOM before the opening fence (Windows editors add one) must not make the file look frontmatter-less:
  # the synthesised block that follows would hide the real one, and `mode` would silently fall back to converge.
  # The rewrite below drops the BOM.
  first=$(head -1 "$f" 2>/dev/null); first=${first#$'\357\273\277'}; first=${first%$'\r'}   # BOM and CR before the fence
  if [ "$first" = "---" ]; then
    # LC_ALL=C: the CR-stripping regex below aborts BSD awk in a UTF-8 locale on a line holding invalid UTF-8 (the
    # round would silently not advance). An earlier version of this rewrite had no regex and did not need it.
    LC_ALL=C awk -v n="$n" '
      NR == 1 && index($0, "\357\273\277") == 1 { $0 = substr($0, length("\357\273\277") + 1) }
      NR == 1 { crlf = ($0 ~ /\r$/) ? "\r" : "" }      # a CRLF file keeps its line endings, inserted lines included
      { l = $0; sub(/\r$/, "", l) }                    # fence and key comparisons ignore the CR
      NR == 1 && l == "---" { fm = 1; print; next }
      fm && !done && l == "---" { print "review_rounds: " n crlf; done = 1; fm = 0; print; next }
      fm && !done && index(l, "review_rounds:") == 1 { print "review_rounds: " n crlf; done = 1; next }
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

# followups_open <file> → every open follow-up (entries the parser recognised, unticked), one raw line each;
# followups_high <file> → the open HIGH ones. Lines the parser could not recognise are NOT here: they are
# reported by scope_problem_notice, flagged as unticked when they would have been open work.
followups_open() { [ -f "$1" ] || return 0; scope_parse followups "$1" | awk -F'\t' '$1 == "E" && $3 == 0 { print $10 }' || true; }
followups_high() { [ -f "$1" ] || return 0; scope_parse followups "$1" | awk -F'\t' '$1 == "E" && $3 == 0 && $5 == "HIGH" { print $10 }' || true; }

# scope_problem_notice <label> <file> <ledger|followups> → a fixed-vocabulary notice listing the lines that
# do not fit the grammar (line number + reason only — never the line's own text, which would replay file
# content into the model's context). Prints nothing when the file is clean.
scope_problem_notice() {
  local label="$1" file="$2" kind="$3" recs total bad warn
  recs=$(scope_parse "$kind" "$file" | awk -F'\t' '$1 == "X"')
  [ -n "$recs" ] || return 0
  total=$(printf '%s\n' "$recs" | awk 'END { print NR }')
  bad=$(printf '%s\n' "$recs" | awk -F'\t' '$3 == "bad" { n++ } END { print n + 0 }')
  warn=$(printf '%s\n' "$recs" | awk -F'\t' '$3 == "warn" { n++ } END { print n + 0 }')
  printf 'scope-ledger｜⚠ %s %s 有 %s 行格式問題（無法解析 %s 行、欄位不齊 %s 行）；只列行號與原因、不回放內容，請對照 /scope-ledger:scope 的格式修正：\n' "$label" "$file" "$total" "$bad" "$warn"
  printf '%s\n' "$recs" | awk -F'\t' 'NR <= 10 { printf "  第 %s 行：%s%s\n", $2, $5, ($3 == "bad" && $4 == 1) ? "（未勾選的待辦行，不在上方件數內）" : "" }'
  if [ "$total" -gt 10 ]; then printf '  …（其餘 %s 行同樣有問題）\n' "$((total - 10))"; fi
}

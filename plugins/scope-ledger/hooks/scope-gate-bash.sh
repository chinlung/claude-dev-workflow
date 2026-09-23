#!/bin/bash
# scope-ledger PreToolUse gate — matcher: Bash
#
# The Edit/Write gate never sees a source file written through the shell, and the harness's auto
# mode steers the model toward exactly that (`sed -i`, `perl -pi`, heredoc redirects). This hook
# finds the WRITE TARGETS of a Bash command and hands each to the same verdict as the Edit gate, so
# the first source change of a session is caught whichever tool makes it. Same single deny per
# session (shared flag), same exemptions, same fail-open stance.
#
# What counts as a write target (after heredoc bodies and single-quoted strings are dropped, so a
# sed expression or a commit message cannot trip it):
#   * the token after `>` or `>>`                      * `tee [-a] <file>`
#   * every source-looking token in a `sed -i…` / `perl -i…` / `perl -pi…` segment
#   * the last token of a `cp …` / `mv …` segment       * `git apply` / `patch` (targets unknown → treated as source)
# Reads (`cat x.php`, `grep … x.php > out.log`, anything to $TMPDIR or /tmp) never trigger it.
set -uo pipefail
allow() { exit 0; }
trap allow ERR

input=$(cat)
command -v jq >/dev/null 2>&1 || allow
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/_ledger.sh" || allow
. "$here/_gate.sh" || allow

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -n "$cmd" ] || allow
session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || allow
proj="${proj%/}"
[ -n "$cwd" ] || cwd="$proj"

# ── 1. Drop heredoc bodies, single-quoted strings, and bare double quotes ─────────────────────
stripped=$(printf '%s\n' "$cmd" | awk -v q="'" -v dq='"' '
  BEGIN { skip = 0; re = "<<-?[ \t]*[" dq q "]?[A-Za-z_][A-Za-z0-9_]*[" dq q "]?" }
  {
    if (skip) { if ($0 == delim) skip = 0; next }
    if (match($0, re)) {
      d = substr($0, RSTART, RLENGTH); sub(/<<-?[ \t]*/, "", d); gsub("[" dq q "]", "", d)
      delim = d; skip = 1; print substr($0, 1, RSTART - 1); next
    }
    print
  }' 2>/dev/null | sed -E "s/'[^']*'//g; s/\"//g" 2>/dev/null) || allow

# ── 2. Collect write targets per segment ────────────────────────────────────────────────────
targets=$(printf '%s\n' "$stripped" | tr ';|&' '\n\n\n' | while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  printf '%s\n' "$seg" | grep -oE '>>?[[:space:]]*[^[:space:]>]+' 2>/dev/null | sed -E 's/^>>?[[:space:]]*//'
  printf '%s\n' "$seg" | grep -oE '(^|[[:space:]])tee[[:space:]]+(-a[[:space:]]+)?[^[:space:]]+' 2>/dev/null | awk '{ print $NF }'
  if printf '%s' "$seg" | grep -Eq '(^|[[:space:]])(sed[[:space:]]+-[a-zA-Z]*i|perl[[:space:]]+-[a-zA-Z]*i)'; then
    printf '%s\n' "$seg" | tr ' \t' '\n\n' | grep -E "$SRC_RE" 2>/dev/null
  fi
  if printf '%s' "$seg" | grep -Eq '(^|[[:space:]])(cp|mv)[[:space:]]'; then
    printf '%s\n' "$seg" | awk '{ print $NF }'
  fi
  if printf '%s' "$seg" | grep -Eq '(^|[[:space:]])(git[[:space:]]+apply|patch)([[:space:]]|$)'; then
    echo "__PATCH__"
  fi
done) || allow
[ -n "$targets" ] || allow

# ── 3. Resolve and judge each target; the first deny wins ─────────────────────────────────────
printf '%s\n' "$targets" | while IFS= read -r t; do
  [ -n "$t" ] || continue
  t="${t%\"}"; t="${t#\"}"
  case "$t" in *TMPDIR* | /tmp/* | /private/tmp/* | /dev/*) continue ;; esac
  anyfile=""
  if [ "$t" = "__PATCH__" ]; then
    t="$proj/.scope-ledger-patch-target"; anyfile=any
  else
    case "$t" in
      /*) : ;;
      "~/"*) t="$HOME/${t#\~/}" ;;
      *) t="$cwd/$t" ;;
    esac
    t=$(printf '%s' "$t" | sed -E 's#/\./#/#g; s#//+#/#g')
  fi
  if [ "$(gate_verdict "$proj" "$t" "$session_id" "$agent_id" "$anyfile")" = deny ]; then
    if [ "$anyfile" = any ]; then shown="patch／git apply"; else shown="${t#$proj/}"; fi
    gate_deny_json "$(gate_reason "$proj" "Bash 寫入 ${shown}")"
    exit 3
  fi
done
# exit 3 from the subshell loop = a deny was printed; anything else = allow
rc=$?
exit 0

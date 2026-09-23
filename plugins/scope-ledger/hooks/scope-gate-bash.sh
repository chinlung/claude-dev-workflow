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
# Only the `<<DELIM` token and the body are removed; the rest of the command line is kept, so
# `cat <<'EOF' > src/new.ts` (redirect after the delimiter — valid bash, and the form a
# cross-vendor review found slipping through) still yields its target.
stripped=$(printf '%s\n' "$cmd" | awk -v q="'" -v dq='"' '
  BEGIN { skip = 0; re = "<<-?[ \t]*[" dq q "]?[A-Za-z_][A-Za-z0-9_]*[" dq q "]?" }
  {
    if (skip) { if ($0 == delim) skip = 0; next }
    if (match($0, re)) {
      d = substr($0, RSTART, RLENGTH); sub(/<<-?[ \t]*/, "", d); gsub("[" dq q "]", "", d)
      delim = d; skip = 1; print substr($0, 1, RSTART - 1) " " substr($0, RSTART + RLENGTH); next
    }
    print
  }' 2>/dev/null | sed -E "s/'[^']*'//g; s/\"//g" 2>/dev/null) || allow

# ── 2. Collect write targets per segment, resolved to absolute paths ─────────────────────────
# A segment is one command between ; | && || or a newline. A leading `cd <dir>` moves the base
# directory for the segments after it, so `cd src && sed -i … a.php` resolves to <cwd>/src/a.php
# (and `cd .claude && cat > x` lands in the exempt directory instead of looking like a source
# write at the project root). Targets containing an unexpanded `$…` cannot be resolved and are
# skipped; `__PATCH__` marks `patch` / `git apply` in command position, whose targets are unknown.
targets=$(printf '%s\n' "$stripped" | tr ';|&' '\n\n\n' | awk -v base="$cwd" -v home="$HOME" '
  function resolve(t,   r) {
    if (t == "") return ""
    if (t ~ /\$/) return ""
    if (t ~ /^\//) r = t
    else if (t ~ /^~\//) r = home "/" substr(t, 3)
    else r = base "/" t
    gsub(/\/\.\//, "/", r); gsub(/\/\/+/, "/", r)
    return r
  }
  function emit(t,   r) { r = resolve(t); if (r != "") print r }
  {
    seg = $0
    sub(/^[[:space:]]+/, "", seg)
    if (seg == "") next
    if (match(seg, /^cd[[:space:]]+[^[:space:]]+/)) {
      d = substr(seg, RSTART + 2, RLENGTH - 2); sub(/^[[:space:]]+/, "", d)
      nb = resolve(d); if (nb != "") base = nb
      next
    }
    # redirect targets
    s = seg
    while (match(s, />>?[[:space:]]*[^[:space:]>]+/)) {
      t = substr(s, RSTART, RLENGTH); sub(/^>>?[[:space:]]*/, "", t); emit(t)
      s = substr(s, RSTART + RLENGTH)
    }
    # tee [-a] <file>
    if (match(seg, /(^|[[:space:]])tee[[:space:]]+(-a[[:space:]]+)?[^[:space:]]+/)) {
      t = substr(seg, RSTART, RLENGTH); n = split(t, a, /[[:space:]]+/); emit(a[n])
    }
    # sed -i… / perl -i… / perl -pi…: every source-looking operand
    if (seg ~ /(^|[[:space:]])(sed[[:space:]]+-[a-zA-Z]*i|perl[[:space:]]+-[a-zA-Z]*i)/) {
      n = split(seg, a, /[[:space:]]+/)
      for (i = 1; i <= n; i++) if (a[i] ~ /\.(php|js|jsx|mjs|cjs|ts|tsx|vue|svelte|py|rb|go|rs|java|kt|kts|scala|swift|m|mm|c|cc|cpp|h|hpp|cs|sh|bash|zsh|sql|tf|hcl)$/) emit(a[i])
    }
    # cp / mv (also `git mv`): last operand
    if (seg ~ /(^|[[:space:]])(cp|mv)[[:space:]]/) { n = split(seg, a, /[[:space:]]+/); emit(a[n]) }
    # patch / git apply in COMMAND position only (`npm version patch`, `--grep patch` are not writes)
    if (seg ~ /^(git[[:space:]]+apply|patch)([[:space:]]|$)/) print "__PATCH__"
  }' 2>/dev/null) || allow
[ -n "$targets" ] || allow

# ── 3. Judge each target; the first deny wins ────────────────────────────────────────────────
# No blanket "/tmp is scratch" exemption: a target outside the project already passes in
# gate_verdict, and a project that itself lives under /tmp (CI fixtures, throwaway checkouts) must
# still be gated — an earlier `/tmp/*` skip made the whole gate a no-op there. `$TMPDIR` targets
# arrive unexpanded and are dropped by the collector.
printf '%s\n' "$targets" | while IFS= read -r t; do
  [ -n "$t" ] || continue
  case "$t" in /dev/*) continue ;; esac
  anyfile=""
  if [ "$t" = "__PATCH__" ]; then
    t="$proj/.scope-ledger-patch-target"; anyfile=any
  fi
  if [ "$(gate_verdict "$proj" "$t" "$session_id" "$agent_id" "$anyfile")" = deny ]; then
    if [ "$anyfile" = any ]; then shown="patch／git apply"; else shown="${t#$proj/}"; fi
    gate_deny_json "$(gate_reason "$proj" "Bash 寫入 ${shown}")"
    exit 3
  fi
done
# exit 3 from the subshell loop = a deny was printed; anything else = allow
exit 0

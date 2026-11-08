#!/bin/bash
# openspec-superpowers-workflow PreToolUse archive gate (matcher Bash; hooks.json narrows it with
# `if` to `openspec archive *` and `mv *`, so it does not spawn for every Bash call).
#
# Denies archiving an OpenSpec change until `reconcile-check.cjs check` has recorded a pass verdict
# and none of the files that verdict hashed changed since (`reconcile-check.cjs verify`). Both ways
# of archiving are covered: `openspec archive <name>` and the OpenSpec 1.16 /opsx:archive template,
# which syncs specs itself and then runs `mv <changes>/<name> <changes>/archive/<date-name>`
# (bulk-archive runs one mv per change; every change in the command must pass).
# On allow it leaves ${TMPDIR}/claude-openspec-archived-<session>, which skip-gate reads.
# Bypass for one command: OPENSPEC_ARCHIVE_OK=1 in the command.
# Fail-open: missing jq/perl/node, malformed input, no change name, a change dir that does not
# exist, or any unexpected error all allow — this hook must never be the reason a command fails.
# Design: docs/openspec-workflow-2-design-2026-11-09.md §4.1(b). Tests: tests/archive-gate.test.sh
set -uo pipefail
allow() { exit 0; }
trap allow ERR

input=$(cat) || allow
# Cheapest exit first: a project without openspec/ has nothing to gate (cwd is only needed when
# CLAUDE_PROJECT_DIR is unset, so this decides the same way as the proj check below).
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ ! -d "${CLAUDE_PROJECT_DIR%/}/openspec" ]; then allow; fi
command -v jq >/dev/null 2>&1 || allow
command -v perl >/dev/null 2>&1 || allow
command -v node >/dev/null 2>&1 || allow

# The command stays its own jq call: it may hold tabs and newlines, which @tsv would escape.
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || allow
[ -n "$cmd" ] || allow
case $cmd in *OPENSPEC_ARCHIVE_OK=1*) allow ;; esac
# Joined with US (0x1f), not tab: tab is IFS whitespace and would collapse an empty session_id away.
IFS=$'\x1f' read -r session_id cwd < <(printf '%s' "$input" | jq -r '[.session_id // "", .cwd // ""] | join("\u001f")' 2>/dev/null) || allow
session_id="${session_id//[^a-zA-Z0-9._-]/_}"; session_id="${session_id:-unknown}"
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || allow
proj="${proj%/}"

# Change names the command archives, one per line. A shell-word tokenizer, so quoted paths are read
# as the shell reads them and words inside quotes (a commit message that mentions
# `openspec archive`) never count; heredoc bodies are dropped. Only command position counts: the
# first word of a segment after any VAR=value prefixes, segments split on ; & | ( ) and newlines.
IFS= read -r -d '' parser <<'PERL' || true
use strict; use warnings;
my $c = $ENV{AG_CMD} // '';
my @lines = split /\n/, $c, -1; my @keep; my $delim;
for my $l (@lines) {
  if (defined $delim) { my $t = $l; $t =~ s/^\t+//; undef $delim if $t eq $delim; next; }
  push @keep, $l;
  $delim = $1 if $l =~ /<<-?\s*['"]?([A-Za-z_]\w*)['"]?/;
}
$c = join "\n", @keep;
my @segs = ([]); my $tok; my $i = 0; my $n = length $c;
sub endtok { push @{$segs[-1]}, $tok if defined $tok; undef $tok; }
while ($i < $n) {
  my $ch = substr($c, $i, 1);
  if ($ch eq "'") { my $j = index($c, "'", $i + 1); $j = $n if $j < 0; $tok .= substr($c, $i + 1, $j - $i - 1); $i = $j + 1; next; }
  if ($ch eq '"') {
    my $j = $i + 1; $tok //= '';
    while ($j < $n && substr($c, $j, 1) ne '"') { if (substr($c, $j, 1) eq "\\") { $j++; } $tok .= substr($c, $j, 1); $j++; }
    $i = $j + 1; next;
  }
  if ($ch eq "\\") { $tok .= substr($c, $i + 1, 1); $i += 2; next; }
  if ($ch =~ /[;&|()\n]/) { endtok(); push @segs, []; $i++; next; }
  if ($ch =~ /\s/) { endtok(); $i++; next; }
  $tok .= $ch; $i++;
}
endtok();
my %seen;
for my $s (@segs) {
  my @t = @$s; shift @t while @t && $t[0] =~ /^[A-Za-z_]\w*=/;
  next unless @t;
  if ($t[0] eq 'openspec' && @t > 1 && $t[1] eq 'archive') {
    my ($name) = grep { !/^-/ } @t[2 .. $#t];
    print "$name\n" if defined $name && !$seen{$name}++;
  } elsif ($t[0] eq 'mv') {
    my @args = grep { !/^-/ } @t[1 .. $#t];
    next unless @args >= 2 && $args[-1] =~ m{(^|/)changes/archive(/|$)};
    for my $src (@args[0 .. $#args - 1]) {
      (my $p = $src) =~ s{/+$}{};
      next unless $p =~ m{(^|/)changes/([^/]+)$};
      print "$2\n" unless $seen{$2}++;
    }
  }
}
PERL

names=$(AG_CMD=$cmd perl -e "$parser" 2>/dev/null) || allow
[ -n "$names" ] || allow

here=$(dirname "${BASH_SOURCE[0]}")
check_dir=$(cd "$here/../skills/openspec-superpowers-workflow/validators" 2>/dev/null && pwd) || allow
check="$check_dir/reconcile-check.cjs"
[ -f "$check" ] || allow

failures=""; verified=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  dir="$proj/openspec/changes/$name"
  [ -d "$dir" ] || continue
  # `|| rc=$?`, not a bare assignment: a non-zero exit would fire the ERR trap, which allows.
  rc=0; reason=$(node "$check" verify "$dir" 2>/dev/null) || rc=$?
  # verify answers with exit 3 (no verdict, or stale); node's own crash exit is 1, so anything but
  # 0 and 3 is the checker failing, not the change — fail-open.
  case $rc in
    0) verified=1 ;;
    3) failures+="  - ${name}: ${reason}"$'\n' ;;
  esac
done <<< "$names"

if [ -n "$failures" ]; then
  reason="⛔ openspec 歸檔閘門：下列 change 沒有有效的 Phase 6 核查結果，歸檔已擋下。
${failures}no-verdict＝還沒跑過 check，或上一次 check 沒有通過；stale:<artifact>＝check 之後該檔又被改過。
處理方式：Phase 6 開始時先跑 \`node ${check} snapshot <change 目錄>\`；reconcile 完成後跑 \`node ${check} check <change 目錄>\`，逐項處理 fail 與 warn，並在回覆中寫出 manual 項（C1、C2、C5）的判斷。check 通過、且之後沒有再改檔，才能歸檔。review-notes 最後一輪必須標 final，而且只有使用者明說 review 已收斂後才能加。
確定要略過本閘門：在命令前加 OPENSPEC_ARCHIVE_OK=1。"
  jq -cn --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi

if [ "$verified" = 1 ]; then touch "${TMPDIR:-/tmp}/claude-openspec-archived-${session_id}" 2>/dev/null || true; fi
allow

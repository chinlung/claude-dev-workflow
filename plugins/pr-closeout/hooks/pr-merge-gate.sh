#!/bin/bash
# pr-closeout PreToolUse merge gate (matchers: Bash, and the GitHub MCP merge_pull_request tool).
#
# Before a PR is merged — `gh pr merge`, `gh api …/pulls/<n>/merge`, or the MCP merge tool — this
# hook runs `pr-closeout.mjs ready` for that PR itself and lets the merge through only on exit 0.
# Anything else is denied with the exit, the gate and what ready found. It asks GitHub itself
# rather than trusting a marker file: inside and outside the sandbox $TMPDIR differs, and a marker
# the sandbox can write is one it can forge.
#
# Which PR: `gh pr merge <n|url> --repo|-R <owner/repo> [--match-head-commit <sha>]` (the sha
# becomes --expect-head), `gh api repos/<owner>/<repo>/pulls/<n>/merge`, or the MCP tool's owner,
# repo, pullNumber and sha. A merge whose repo or number cannot be read is denied: write them out.
# Only command position counts (a shell-word tokenizer; quoted text and heredoc bodies never match).
# Bypass for one command: PR_CLOSEOUT_OK=1 in it (the MCP tool has no bypass; use gh).
#
# A gate, so it fails closed: no jq, no node or no ready script denies a merge (and says how to
# bypass). Commands that are not a merge are allowed at once — the first test is a builtin `case`
# on the raw input, so ordinary Bash calls cost no subprocess.
# Design: docs/pr-closeout-skill-design-2026-11-09.md (D7). Tests: tests/pr-merge-gate.test.sh
set -uo pipefail
allow() { exit 0; }
deny() {
  local r="⛔ pr-closeout merge 閘門：$1
確定要略過：在命令前加 PR_CLOSEOUT_OK=1（只對 gh 有效；MCP 的 merge 工具請改用 gh）。"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  else
    printf '%s\n' "$r" >&2; exit 2
  fi
  exit 0
}

input=$(cat) || allow
case $input in *[Mm][Ee][Rr][Gg][Ee]*) ;; *) allow ;; esac   # any case: enablePullRequestAutoMerge
command -v jq >/dev/null 2>&1 || deny "需要 jq 才能判斷這是不是 merge。"
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || deny "讀不懂 hook 的輸入。"

targets=""   # one line per merge: <owner/repo or -> <number or -> <head sha or ->
if [ "$tool" = Bash ]; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || deny "讀不懂 hook 的輸入。"
  case $cmd in *PR_CLOSEOUT_OK=1*) allow ;; esac
  command -v perl >/dev/null 2>&1 || deny "需要 perl 才能判斷這是不是 merge。"
  # Merges in command position, one per line. Same tokenizer as openspec's archive-gate: quoted
  # words never count, heredoc bodies are dropped. A here-string (<<<) is not a heredoc: matching
  # `<<` without a "next char is not <" test means its first < opens no heredoc (the delimiter
  # pattern never matches the following <) and its last two are skipped with it.
  IFS= read -r -d '' parser <<'PERL' || true
use strict; use warnings;
my $c = $ENV{PMG_CMD} // '';
my @lines = split /\n/, $c, -1; my @keep; my $delim; my @body;
for my $l (@lines) {
  if (defined $delim) { push @body, $l; my $t = $l; $t =~ s/^\t+//; if ($t eq $delim) { undef $delim; @body = (); } next; }
  push @keep, $l;
  my $s = $l; $s =~ s/<<<//g;
  $delim = $1 if $s =~ /<<-?\s*['"]?([A-Za-z_]\w*)['"]?/;
}
push @keep, @body;   # a heredoc that never closes is not one: its lines are commands (fail closed)
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
  if ($ch =~ /[;&|()`\n]/) { endtok(); push @segs, []; $i++; next; }
  if ($ch =~ /\s/) { endtok(); $i++; next; }
  $tok .= $ch; $i++;
}
endtok();
for my $s (@segs) {
  # gh anywhere in the segment, by basename: wrappers (command, env, time, sudo, xargs…) and a full
  # path to gh still reach it; a stray `echo gh pr merge` is read as a merge too (the safe side)
  my @t = @$s; shift @t while @t && !(($t[0] =~ m{([^/]+)$})[0] eq 'gh');
  next unless @t >= 2;
  my ($repo, $num, $sha) = ('-', '-', '-');
  if ($t[1] eq 'pr' && @t > 2 && $t[2] eq 'merge') {
    my @a = @t[3 .. $#t];
    for (my $k = 0; $k < @a; $k++) {
      my $x = $a[$k];
      if ($x eq '--repo' || $x eq '-R') { $repo = $a[++$k] // '-'; next; }
      if ($x =~ /^--repo=(.+)$/) { $repo = $1; next; }
      if ($x eq '--match-head-commit') { $sha = $a[++$k] // '-'; next; }
      if ($x =~ /^--match-head-commit=(.+)$/) { $sha = $1; next; }
      if ($x =~ m{^https://github\.com/([^/]+/[^/]+)/pull/(\d+)}) { $repo = $1; $num = $2; next; }
      if ($x =~ /^\d+$/ && $num eq '-') { $num = $x; next; }
    }
    print "$repo $num $sha\n";
  } elsif ($t[1] eq 'api') {
    my $found = 0;
    for my $x (@t[2 .. $#t]) {
      if ($x =~ m{^/?repos/([^/]+/[^/]+)/pulls/(\d+)/merge/?(?:\?.*)?$}) { print "$1 $2 -\n"; $found = 1; last; }
    }
    # a merge this parser cannot pin to a PR (a GraphQL mergePullRequest, an odd endpoint): unreadable
    print "- - -\n" if !$found && grep { /mergePullRequest|AutoMerge|\/merge/i } @t[2 .. $#t];
  }
}
PERL
  targets=$(PMG_CMD=$cmd perl -e "$parser" 2>/dev/null) || deny "無法解析命令。"
  [ -n "$targets" ] || allow
elif [[ $tool == mcp__*merge_pull_request ]]; then
  targets=$(printf '%s' "$input" | jq -r '.tool_input | "\(if .owner and .repo then "\(.owner)/\(.repo)" else "-" end) \(.pullNumber // "-") \(.sha // "-")"' 2>/dev/null) \
    || deny "讀不懂 MCP merge 工具的輸入。"
else
  allow
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script=${PR_CLOSEOUT_SCRIPT:-"${CLAUDE_PLUGIN_ROOT:-$here/..}/scripts/pr-closeout.mjs"}
command -v node >/dev/null 2>&1 || deny "需要 node 才能執行 pr-closeout ready。"
[ -f "$script" ] || deny "找不到 pr-closeout 腳本：$script"

while read -r repo num sha; do
  [ -n "$repo" ] || continue
  if [ "$repo" = - ] || [ "$num" = - ]; then
    deny "看得出是 merge，但讀不出是哪個 repo 的哪個 PR。請明寫：gh pr merge <號碼> --repo <owner/repo>。"
  fi
  args=(ready "$repo" "$num")
  [ "$sha" = - ] || args+=(--expect-head "$sha")
  out=$(node "$script" "${args[@]}" 2>/dev/null); rc=$?
  [ "$rc" = 0 ] && continue
  summary=$(printf '%s' "$out" | jq -r '"gate: \(.gate // "-")\n" + ([.hits[]? | "  - \(.code)\(if .gate then " (" + .gate + ")" else "" end)：\(.detail)"] | join("\n"))' 2>/dev/null)
  deny "$repo#$num 還不能合併（pr-closeout ready exit $rc）。
${summary:-（ready 沒有輸出可讀的結果）}
先處理上面列的項目，或照 pr-closeout skill 的收尾步驟走。"
done <<< "$targets"
allow

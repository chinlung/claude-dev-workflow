#!/bin/bash
# Differential test of the gates' shell lexer against bash (tokenizer-differential.pl does the work).
# 1. Today's archive-gate and pr-merge-gate miss nothing bash runs, over the seeded grammar and over
#    random shell punctuation (--chars, three fixed seeds). For the merge gate "miss" includes reading a
#    number or repo other than the one bash merges. (A superset check against older parsers, judged by
#    bash, would add nothing: a case fails it only when bash ran something today's parser misses, which
#    this check already looks for. It stays in the harness as --superset-of --judge, to list what an
#    older parser reported that today's does not.)
# 2. The harness can fail on real past mistakes: for each tokenizer fix (#48, #51 in both gates, #55
#    in both gates) it finds a command the version before the fix misses and the fixed version catches;
#    for the lexer (W5-8) the fixed version is today's file.
#    The versions come from git history, so this needs a full clone (CI checks out with fetch-depth: 0);
#    a missing commit fails the suite instead of skipping it.
# 3. Each recorded open gap (--gap I) still produces counterexamples on its own: when one is fixed, its
#    check turns red and the item moves from @gaps into the default grammar. The three gaps recorded with
#    #57 moved there with the lexer (W5-8); gap 0 now is a line bash drops as a syntax error.
# 4. Canaries: a parser that sees nothing is reported, and one that is not a parser at all is refused.
# 5. Lexer mutants: each breaks one path of the lexer, and bash must catch it.
# 6. Bounded time on nested shapes the lexer reads two ways, with a canary that the check can fail, and
#    the step limit past which the merge gate denies.
# The harness runs are independent, so they run in parallel; results are judged in the order listed.
# Usage: bash plugins/openspec-superpowers-workflow/tests/tokenizer-differential.test.sh
# Consumers: the validate-on-plugin-edit hook and CI (.github/workflows/validate.yml lists plugins/*/tests/*.test.sh)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
H=${HARNESS:-"$SCRIPT_DIR/tokenizer-differential.pl"}   # HARNESS=<copy> to check the suite catches a broken harness
AG_PATH=plugins/openspec-superpowers-workflow/hooks/archive-gate.sh
PMG_PATH=plugins/pr-closeout/hooks/pr-merge-gate.sh
AG="$ROOT/$AG_PATH"
PMG="$ROOT/$PMG_PATH"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tokdiff-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# expect <label> <want rc> <harness args…>: starts the harness in the background; judged after `wait`
N=0; LABELS=(); WANTS=()
expect() {
  local label=$1 want=$2; shift 2
  N=$((N+1)); LABELS[$N]=$label; WANTS[$N]=$want
  ( perl "$H" "$@" > "$WORK/job-$N.out" 2>&1; echo $? > "$WORK/job-$N.rc" ) &
}

# 1. today's gates
expect "archive-gate misses nothing bash runs" 0 --kind ag --source "$AG" --n 400 --min-exercised 350
expect "pr-merge-gate misses nothing bash runs" 0 --kind pmg --source "$PMG" --n 400 --min-exercised 350
for seed in 1 2 3; do
  expect "archive-gate misses nothing bash runs, random punctuation, seed $seed" 0 --kind ag --source "$AG" --chars --seed "$seed" --n 1500 --min-exercised 100
  expect "pr-merge-gate misses nothing bash runs, random punctuation, seed $seed" 0 --kind pmg --source "$PMG" --chars --seed "$seed" --n 1500 --min-exercised 100
done
# 1b. the lexer alone: the reading loop cut down to its third pass. It must miss nothing bash runs in the
#     grammars either; its mutants (5) and the wide inputs (6) run on these copies, because the two older
#     readings would catch most of what a broken lexer misses.
readings_only() {   # <modes> <gate or parser> <copy>: 0 when the copy was made and differs from its source
  MODES=$1 perl -pe 's/^for my \$mode \(0, 1, 2\) \{$/for my \$mode ($ENV{MODES}) {/' "$2" > "$3" && ! cmp -s "$2" "$3"
}
lexer_only() { readings_only 2 "$@"; }
AGL="$WORK/ag-lexer.sh"; PMGL="$WORK/pmg-lexer.sh"
lexer_only "$AG" "$AGL" && lexer_only "$PMG" "$PMGL" || bad "lexer alone — the reading loop `for my \$mode (0, 1, 2)` is not in both gates"
expect "archive-gate's lexer alone misses nothing bash runs" 0 --kind ag --source "$AGL" --n 400 --min-exercised 350
expect "pr-merge-gate's lexer alone misses nothing bash runs" 0 --kind pmg --source "$PMGL" --n 400 --min-exercised 350

# 2. real past mistakes: <label> <kind> <path> <before> <after> (after "-": today's file)
while read -r label kind path before after; do
  have=1
  for c in "$before" "$after"; do
    [ "$c" = - ] && continue
    git -C "$ROOT" cat-file -e "$c^{commit}" 2>/dev/null || { bad "$label — commit $c is not in this clone (needs full history)"; have=0; }
  done
  [ "$have" = 1 ] || continue
  if [ "$after" = - ]; then cp "$ROOT/$path" "$WORK/$label-after.sh"; else git -C "$ROOT" show "$after:$path" > "$WORK/$label-after.sh"; fi \
    && git -C "$ROOT" show "$before:$path" > "$WORK/$label-before.sh" \
    || { bad "$label — cannot read $path at $before / $after"; continue; }
  expect "$label: the harness tells the version before the fix from the fix" 1 \
    --kind "$kind" --source "$WORK/$label-before.sh" --fixed-by "$WORK/$label-after.sh" --n 200
done <<EOF
#48-archive-gate ag $AG_PATH 3d9baa9^ 3d9baa9
#51-archive-gate ag $AG_PATH 392d732^ 392d732
#51-merge-gate pmg $PMG_PATH 392d732^ 392d732
#55-archive-gate ag $AG_PATH a86abf5 38f95d7
#55-merge-gate pmg $PMG_PATH a86abf5 38f95d7
W5-8-archive-gate ag $AG_PATH 01457c3 -
W5-8-merge-gate pmg $PMG_PATH 01457c3 -
EOF

# 2b. never less than before: on every generated command the gates report at least what they did at
#     b16fb23 (the first release with the three readings) — every line it printed, or for the merge gate
#     a line that denies the command outright. This is what keeps a mistake in the lexer from letting
#     anything through, and it holds only with the two older readings: the lexer alone fails it (they
#     catch commands on a line after one bash drops as a syntax error, which the lexer cannot tell).
#     Retiring them was tried and measured in docs/gate-lexer-design-2026-11-13.md §11.
if git -C "$ROOT" cat-file -e "b16fb23^{commit}" 2>/dev/null \
   && git -C "$ROOT" show "b16fb23:$AG_PATH" > "$WORK/base-ag.sh" && git -C "$ROOT" show "b16fb23:$PMG_PATH" > "$WORK/base-pmg.sh"; then
  for g in "" "--chars --seed 3"; do
    expect "archive-gate reports at least what it did at b16fb23 ${g:+(random punctuation)}" 0 --kind ag --source "$AG" --superset-of "$WORK/base-ag.sh" $g --n 1500
    expect "pr-merge-gate reports at least what it did at b16fb23 ${g:+(random punctuation)}" 0 --kind pmg --source "$PMG" --superset-of "$WORK/base-pmg.sh" $g --n 1500
  done
  expect "canary: archive-gate without the older readings reports less" 1 --kind ag --source "$AGL" --superset-of "$WORK/base-ag.sh" --chars --seed 3 --n 1500 --show 0
  expect "canary: pr-merge-gate without the older readings reports less" 1 --kind pmg --source "$PMGL" --superset-of "$WORK/base-pmg.sh" --chars --seed 3 --n 1500 --show 0
else
  bad "superset check — commit b16fb23 is not in this clone (needs full history)"
fi

# 3. open gaps are still open, each on its own: with several in one run, a fixed gap would hide behind another
for g in 0; do
  expect "known gap $g still found in archive-gate" 1 --kind ag --source "$AG" --gap "$g" --n 200 --show 0
  expect "known gap $g still found in pr-merge-gate" 1 --kind pmg --source "$PMG" --gap "$g" --n 200 --show 0
done

# 4. canaries
printf '%s\n' 'print "probe\n" if ($ENV{AG_CMD} // "") eq "openspec archive probe";' > "$WORK/blind.pl"
expect "canary: a parser that sees nothing is reported" 1 --kind ag --source "$WORK/blind.pl" --n 20 --show 0
printf '%s\n' 'print "";' > "$WORK/mute.pl"
expect "canary: something that is not a parser is refused" 2 --kind ag --source "$WORK/mute.pl" --n 5

# 5. lexer mutants: <label> <perl substitution on the lexer-alone copy of archive-gate>
#    The lexer region is the same bytes in both gates (shared-tokenizer.test.sh), so one copy serves.
LEX_MUTANTS=0
  while IFS=$'\t' read -r label sub; do
    [ -n "$label" ] || continue
    LEX_MUTANTS=$((LEX_MUTANTS+1))
    m="$WORK/lexmut-$label.sh"
    if ! perl -pe "$sub" "$AGL" > "$m" || cmp -s "$m" "$AGL"; then bad "lexer mutant [$label]: substitution did not apply"; continue; fi
    expect "lexer mutant [$label] is caught" 1 --kind ag --source "$m" --n 400 --show 0
  done <<'EOF'
arith-subs	s/^(\s*)if \(substr\(\$\$sr, \$i, 2\) eq .\$\(.\) \{$/$1if (0) {/
dq-subs	s/\$i = lex_cmd\(\$sr, \$i \+ 2, .\)., \$segs, \$depth \+ 1\); \$t/\$i = lex_cmd(\$sr, \$i + 2, ")", [], \$depth + 1); \$t/
bq-cmd	s/^(\s*)lex_text\(\$t, \$segs, \$depth\);$/$1lex_text(\$t, [], \$depth);/
body	s/lex_dq\(\\\$x, 0, \$segs, \$depth, 1\); \}   # an unquoted body/lex_dq(\\\$x, 0, [], \$depth, 1); }   # an unquoted body/
delim-paren	s/^\s*if \(\$end eq .\). && substr\(\$l, 0, length\(\$d\) \+ 1\).*$//
redirect	s/if \(\$ch eq .<. \|\| \$ch eq .>.\) \{/if (0) {/
redirect-target	s/\$skip = 1; \$i = \$j; next;/\$i = \$j; next;/
comment-word	s/if \(\$ch eq .#. && !defined \$tok && /if (\$ch eq "#" \&\& /
continuation	s/ unless \$e eq "\\n"; \$i \+= 2; next; \}/; \$i += 2; next; }/
param-subs	s/subs_of\(substr\(\$\$sr, \$i, \$j - \$i\), \$sq\)/subs_of("", \$sq)/
arith-bq	s/^(\s*)if \(\$x eq .`.\) \{ \$i = lex_bq\(\$sr, \$i, \$segs, \$depth, 1\); next; \}$/$1/
arith-paren	s/^\s*lex_text\(substr\(\$\$sr, \$from, \$i \+ 1 - \$from\), \$segs, \$depth\);$//
unclosed-quote	s/^sub lex_rest \{ .*$/sub lex_rest { }/
arith-cmd	s/^(\s*)if \(!defined \$tok && substr\(\$\$sr, \$i, 2\) eq .\(\(.\) \{/$1if (0) {/
empty-word	s/grep \{ \$_ ne .. \} map \{ lex_kw\(\$_\) \} \@\$s/map { lex_kw(\$_) } \@\$s/
EOF
# Not here: a rule whose mistake only makes the lexer read more (the body of an open heredoc, `<<\` and
# a newline, `$[ … ]`). What such a mistake loses, reading the text after an unclosed construct as
# commands finds again, so bash cannot catch it; a case that must be let through could (follow-up).
LEX_MUTANTS_WANT=15
[ "$LEX_MUTANTS" = "$LEX_MUTANTS_WANT" ] || bad "ran $LEX_MUTANTS lexer mutants, expected $LEX_MUTANTS_WANT"
# the mark a substitution leaves in a word: without it the merge gate reads `gh pr merge 3$(echo 0)` as
# PR 3 and checks it while bash merges 30. Judged on the merge gate (archive-gate takes it as empty).
m="$WORK/lexmut-value-mark.sh"
perl -pe 's/\$tok \.= "\\x0[12]";/\$tok .= q();/g; s/\$t \.= "\\x01"; //g' "$PMGL" > "$m"
if cmp -s "$m" "$PMGL"; then bad "lexer mutant [value-mark]: substitution did not apply"
else expect "lexer mutant [value-mark] is caught (merge gate)" 1 --kind pmg --source "$m" --n 400 --show 0; fi

wait   # the clocked checks below run alone: the harness jobs above would share the CPU with them
# 6. bounded time: the lexer reads some texts a second way, and those readings nest. Without reading
#    each text only once, 20 nested unclosed `"$(` or 20 nested `$((` took seconds and 40 took hours;
#    with the step limit they now spend it instead, and an ordinary command goes unread.
#    Run the way the hook runs the parser, under a clock: 142 is the alarm.
parser_of() { perl -ne 'if (!$in) { $in = 1 if /<<\x27PERL\x27/; next } last if /^\s*PERL\s*$/; print' "$1"; }
within() {   # <seconds> <env var> <command> <parser file>: the parser's output; exit 142 past the time
  env "$2=$3" perl -e 'alarm shift; my $p = do { local $/; open my $f, "<", shift or die; <$f> }; exec $^X, "-e", $p' "$1" "$4"
}
UNCLOSED=$(perl -e 'print q{"$(} x 40')
ARITH_AG=$(perl -e 'print "echo " . (q{$(( } x 40) . "1" . (" ))" x 40) . "; openspec archive foo"')
ARITH_PMG=$(perl -e 'print "echo " . (q{$(( } x 40) . "1" . (" ))" x 40) . "; gh pr merge 3 --repo o/r"')
parser_of "$AG" > "$WORK/ag-parser.pl"; parser_of "$PMG" > "$WORK/pmg-parser.pl"
parser_of "$AGL" > "$WORK/ag-lexer.pl"; parser_of "$PMGL" > "$WORK/pmg-lexer.pl"
timed() {   # <label> <want rc> <want text in the output, or ""> <within args…> (RUN=inproc: <inproc args…>)
  local label=$1 want=$2 text=$3 out rc; shift 3
  out=$(${RUN:-within} "$@" 2>/dev/null); rc=$?
  if [ "$rc" = "$want" ] && { [ -z "$text" ] || [[ $out == *"$text"* ]]; }; then ok "$label"; else bad "$label — exit $rc, output [${out:0:80}]"; fi
}
timed "archive-gate: 40 nested unclosed \"\$( in under 5 s" 0 "" 5 AG_CMD "$UNCLOSED" "$WORK/ag-parser.pl"
timed "archive-gate: 40 nested \$(( in under 5 s, the archive after them seen" 0 foo 5 AG_CMD "$ARITH_AG" "$WORK/ag-parser.pl"
timed "pr-merge-gate: 40 nested unclosed \"\$( in under 5 s" 0 "" 5 PMG_CMD "$UNCLOSED" "$WORK/pmg-parser.pl"
timed "pr-merge-gate: 40 nested \$(( in under 5 s, the merge after them seen" 0 "o/r 3 -" 5 PMG_CMD "$ARITH_PMG" "$WORK/pmg-parser.pl"
# Wide inputs: every loop of the lexer counts against one step limit and $(( nests no deeper than 50, so
# the lexer reads no command for longer than the hook's timeout (archive-gate 10 s, the merge gate 30 s).
# The unclosed ${ go to the lexer alone here; the two older readings are timed on their own in 7.
WIDE_ARITH=$(perl -e 'print "echo ", q{$((} x 15000, "1", q{))} x 15000')
WIDE_PARAM=$(perl -e 'print "gh pr merge 3 --repo o/r; echo ", q[${a:-] x 8000')
DEEP60=$(perl -e 'print "echo ", q{$((} x 60, "1", q{))} x 60, "; gh pr merge 3 --repo o/r"')
timed "archive-gate: 15000 nested \$(( in under 5 s" 0 foo 5 AG_CMD "$WIDE_ARITH; openspec archive foo" "$WORK/ag-parser.pl"
timed "pr-merge-gate: 15000 nested \$(( in under 5 s, unreadable" 0 "- - -" 5 PMG_CMD "$WIDE_ARITH; gh pr merge 3 --repo o/r" "$WORK/pmg-parser.pl"
  timed "archive-gate's lexer: 8000 unclosed \${ in under 5 s" 0 "" 5 AG_CMD "$WIDE_PARAM" "$WORK/ag-lexer.pl"
  timed "pr-merge-gate's lexer: 8000 unclosed \${ in under 5 s, unreadable" 0 "- - -" 5 PMG_CMD "$WIDE_PARAM" "$WORK/pmg-lexer.pl"
  timed "pr-merge-gate's lexer: 60 nested \$(( are deeper than it reads" 0 "- - -" 5 PMG_CMD "$DEEP60" "$WORK/pmg-lexer.pl"
  # one budget for the whole command: 20 bash -c strings of 1200 unclosed ${ each (about 0.4 s apiece
  # with a budget of their own). 120 KB: Linux refuses an environment variable over 128 KB (exit 126).
  MANY_C=$(perl -e 'my $x = q[${a:-] x 1200; print "gh pr merge 3 --repo o/r", map({ "; bash -c \x27$x\x27" } 1 .. 20)')
  timed "pr-merge-gate's lexer: 20 bash -c strings share one step limit, under 5 s" 0 "- - -" 5 PMG_CMD "$MANY_C" "$WORK/pmg-lexer.pl"
  perl -pe 's/^(\s*my \(\$s\) = \@_; my \@segs; %LEX_READ = \(\);)$/$1 \$LEX_STEPS = 0;/' "$WORK/pmg-lexer.pl" > "$WORK/c-reset.pl"
  if cmp -s "$WORK/pmg-lexer.pl" "$WORK/c-reset.pl"; then bad "canary [reset]: lex_segs is not where this test finds it"
  else timed "canary [reset]: a step limit per bash -c string runs out of time" 142 "" 5 PMG_CMD "$MANY_C" "$WORK/c-reset.pl"; fi
  # canaries, each on what it removes: without reading each text once, 40 nested $(( spend the whole
  # limit and the merge after them goes unread; without the counting in param_end, the unclosed ${ run
  # out of time; without the depth check and the counting in lex_arith and lex_text, so do the $((
  perl -ne 'print unless /^\s*return if \$LEX_READ\{/' "$WORK/pmg-lexer.pl" > "$WORK/c-memo.pl"
  perl -pe 's/ ?lex_tick\([^;]*\);// if /^sub param_end/ .. /^\}/' "$WORK/pmg-lexer.pl" > "$WORK/c-param.pl"
  perl -pe 's/ ?lex_tick\([^;]*\);// if /^sub lex_(arith|text) / .. /^\}/; $_ = "" if /^\s*if \(\$depth > 50\) \{ \$LEX_UNREAD = 1; return \$n; \}$/ && $in_arith; $in_arith = /^sub lex_arith / ? 1 : /^\}/ ? 0 : $in_arith' "$WORK/pmg-lexer.pl" > "$WORK/c-arith.pl"
  for c in memo param arith; do cmp -s "$WORK/pmg-lexer.pl" "$WORK/c-$c.pl" && bad "canary [$c]: what it removes is not in the lexer"; done
  out=$(within 5 PMG_CMD "$ARITH_PMG" "$WORK/c-memo.pl" 2>/dev/null)
  if [[ $out == *"- - -"* && $out != *"o/r 3 -"* ]]; then ok "canary [memo]: reading each text every time spends the limit"; else bad "canary [memo] — output [${out:0:80}]"; fi
  timed "canary [param]: without counting in param_end the unclosed \${ run out of time" 142 "" 3 PMG_CMD "$WIDE_PARAM" "$WORK/c-param.pl"
  timed "canary [arith]: without the depth check and counting the nested \$(( run out of time" 142 "" 3 PMG_CMD "$WIDE_ARITH" "$WORK/c-arith.pl"
# the step limit: past it the rest is unread, and the merge gate reports a merge it cannot read (deny);
# the limit is lowered in a copy so that a short command reaches it
LONG=$(perl -e 'print "echo " . ("x " x 3000) . "; gh pr merge 3 --repo o/r"')
perl -pe 's/\$LEX_MAX, %LEX_READ\) = \(0, 0, 3_000_000\)/\$LEX_MAX, %LEX_READ) = (0, 0, 2000)/' "$WORK/pmg-parser.pl" > "$WORK/pmg-lowmax.pl"
if cmp -s "$WORK/pmg-parser.pl" "$WORK/pmg-lowmax.pl"; then bad "step limit — the limit is not where this test lowers it"
else
  timed "pr-merge-gate past the step limit: unreadable" 0 "- - -" 5 PMG_CMD "$LONG" "$WORK/pmg-lowmax.pl"
  out=$(within 5 PMG_CMD "$LONG" "$WORK/pmg-parser.pl" 2>/dev/null)
  if [[ $out == *"o/r 3 -"* && $out != *"- - -"* ]]; then ok "pr-merge-gate under the step limit: the merge, nothing unread"; else bad "pr-merge-gate under the step limit — output [${out:0:80}]"; fi
fi

# 7. the two older readings in linear time. Each was quadratic somewhere: a ${ that never closes was
#    scanned to the end of the text once per ${, the heredoc pass copied the rest of the line at each
#    character, and a heredoc that never closes collected every later line before they were scanned
#    again, once per heredoc (8000 ${a:- took 17 s, 20000 such heredocs over a minute). Timed on a copy
#    with only those two readings, the command read from a file inside one perl (Linux refuses an
#    environment variable over 128 KB), by CPU time; each canary puts one quadratic loop back.
inproc() {   # <seconds> <parser file> <env var> <command file> [<cpu file>]: the parser's output; exit 142 past the time
  perl -e 'my ($s, $pf, $var, $cf, $cpu) = @ARGV; alarm $s;
    my $p = do { local $/; open my $f, "<", $pf or die; <$f> };
    $ENV{$var} = do { local $/; open my $f, "<", $cf or die; <$f> };
    my $t = (times)[0]; eval $p; die $@ if $@;
    if ($cpu) { open my $o, ">", $cpu or die; printf $o "%.4f\n", (times)[0] - $t; }' "$@"
}
fast() { RUN=inproc timed "$@"; }   # <label> <want rc> <want text, or ""> <inproc args…>
linear() {   # <label> <want 0 linear | 1 not> <parser> <env var> <file n> <file 4n>: 4n under 10 s and under 6× the time of n
  # (measured on 150,000 → 600,000 characters: the linear parsers take 4.0×, the substr canary 12.7×; at
  # 75,000 → 300,000 a slower CI machine measured the canary at 7.5× and a threshold of 8 let it through)
  local label=$1 want=$2 p=$3 v=$4 got t1 t4
  inproc 10 "$p" "$v" "$5" "$WORK/cpu1" > /dev/null 2>&1 && inproc 10 "$p" "$v" "$6" "$WORK/cpu4" > /dev/null 2>&1 \
    && t1=$(cat "$WORK/cpu1") && t4=$(cat "$WORK/cpu4") && perl -e 'exit !($ARGV[1] < 6 * ($ARGV[0] > 0.05 ? $ARGV[0] : 0.05))' "$t1" "$t4"
  got=$?; [ "$got" = 0 ] || got=1
  if [ "$got" = "$want" ]; then ok "$label"; else bad "$label — n ${t1:-?} s, 4n ${t4:-?} s"; fi
  rm -f "$WORK/cpu1" "$WORK/cpu4"
}
for g in ag pmg; do readings_only "0, 1" "$WORK/$g-parser.pl" "$WORK/$g-older.pl" || bad "$g: the readings loop is not where this test narrows it"; done
perl -e 'print "openspec archive foo; echo ", q[${a:-] x 8000' > "$WORK/ag-brace"
printf '%s' "$WIDE_PARAM" > "$WORK/pmg-brace"
perl -e 'print "openspec archive foo\n", map { "echo <<EOF$_\n" } 1 .. 20000' > "$WORK/ag-here"
perl -e 'print "gh pr merge 3 --repo o/r\n", map { "echo <<EOF$_\n" } 1 .. 20000' > "$WORK/pmg-here"
for n in 150000 600000; do
  perl -e 'print "openspec archive foo; echo ", "x" x $ARGV[0]' $n > "$WORK/ag-long-$n"
  perl -e 'print "gh pr merge 3 --repo o/r; echo ", "x" x $ARGV[0]' $n > "$WORK/pmg-long-$n"
done
fast   "archive-gate's older readings: 8000 unclosed \${ in under 3 s" 0 foo 3 "$WORK/ag-older.pl" AG_CMD "$WORK/ag-brace"
fast   "pr-merge-gate's older readings: 8000 unclosed \${ in under 3 s" 0 "o/r 3 -" 3 "$WORK/pmg-older.pl" PMG_CMD "$WORK/pmg-brace"
fast   "archive-gate's older readings: 20000 heredocs that never close in under 3 s" 0 foo 3 "$WORK/ag-older.pl" AG_CMD "$WORK/ag-here"
fast   "pr-merge-gate's older readings: 20000 heredocs that never close in under 3 s" 0 "o/r 3 -" 3 "$WORK/pmg-older.pl" PMG_CMD "$WORK/pmg-here"
linear "archive-gate's older readings: a line 4× as long takes under 6× the time" 0 "$WORK/ag-older.pl" AG_CMD "$WORK/ag-long-150000" "$WORK/ag-long-600000"
linear "pr-merge-gate's older readings: a line 4× as long takes under 6× the time" 0 "$WORK/pmg-older.pl" PMG_CMD "$WORK/pmg-long-150000" "$WORK/pmg-long-600000"
perl -pe 's/if \(!exists \$brace\{\$i\}\) \{/if (1) {/' "$WORK/pmg-older.pl" > "$WORK/q-brace.pl"
perl -pe 's{!\$left\{\$hd\[0\]\[0\]\}}{!grep { s/^\\t+//r eq \$hd[0][0] } \@todo}' "$WORK/pmg-older.pl" > "$WORK/q-here.pl"
perl -ne 'next if /^\s*pos\(\$l\) = \$i;/; s/\$l =~ \/\\G<</substr(\$l, \$i) =~ \/^<</; print' "$WORK/pmg-older.pl" > "$WORK/q-pos.pl"
for c in brace here pos; do cmp -s "$WORK/pmg-older.pl" "$WORK/q-$c.pl" && bad "canary [quadratic $c]: what it puts back is not in the parser"; done
fast   "canary [quadratic brace]: scanning each \${ again runs out of time" 142 "" 3 "$WORK/q-brace.pl" PMG_CMD "$WORK/pmg-brace"
fast   "canary [quadratic here]: looking through the lines left for each heredoc runs out of time" 142 "" 3 "$WORK/q-here.pl" PMG_CMD "$WORK/pmg-here"
linear "canary [quadratic pos]: copying the rest of the line at each character is not linear" 1 "$WORK/q-pos.pl" PMG_CMD "$WORK/pmg-long-150000" "$WORK/pmg-long-600000"

wait
for i in $(seq 1 "$N"); do
  head -4 "$WORK/job-$i.out" 2>/dev/null | sed 's/^/    /'
  rc=$(cat "$WORK/job-$i.rc" 2>/dev/null || echo none)
  if [ "$rc" = "${WANTS[$i]}" ]; then ok "${LABELS[$i]}"; else bad "${LABELS[$i]} — harness exit $rc, wanted ${WANTS[$i]}"; fi
done

# ---- summary ----
# written out, not counted as the checks run: a check that is skipped must lower the count
MIN=68
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then bad "ran $((PASS + FAIL)) checks, expected at least $MIN"; fi
echo "tokenizer-differential: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

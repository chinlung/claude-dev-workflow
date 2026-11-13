#!/bin/bash
# Differential test of the gates' shell tokenizer against bash (tokenizer-differential.pl does the work).
# 1. Today's archive-gate and pr-merge-gate miss nothing bash runs, over the seeded grammar and over
#    random shell punctuation (--chars, one fixed seed).
#    1b. The lexer alone (a copy of each gate with only its third reading) misses nothing either: the
#    step that retires the two older readings (docs/gate-lexer-design-2026-11-13.md §4) starts from it.
# 2. The harness can fail on real past mistakes: for each tokenizer fix (#48, #51 in both gates, #55
#    in both gates) it finds a command the version before the fix misses and the fixed version catches;
#    for the lexer (W5-8) the fixed version is today's file.
#    The versions come from git history, so this needs a full clone (CI checks out with fetch-depth: 0);
#    a missing commit fails the suite instead of skipping it.
# 2b. Today's gates print every line the gates at b81dcdc and at 01457c3 print.
# 3. Each recorded open gap (--gap I) still produces counterexamples on its own: when one is fixed, its
#    check turns red and the item moves from @gaps into the default grammar. The three gaps recorded with
#    #57 moved there with the lexer (W5-8); gap 0 now is a line bash drops as a syntax error.
# 4. Canaries: a parser that sees nothing is reported, and one that is not a parser at all is refused.
# 5. Lexer mutants: each breaks one path of the lexer in the lexer-alone copy, and bash must catch it.
#    The gate suites' own mutants run on the two older readings, which the lexer would otherwise cover.
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
expect "archive-gate misses nothing bash runs, random punctuation" 0 --kind ag --source "$AG" --chars --seed 1 --n 1500 --min-exercised 100
expect "pr-merge-gate misses nothing bash runs, random punctuation" 0 --kind pmg --source "$PMG" --chars --seed 1 --n 1500 --min-exercised 100

# 1b. the lexer alone: the reading loop cut down to its third pass
lexer_only() {   # <gate> <copy>: 0 when the copy was made and differs from the gate
  perl -pe 's/^for my \$mode \(0, 1, 2\) \{$/for my \$mode (2) {/' "$1" > "$2" && ! cmp -s "$1" "$2"
}
if lexer_only "$AG" "$WORK/ag-lexer.sh" && lexer_only "$PMG" "$WORK/pmg-lexer.sh"; then
  expect "archive-gate's lexer alone misses nothing bash runs" 0 --kind ag --source "$WORK/ag-lexer.sh" --n 400 --min-exercised 350
  expect "pr-merge-gate's lexer alone misses nothing bash runs" 0 --kind pmg --source "$WORK/pmg-lexer.sh" --n 400 --min-exercised 350
  expect "archive-gate's lexer alone, random punctuation" 0 --kind ag --source "$WORK/ag-lexer.sh" --chars --seed 2 --n 1500 --min-exercised 100
  expect "pr-merge-gate's lexer alone, random punctuation" 0 --kind pmg --source "$WORK/pmg-lexer.sh" --chars --seed 2 --n 1500 --min-exercised 100
else
  bad "lexer alone — the reading loop \`for my \$mode (0, 1, 2)\` is not in both gates"
fi

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

# 2b. never less than before: on every generated command, today's parsers print every line the parsers
#     at b81dcdc (before the comment rules) and at 01457c3 (before the lexer) print. The first commit of
#     the comment rules failed this on about one case in five. It does not by itself prove the older
#     readings are there: the `plain-reading` mutant in the two gate suites is what shows the second
#     reading is used.
for BASE in b81dcdc 01457c3; do
  if git -C "$ROOT" cat-file -e "$BASE^{commit}" 2>/dev/null \
     && git -C "$ROOT" show "$BASE:$AG_PATH" > "$WORK/base-ag-$BASE.sh" && git -C "$ROOT" show "$BASE:$PMG_PATH" > "$WORK/base-pmg-$BASE.sh"; then
    expect "archive-gate sees everything it saw at $BASE" 0 --kind ag --source "$AG" --superset-of "$WORK/base-ag-$BASE.sh" --n 400
    expect "pr-merge-gate sees everything it saw at $BASE" 0 --kind pmg --source "$PMG" --superset-of "$WORK/base-pmg-$BASE.sh" --n 400
  else
    bad "superset check — commit $BASE is not in this clone (needs full history)"
  fi
done

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
if [ -f "$WORK/ag-lexer.sh" ]; then
  while IFS=$'\t' read -r label sub; do
    [ -n "$label" ] || continue
    LEX_MUTANTS=$((LEX_MUTANTS+1))
    m="$WORK/lexmut-$label.sh"
    if ! perl -pe "$sub" "$WORK/ag-lexer.sh" > "$m" || cmp -s "$m" "$WORK/ag-lexer.sh"; then bad "lexer mutant [$label]: substitution did not apply"; continue; fi
    expect "lexer mutant [$label] is caught" 1 --kind ag --source "$m" --n 400 --show 0
  done <<'EOF'
arith-subs	s/^(\s*)if \(substr\(\$\$sr, \$i, 2\) eq .\$\(.\) \{$/$1if (0) {/
dq-subs	s/\$i = lex_cmd\(\$sr, \$i \+ 2, .\)., \$segs, \$depth \+ 1\); \$sub = 1; next; \}/\$i = lex_cmd(\$sr, \$i + 2, ")", [], \$depth + 1); \$sub = 1; next; }/
bq-cmd	s/^(\s*)lex_text\(\$t, \$segs, \$depth\);$/$1lex_text(\$t, [], \$depth);/
body	s/lex_dq\(\\\$x, 0, \$segs, \$depth, 1\); \}   # an unquoted body/lex_dq(\\\$x, 0, [], \$depth, 1); }   # an unquoted body/
open-body	s/unless \(\$quoted\) \{ my \$x = substr\(\$\$sr, \$i\); lex_dq\(\\\$x, 0, \$segs/unless (\$quoted) { my \$x = substr(\$\$sr, \$i); lex_dq(\\\$x, 0, []/
delim-paren	s/^\s*if \(\$end eq .\). && substr\(\$l, 0, length\(\$d\) \+ 1\).*$//
delim-cont	s/if \(substr\(\$\$sr, \$j \+ 1, 1\) ne "\\n"\) \{/if (1) {/
redirect	s/if \(\$ch eq .<. \|\| \$ch eq .>.\) \{/if (0) {/
redirect-target	s/\$skip = 1; \$i = \$j; next;/\$i = \$j; next;/
comment-word	s/if \(\$ch eq .#. && !defined \$tok && /if (\$ch eq "#" \&\& /
continuation	s/ unless \$e eq "\\n"; \$i \+= 2; next; \}/; \$i += 2; next; }/
param-subs	s/subs_of\(substr\(\$\$sr, \$i, \$j - \$i\), \$sq\)/subs_of("", \$sq)/
arith-bq	s/^(\s*)if \(\$x eq .`.\) \{ \$i = lex_bq\(\$sr, \$i, \$segs, \$depth, 1\); next; \}$/$1/
arith-paren	s/^\s*lex_text\(substr\(\$\$sr, \$from, \$i \+ 1 - \$from\), \$segs, \$depth\);$//
unclosed-quote	s/^sub lex_rest \{ .*$/sub lex_rest { }/
old-arith	s/ \|\| substr\(\$\$sr, \$i, 2\) eq .\$\[.\) \{ my \$j = lex_arith\(\$sr, \$i, \$segs, \$depth\); if \(defined \$j\) \{ \$i = \$j; \$tok/) { my \$j = lex_arith(\$sr, \$i, \$segs, \$depth); if (defined \$j) { \$i = \$j; \$tok/
arith-cmd	s/^(\s*)if \(!defined \$tok && substr\(\$\$sr, \$i, 2\) eq .\(\(.\) \{/$1if (0) {/
empty-word	s/\(\$tok ne .. \|\| !\$sub\)/(1)/
EOF
fi
LEX_MUTANTS_WANT=18
[ "$LEX_MUTANTS" = "$LEX_MUTANTS_WANT" ] || bad "ran $LEX_MUTANTS lexer mutants, expected $LEX_MUTANTS_WANT"

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
timed() {   # <label> <want rc> <want text in the output, or ""> <within args…>
  local label=$1 want=$2 text=$3 out rc; shift 3
  out=$(within "$@" 2>/dev/null); rc=$?
  if [ "$rc" = "$want" ] && { [ -z "$text" ] || [[ $out == *"$text"* ]]; }; then ok "$label"; else bad "$label — exit $rc, output [${out:0:80}]"; fi
}
timed "archive-gate: 40 nested unclosed \"\$( in under 5 s" 0 "" 5 AG_CMD "$UNCLOSED" "$WORK/ag-parser.pl"
timed "archive-gate: 40 nested \$(( in under 5 s, the archive after them seen" 0 foo 5 AG_CMD "$ARITH_AG" "$WORK/ag-parser.pl"
timed "pr-merge-gate: 40 nested unclosed \"\$( in under 5 s" 0 "" 5 PMG_CMD "$UNCLOSED" "$WORK/pmg-parser.pl"
timed "pr-merge-gate: 40 nested \$(( in under 5 s, the merge after them seen" 0 "o/r 3 -" 5 PMG_CMD "$ARITH_PMG" "$WORK/pmg-parser.pl"
# Wide inputs: every loop of the lexer counts against one step limit and $(( nests no deeper than 50, so
# no command reads for longer than the hook's timeout (archive-gate 10 s, the merge gate 30 s). The
# unclosed ${ go to the lexer alone: the two older readings are themselves quadratic on them (follow-up).
WIDE_ARITH=$(perl -e 'print "echo ", q{$((} x 15000, "1", q{))} x 15000')
WIDE_PARAM=$(perl -e 'print "gh pr merge 3 --repo o/r; echo ", q[${a:-] x 8000')
DEEP60=$(perl -e 'print "echo ", q{$((} x 60, "1", q{))} x 60, "; gh pr merge 3 --repo o/r"')
timed "archive-gate: 15000 nested \$(( in under 5 s" 0 foo 5 AG_CMD "$WIDE_ARITH; openspec archive foo" "$WORK/ag-parser.pl"
timed "pr-merge-gate: 15000 nested \$(( in under 5 s, unreadable" 0 "- - -" 5 PMG_CMD "$WIDE_ARITH; gh pr merge 3 --repo o/r" "$WORK/pmg-parser.pl"
if [ -f "$WORK/ag-lexer.sh" ] && [ -f "$WORK/pmg-lexer.sh" ]; then
  parser_of "$WORK/ag-lexer.sh" > "$WORK/ag-lexer.pl"; parser_of "$WORK/pmg-lexer.sh" > "$WORK/pmg-lexer.pl"
  timed "archive-gate's lexer: 8000 unclosed \${ in under 5 s" 0 "" 5 AG_CMD "$WIDE_PARAM" "$WORK/ag-lexer.pl"
  timed "pr-merge-gate's lexer: 8000 unclosed \${ in under 5 s, unreadable" 0 "- - -" 5 PMG_CMD "$WIDE_PARAM" "$WORK/pmg-lexer.pl"
  timed "pr-merge-gate's lexer: 60 nested \$(( are deeper than it reads" 0 "- - -" 5 PMG_CMD "$DEEP60" "$WORK/pmg-lexer.pl"
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
else
  bad "wide inputs — the lexer-alone copies were not made (section 1b)"
fi
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

wait
for i in $(seq 1 "$N"); do
  head -4 "$WORK/job-$i.out" 2>/dev/null | sed 's/^/    /'
  rc=$(cat "$WORK/job-$i.rc" 2>/dev/null || echo none)
  if [ "$rc" = "${WANTS[$i]}" ]; then ok "${LABELS[$i]}"; else bad "${LABELS[$i]} — harness exit $rc, wanted ${WANTS[$i]}"; fi
done

# ---- summary ----
# written out, not counted as the checks run: a check that is skipped must lower the count
MIN=55
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then bad "ran $((PASS + FAIL)) checks, expected at least $MIN"; fi
echo "tokenizer-differential: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

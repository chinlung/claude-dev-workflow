#!/bin/bash
# Differential test of the gates' shell tokenizer against bash (tokenizer-differential.pl does the work).
# 1. Today's archive-gate and pr-merge-gate miss nothing bash runs, over the seeded grammar.
# 2. The harness can fail on real past mistakes: for each tokenizer fix (#48, #51 in both gates, #55
#    in both gates) it finds a command the version before the fix misses and the fixed version catches.
#    The versions come from git history, so this needs a full clone (CI checks out with fetch-depth: 0);
#    a missing commit fails the suite instead of skipping it.
# 3. Each recorded open gap (--gap I) still produces counterexamples on its own: when one is fixed, its
#    check turns red and the item moves from @gaps into the default grammar.
# 4. Canaries: a parser that sees nothing is reported, and one that is not a parser at all is refused.
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

# 2. real past mistakes: <label> <kind> <path> <before> <after>
while read -r label kind path before after; do
  have=1
  for c in "$before" "$after"; do
    git -C "$ROOT" cat-file -e "$c^{commit}" 2>/dev/null || { bad "$label — commit $c is not in this clone (needs full history)"; have=0; }
  done
  [ "$have" = 1 ] || continue
  git -C "$ROOT" show "$before:$path" > "$WORK/$label-before.sh" && git -C "$ROOT" show "$after:$path" > "$WORK/$label-after.sh" \
    || { bad "$label — cannot read $path at $before / $after"; continue; }
  expect "$label: the harness tells the version before the fix from the fix" 1 \
    --kind "$kind" --source "$WORK/$label-before.sh" --fixed-by "$WORK/$label-after.sh" --n 200
done <<EOF
#48-archive-gate ag $AG_PATH 3d9baa9^ 3d9baa9
#51-archive-gate ag $AG_PATH 392d732^ 392d732
#51-merge-gate pmg $PMG_PATH 392d732^ 392d732
#55-archive-gate ag $AG_PATH a86abf5 38f95d7
#55-merge-gate pmg $PMG_PATH a86abf5 38f95d7
EOF

# 2b. never less than before the comment rules: on every generated command (the gaps included), today's
#     parsers print every line the parsers at b81dcdc print. This is what reading each command twice buys.
BASE=b81dcdc
if git -C "$ROOT" cat-file -e "$BASE^{commit}" 2>/dev/null \
   && git -C "$ROOT" show "$BASE:$AG_PATH" > "$WORK/base-ag.sh" && git -C "$ROOT" show "$BASE:$PMG_PATH" > "$WORK/base-pmg.sh"; then
  expect "archive-gate sees everything it saw at $BASE" 0 --kind ag --source "$AG" --superset-of "$WORK/base-ag.sh" --known-gaps --n 400
  expect "pr-merge-gate sees everything it saw at $BASE" 0 --kind pmg --source "$PMG" --superset-of "$WORK/base-pmg.sh" --known-gaps --n 400
else
  bad "superset check — commit $BASE is not in this clone (needs full history)"
fi

# 3. open gaps are still open, each on its own: with both in one run, a fixed gap would hide behind the other
for g in 0 1 2; do
  expect "known gap $g still found in archive-gate" 1 --kind ag --source "$AG" --gap "$g" --n 200 --show 0
  expect "known gap $g still found in pr-merge-gate" 1 --kind pmg --source "$PMG" --gap "$g" --n 200 --show 0
done

# 4. canaries
printf '%s\n' 'print "probe\n" if ($ENV{AG_CMD} // "") eq "openspec archive probe";' > "$WORK/blind.pl"
expect "canary: a parser that sees nothing is reported" 1 --kind ag --source "$WORK/blind.pl" --n 20 --show 0
printf '%s\n' 'print "";' > "$WORK/mute.pl"
expect "canary: something that is not a parser is refused" 2 --kind ag --source "$WORK/mute.pl" --n 5

wait
for i in $(seq 1 "$N"); do
  head -4 "$WORK/job-$i.out" 2>/dev/null | sed 's/^/    /'
  rc=$(cat "$WORK/job-$i.rc" 2>/dev/null || echo none)
  if [ "$rc" = "${WANTS[$i]}" ]; then ok "${LABELS[$i]}"; else bad "${LABELS[$i]} — harness exit $rc, wanted ${WANTS[$i]}"; fi
done

# ---- summary ----
# written out, not counted as the checks run: a check that is skipped must lower the count
MIN=17
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then bad "ran $((PASS + FAIL)) checks, expected at least $MIN"; fi
echo "tokenizer-differential: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

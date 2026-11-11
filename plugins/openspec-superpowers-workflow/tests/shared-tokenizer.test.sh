#!/bin/bash
# The shell tokenizer that archive-gate and pr-closeout's merge gate each carry must stay the same.
# The two plugins install apart, so neither can source the other at runtime: each keeps a copy, and
# this suite compares the copies between `# >>> shared-tokenizer: <name>` and `# <<< shared-tokenizer: <name>`
# (indentation aside). A fix made in one copy only turns this red.
# Usage: bash plugins/openspec-superpowers-workflow/tests/shared-tokenizer.test.sh
#        (A=<path> B=<path> to compare other copies)
# Consumers: the validate-on-plugin-edit hook and CI (.github/workflows/validate.yml lists plugins/*/tests/*.test.sh)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
A=${A:-"$SCRIPT_DIR/../hooks/archive-gate.sh"}
B=${B:-"$SCRIPT_DIR/../../pr-closeout/hooks/pr-merge-gate.sh"}
# name and the fewest lines its region may hold: the floor is set here, not read from the files, so
# two regions that both came out empty can never compare as the same
REGIONS=('subs_of:14' 'heredoc pass and tokenizer:60')

WORK=$(mktemp -d "${TMPDIR:-/tmp}/shared-tokenizer-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# region <file> <name>: the lines strictly between the two markers, leading whitespace removed.
# Exit 3 when either marker is missing or appears more than once.
region() {
  NAME="$2" perl -ne '
    BEGIN { $n = $ENV{NAME}; }
    if (/^\s*# >>> shared-tokenizer: \Q$n\E(?:\s|$)/) { $open++; $in = 1; next; }
    if (/^\s*# <<< shared-tokenizer: \Q$n\E\s*$/)     { $close++; $in = 0; next; }
    if ($in) { s/^[ \t]+//; print; }
    END { exit 3 unless $open == 1 && $close == 1; }
  ' "$1"
}

# same_regions <file a> <file b> <name> <floor>: 0 same, 1 different, 2 same but below the floor, 3 a marker problem
same_regions() {
  local ra rb
  ra=$(region "$1" "$3") || return 3
  rb=$(region "$2" "$3") || return 3
  [ "$ra" = "$rb" ] || return 1
  [ "$(printf '%s\n' "$ra" | wc -l)" -ge "$4" ] || return 2
  return 0
}

# ---- the real copies ----
for r in "${REGIONS[@]}"; do
  name=${r%:*}; floor=${r##*:}
  same_regions "$A" "$B" "$name" "$floor"; rc=$?
  case $rc in
    0) ok "[$name] same in both gates" ;;
    1) bad "[$name] differs between the gates:"   # files, not <( … ): the sandbox refuses diff's /dev/fd paths
       region "$A" "$name" > "$WORK/a.reg"; region "$B" "$name" > "$WORK/b.reg"; diff "$WORK/a.reg" "$WORK/b.reg" | head -20 ;;
    2) bad "[$name] has fewer than $floor lines in a gate" ;;
    *) bad "[$name] markers missing or repeated in a gate" ;;
  esac
done

# ---- canaries: the comparison itself must be able to fail ----
first=${REGIONS[0]%:*}; ffloor=${REGIONS[0]##*:}
second=${REGIONS[1]%:*}; sfloor=${REGIONS[1]##*:}
expect_rc() {  # <label> <want rc> <file a> <file b> <name> <floor>
  same_regions "$3" "$4" "$5" "$6"; local rc=$?
  if [ "$rc" = "$2" ]; then ok "canary: $1"; else bad "canary: $1 — rc $rc, wanted $2"; fi
}
# one changed character inside a region, in either region
perl -pe 's/\$i \+= 2; next; \}/\$i += 3; next; }/ if /if \(\$ch eq "\\\\"\) \{ \$i \+= 2; next; \}/ && !$done++' "$B" > "$WORK/b-sub.sh"
expect_rc "an edit inside [$first] is caught" 1 "$A" "$WORK/b-sub.sh" "$first" "$ffloor"
perl -pe 's/# not-a-heredoc: here-string/# not-a-heredoc: here string/' "$B" > "$WORK/b-hd.sh"
expect_rc "an edit inside [$second] is caught" 1 "$A" "$WORK/b-hd.sh" "$second" "$sfloor"
# indentation and lines outside the markers are not compared
perl -pe 's/^/  /' "$B" > "$WORK/b-indent.sh"
expect_rc "indentation alone is not a difference" 0 "$A" "$WORK/b-indent.sh" "$second" "$sfloor"
printf '# an extra line outside every region\n' | cat - "$B" > "$WORK/b-outside.sh"
expect_rc "a line outside the regions is not a difference" 0 "$A" "$WORK/b-outside.sh" "$first" "$ffloor"
# a missing or repeated marker is a marker problem, not a pass
perl -ne 'print unless /# <<< shared-tokenizer: subs_of/' "$B" > "$WORK/b-nomark.sh"
expect_rc "a missing end marker is reported" 3 "$A" "$WORK/b-nomark.sh" "$first" "$ffloor"
perl -pe 'print $_ if /# >>> shared-tokenizer: subs_of/' "$B" > "$WORK/b-twice.sh"
expect_rc "a repeated start marker is reported" 3 "$A" "$WORK/b-twice.sh" "$first" "$ffloor"
# two regions that are equal but empty stay below the floor
printf '# >>> shared-tokenizer: %s\n# <<< shared-tokenizer: %s\n' "$first" "$first" > "$WORK/empty.sh"
expect_rc "two empty regions are below the floor" 2 "$WORK/empty.sh" "$WORK/empty.sh" "$first" "$ffloor"

# ---- summary ----
# written out, not counted as the canaries run: a canary that is skipped must lower the count
MIN=$(( ${#REGIONS[@]} + 7 ))
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then bad "ran $((PASS + FAIL)) assertions, expected at least $MIN"; fi
echo "shared-tokenizer: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

#!/bin/bash
# Tests for plugins/pr-closeout/scripts/pr-closeout.mjs (ready / landed).
# Usage: bash plugins/pr-closeout/tests/pr-closeout.test.sh   (SCRIPT=<path> to test a copy)
# Network-free: `ready` reads recorded GitHub answers from --fixture <dir> (fixtures/base is a green,
# mergeable PR; each case copies it and edits one thing with jq). The network path is exercised with
# gh and curl shims first on PATH. Every case runs in its own process group with a timeout, so a hang
# reads as a failure, never a stuck suite. Mutants at the end must each die on the case written for them.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SCRIPT=${SCRIPT:-"$here/../scripts/pr-closeout.mjs"}
BASE="$here/fixtures/base"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/prc-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
command -v node >/dev/null 2>&1 || { echo "pr-closeout.test: node is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "pr-closeout.test: jq is required"; exit 1; }

pass=0; fail=0
CASE_TIMEOUT=${CASE_TIMEOUT:-20}
bounded() {   # <secs> <cmd…>: own process group, whole group killed on timeout (exit 124)
  perl -e 'my $t = shift; my $pid = fork // exit 125;
    if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$pid, $pid; waitpid($pid, 0); exit 124 };
    alarm $t; waitpid($pid, 0); my $s = $?;
    exit($s & 127 ? 128 + ($s & 127) : $s >> 8)' "$@"
}
failed() {   # a mutant run (STOP_ON_FAIL=1) needs only the first failure
  fail=$((fail + 1)); echo "FAIL $1"
  [ "${STOP_ON_FAIL:-0}" = 1 ] && exit 1
  return 0
}
ok() { pass=$((pass + 1)); }
# fixture <name> [jq filter applied to graphql.json]: a copy of the base fixture; prints its dir
fixture() {
  local d="$tmp/fx/$1"
  rm -rf "$d"; mkdir -p "$tmp/fx"; cp -R "$BASE" "$d"
  if [ -n "${2:-}" ]; then jq "$2" "$BASE/graphql.json" > "$d/graphql.json" || { echo "bad jq filter for $1"; exit 2; }; fi
  printf '%s' "$d"
}
# run_cli <want exit> <label> <args…>: the script's stdout lands in $tmp/out.json, stderr in $tmp/err
run_cli() {
  local want=$1 label=$2 rc; shift 2
  bounded "$CASE_TIMEOUT" node "$SCRIPT" "$@" > "$tmp/out.json" 2> "$tmp/err"; rc=$?
  if [ "$rc" = "$want" ]; then ok; else failed "[$label] exit $rc, expected $want: $(head -c 300 "$tmp/err")"; fi
}
# ready_case <want> <label> <fixture dir> [more args]
ready_case() { local want=$1 label=$2 fx=$3; shift 3; run_cli "$want" "$label" ready example/repo 1 --fixture "$fx" "$@"; }
# jqeq <label> <filter> <expected compact JSON>, on the last run's output
jqeq() {
  local got; got=$(jq -c "$2" "$tmp/out.json" 2>/dev/null)
  if [ "$got" = "$3" ]; then ok; else failed "[$1] $2 = $got, expected $3"; fi
}
lacks() { if [[ $2 != *"$3"* ]]; then ok; else failed "[$1] contains $3"; fi; }
has() { if [[ $2 == *"$3"* ]]; then ok; else failed "[$1] lacks $3"; fi; }

# ── Task 1: query layer ──────────────────────────────────────────────────────────────────────────
ready_case 0 "fixture base" "$(fixture base)"
jqeq "fixture base: exit field" '.exit' '0'
jqeq "fixture base: no hits" '.hits' '[]'

fx=$(fixture nographql); rm -f "$fx/graphql.json"
ready_case 7 "query fails: no graphql answer" "$fx"
jqeq "query fails: first hit" '.hits[0].code' '"query-failed"'
fx=$(fixture badjson); printf '{not json' > "$fx/graphql.json"
ready_case 7 "query fails: unparsable answer" "$fx"

# the network path: gh's api calls fail, curl (token on stdin, never in argv or output) answers
mkdir -p "$tmp/shim"
cat > "$tmp/shim/gh" <<'SH'
#!/bin/bash
case " $* " in *" auth token "*) echo TOKEN_SENTINEL; exit 0 ;; esac
echo "gh: forced failure" >&2; exit 1
SH
cat > "$tmp/shim/curl" <<SH
#!/bin/bash
printf '%s\n' "\$*" >> "$tmp/curl-argv"
cat >> "$tmp/curl-stdin"
url=""; for a in "\$@"; do case \$a in https://*) url=\$a ;; esac; done
case \$url in
  */graphql) f=graphql.json ;;
  */pulls/1/comments*) f=pulls-comments.json ;;
  */pulls/1/reviews*) f=pulls-reviews.json ;;
  */issues/1/comments*) f=issues-comments.json ;;
  */compare/*) f=compare.json ;;
  */pulls\?*) f=prev-pulls.json ;;
  */commits/*) f=prev-commit.json ;;
  *) echo "curl shim: unknown url \$url" >&2; exit 22 ;;
esac
cat "$BASE/\$f"
SH
chmod +x "$tmp/shim/gh" "$tmp/shim/curl"
rm -f "$tmp/curl-argv" "$tmp/curl-stdin"
PATH="$tmp/shim:$PATH" run_cli 0 "gh fails, curl fallback" ready example/repo 1
lacks "token not in stdout" "$(cat "$tmp/out.json")" TOKEN_SENTINEL
lacks "token not in stderr" "$(cat "$tmp/err")" TOKEN_SENTINEL
lacks "token not in curl argv" "$(cat "$tmp/curl-argv" 2>/dev/null)" TOKEN_SENTINEL
has "token sent on curl stdin" "$(cat "$tmp/curl-stdin" 2>/dev/null)" "Authorization: bearer TOKEN_SENTINEL"
# both paths down: a query failure, not an empty green
printf '#!/bin/bash\nexit 7\n' > "$tmp/shim/curl"; chmod +x "$tmp/shim/curl"
PATH="$tmp/shim:$PATH" run_cli 7 "gh and curl both fail" ready example/repo 1

# ── Task 2: the exit table ───────────────────────────────────────────────────────────────────────
P='.data.repository.pullRequest'
RU="$P.commits.nodes[0].commit.statusCheckRollup"
CX="$RU.contexts.nodes"
THREAD='{isResolved:false,isOutdated:false,path:"src/a.sh",line:7,comments:{nodes:[{author:{login:"rev"}}]}}'
# gate_case <exit> <gate or ""> <label> <jq filter> [args]: exit plus the gate field
gate_case() {
  local want=$1 gate=$2 label=$3 filter=$4; shift 4
  ready_case "$want" "$label" "$(fixture "t2-$RANDOM" "$filter")" "$@"
  if [ -n "$gate" ]; then jqeq "$label: gate" '.gate' "\"$gate\""; fi
}
gate_case 6 not-open          "merged PR"                 "$P.state = \"MERGED\""
gate_case 6 not-open          "closed PR"                 "$P.state = \"CLOSED\""
gate_case 6 draft             "draft, clean"              "$P.isDraft = true"
gate_case 6 draft             "draft wins over blocked"   "$P.isDraft = true | $P.mergeStateStatus = \"BLOCKED\""
gate_case 6 changes-requested "changes requested"         "$P.reviewDecision = \"CHANGES_REQUESTED\""
gate_case 6 changes-requested "changes requested + red"   "$P.reviewDecision = \"CHANGES_REQUESTED\" | $RU.state = \"FAILURE\""
gate_case 6 head-mismatch     "other head (sha-1)"        "." --expect-head 2222222222222222222222222222222222222222
gate_case 6 head-mismatch     "other head (sha-256)"      "." --expect-head 2222222222222222222222222222222222222222222222222222222222222222
gate_case 2 ""                "conflicting"               "$P.mergeable = \"CONFLICTING\""
gate_case 2 ""                "dirty"                     "$P.mergeStateStatus = \"DIRTY\""
gate_case 3 ""                "one unresolved thread"     "$P.reviewThreads.nodes = [$THREAD]"
jqeq "threads listed" '[.threads[0].path, .threads[0].line, .threads[0].author]' '["src/a.sh",7,"rev"]'
gate_case 3 ""                "outdated is not resolved"  "$P.reviewThreads.nodes = [$THREAD | .isOutdated = true]"
gate_case 0 ""                "resolved thread"           "$P.reviewThreads.nodes = [$THREAD | .isResolved = true]"
gate_case 4 ""                "a failed check"            "$CX[1].conclusion = \"FAILURE\""
gate_case 4 ""                "a conclusion not on the list" "$CX[1].conclusion = \"TIMED_OUT\""
gate_case 4 ""                "blocked, rollup failure"   "$P.mergeStateStatus = \"BLOCKED\" | $RU.state = \"FAILURE\""
gate_case 4 ""                "blocked, rollup error"     "$P.mergeStateStatus = \"BLOCKED\" | $RU.state = \"ERROR\""
gate_case 4 ""                "a status context failed"   "$CX += [{__typename:\"StatusContext\",context:\"ci/x\",state:\"FAILURE\"}]"
gate_case 5 ""                "a check still running"     "$CX[0].status = \"IN_PROGRESS\" | $CX[0].conclusion = null"
gate_case 5 ""                "mergeable still computing" "$P.mergeable = \"UNKNOWN\""
gate_case 5 ""                "merge state still computing" "$P.mergeStateStatus = \"UNKNOWN\""
gate_case 6 blocked-unseen    "blocked, everything green" "$P.mergeStateStatus = \"BLOCKED\""
gate_case 6 blocked-unseen    "blocked, review required"  "$P.mergeStateStatus = \"BLOCKED\" | $P.reviewDecision = \"REVIEW_REQUIRED\""
gate_case 6 behind            "behind"                    "$P.mergeStateStatus = \"BEHIND\""
gate_case 6 behind            "behind, approved"          "$P.mergeStateStatus = \"BEHIND\" | $P.reviewDecision = \"APPROVED\""
gate_case 7 ""                "unknown merge state"       "$P.mergeStateStatus = \"WEIRD\""
gate_case 7 ""                "mergeable missing"         "del($P.mergeable)"
gate_case 7 ""                "unknown review decision"   "$P.reviewDecision = \"MAYBE\""
gate_case 7 ""                "more threads than one page" "$P.reviewThreads.pageInfo.hasNextPage = true"
gate_case 0 ""                "clean"                     "$P.mergeStateStatus = \"CLEAN\""
gate_case 0 ""                "has hooks"                 "$P.mergeStateStatus = \"HAS_HOOKS\""
gate_case 0 ""                "unstable, every listed check green" "$P.mergeStateStatus = \"UNSTABLE\""
gate_case 0 ""                "expected head matches"     "." --expect-head 1111111111111111111111111111111111111111
# every check runs: a conflict and an unresolved thread both appear, the exit is the more urgent one
gate_case 2 ""                "hits lists all"            "$P.mergeable = \"CONFLICTING\" | $P.reviewThreads.nodes = [$THREAD]"
jqeq "hits lists all: both codes" '[.hits[].code] | sort' '["conflict","unresolved-threads"]'
# threads outrank an unseen block (a protected repo reports BLOCKED while a thread is open), and a
# query failure outranks everything: the hits are ordered by urgency, not by when they were found
gate_case 3 ""                "blocked with an unresolved thread" "$P.mergeStateStatus = \"BLOCKED\" | $P.reviewThreads.nodes = [$THREAD]"
gate_case 7 ""                "query failure outranks a gate" "$P.state = \"MERGED\" | $P.reviewThreads.pageInfo.hasNextPage = true"

# ── summary and mutants ──────────────────────────────────────────────────────────────────────────
MIN_PASS=62
if [ "$pass" -lt "$MIN_PASS" ] && [ "${STOP_ON_FAIL:-0}" != 1 ]; then failed "only $pass checks passed, expected at least $MIN_PASS"; fi
echo "pr-closeout: $pass passed, $fail failed"

mut_bad=0; mut_n=0
mutant() {   # <label> <substring of the case that must kill it> <perl substitution>
  local label=$1 want=$2 m="$tmp/mutant-$1.mjs" log="$tmp/mutant-$1.log" rc first
  perl -pe "$3" "$SCRIPT" > "$m" || { echo "MUTANT [$label] perl failed"; mut_bad=1; return; }
  if cmp -s "$m" "$SCRIPT"; then echo "MUTANT [$label] substitution did not apply"; mut_bad=1; return; fi
  SCRIPT="$m" NO_MUTANTS=1 STOP_ON_FAIL=1 bounded 300 bash "$0" > "$log" 2>&1; rc=$?
  mut_n=$((mut_n + 1))
  first=$(command grep -m1 '^FAIL' "$log")
  if [ "$rc" = 0 ]; then echo "MUTANT [$label] suite stayed green"; mut_bad=1
  elif [ -z "$first" ]; then echo "MUTANT [$label] crashed before any case failed"; mut_bad=1
  elif [[ $first != *"$want"* ]]; then echo "MUTANT [$label] killed by [${first:0:90}], expected [$want]"; mut_bad=1
  else echo "mutant [$label]: suite red as required (by [$want])"; fi
}
if [ "${NO_MUTANTS:-0}" != 1 ]; then
  mutant outdated      "[outdated is not resolved]"        "s/t\.isResolved !== true\)/t.isResolved !== true && !t.isOutdated)/"
  mutant not-open      "[merged PR]"                       "s/p\.state !== 'OPEN'/false/"
  mutant draft         "[draft, clean]"                    "s/else if \(p\.isDraft\) gate/else if (false) gate/"
  mutant changes       "[changes requested]"               "s/p\.reviewDecision === 'CHANGES_REQUESTED'\) \{/false) {/"
  mutant head          "[other head (sha-1)]"              "s/expectHead && p\.headRefOid !== expectHead/false/"
  mutant conflict      "[conflicting]"                     "s/\(mergeableKnown && p\.mergeable === 'CONFLICTING'\) \|\|/false ||/"
  mutant failed        "[a failed check]"                  "s/if \(failedChecks\.length \|\| rollupFailed\)/if (false)/"
  mutant rollup        "[blocked, rollup failure]"         "s/const rollupFailed = rollupKnown && /const rollupFailed = false && /"
  mutant whitelist     "[a failed check]"                  "s/return OK_CONCLUSIONS\.has\(c\.conclusion\) \? 'ok' : 'failed';/return 'ok';/"
  mutant running       "[a check still running]"           "s/if \(c\.status !== 'COMPLETED'\) return 'pending';//"
  mutant computing     "[mergeable still computing]"       "s/\(mergeableKnown && p\.mergeable === 'UNKNOWN'\) \|\|/false ||/"
  mutant unseen        "[blocked, everything green]"       "s/p\.mergeStateStatus === 'BLOCKED' && !hits/false && !hits/"
  mutant behind        "[behind]"                          "s/p\.mergeStateStatus === 'BEHIND'\) gate/false) gate/"
  mutant unknown       "[unknown merge state]"             "s/KNOWN\[field\]\.has\(value\) \? true :/true ? true :/"
  mutant soft-rank     "[blocked with an unresolved thread]" "s/SOFT_GATES\.has\(h\.gate\) \? 6 :/SOFT_GATES.has(h.gate) ? 1 :/"
  mutant unsorted      "[query failure outranks a gate]"   "s/^  hits\.sort\(.*\n//"
  MUT_WANT_N=16
  if [ "$mut_n" != "$MUT_WANT_N" ]; then echo "FAIL: $mut_n of $MUT_WANT_N mutants ran"; mut_bad=1; fi
  [ "$mut_bad" = 0 ] || fail=$((fail + 1))
fi
[ "$fail" = 0 ]

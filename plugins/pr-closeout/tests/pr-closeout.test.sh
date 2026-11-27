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
# Removed first: a run that dies of SIGPIPE runs its EXIT trap only up to the first builtin. Then the
# subshells of the mutant runs still going after a Ctrl-C are stopped and waited for, and it is removed
# again: they write their .rc files here, and one removal racing them left the directory behind. The
# runs under them are not signalled; they end on their own within seconds, since what they test is a copy
# in this directory.
trap 'rm -rf "$tmp"; kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; rm -rf "$tmp"' EXIT
command -v node >/dev/null 2>&1 || { echo "pr-closeout.test: node is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "pr-closeout.test: jq is required"; exit 1; }
# never the real per-user list: every case below names the config it means
export PR_CLOSEOUT_CONFIG="$tmp/no-config.json"
export RECONCILE_CHECK="$tmp/no-reconcile-check.cjs"   # never the installed plugin's copy

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
gate_case 7 ""                "rollup field missing"      "del($RU)"
gate_case 7 ""                "rollup not an object"      "$RU = \"SUCCESS\""
gate_case 0 ""                "no checks at all (null rollup)" "$RU = null"
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

# ── Task 3: required checks, suspected skips, precedent, base, comments ──────────────────────────
printf '%s' '{"example/repo":{"required":["security-review","validate-fixtures"],"minSeconds":{"security-review":30}}}' > "$tmp/cfg.json"
printf '%s' '{"other/repo":{"required":["security-review"]}}' > "$tmp/cfg-other.json"
printf '{not json' > "$tmp/cfg-bad.json"
withcfg() { local c=$1; shift; PR_CLOSEOUT_CONFIG="$c" "$@"; }
withcfg "$tmp/cfg.json" ready_case 4 "required missing: security-review" "$(fixture t3a "del($CX[0])")"
has "required missing: named" "$(cat "$tmp/out.json")" "required check missing: security-review"
withcfg "$tmp/cfg.json" ready_case 4 "required missing: validate-fixtures" "$(fixture t3b "del($CX[1])")"
withcfg "$tmp/cfg.json" ready_case 0 "required all present" "$(fixture t3c)"
withcfg "$tmp/cfg-other.json" ready_case 0 "repo not on the list" "$(fixture t3d "del($CX[0])")"
withcfg "$tmp/absent.json" ready_case 0 "no config file" "$(fixture t3e "del($CX[0])")"
withcfg "$tmp/cfg-bad.json" ready_case 7 "config not JSON" "$(fixture t3f)"
printf '%s' '{"example/repo":{"required":"security-review"}}' > "$tmp/cfg-shape.json"
withcfg "$tmp/cfg-shape.json" ready_case 7 "config of the wrong shape" "$(fixture t3g)"
withcfg "$tmp/cfg.json" ready_case 0 "suspected skip" "$(fixture t3h "$CX[0].completedAt = \"2026-11-09T00:00:12Z\"")"
jqeq "suspected skip: named" '.suspectedSkip' '["security-review"]'
withcfg "$tmp/cfg.json" ready_case 0 "long enough" "$(fixture t3i "$CX[0].completedAt = \"2026-11-09T00:00:45Z\"")"
jqeq "long enough: none" '.suspectedSkip' '[]'
fx=$(fixture t3j); ready_case 0 "precedent squash" "$fx"
jqeq "precedent squash: method" '[.precedent.pr, .precedent.parents, .precedent.method]' '[8,1,"squash"]'
fx=$(fixture t3k); jq '.parents += [{sha:"5555555555555555555555555555555555555555"}]' "$BASE/prev-commit.json" > "$fx/prev-commit.json"
ready_case 0 "precedent merge" "$fx"
jqeq "precedent merge: method" '.precedent.method' '"merge"'
fx=$(fixture t3l); echo '[]' > "$fx/prev-pulls.json"; rm -f "$fx/prev-commit.json"
ready_case 0 "no precedent" "$fx"
jqeq "no precedent: unknown" '.precedent.method' '"unknown"'
fx=$(fixture t3m); echo '{"behind_by":3,"ahead_by":1}' > "$fx/compare.json"
ready_case 0 "base behind" "$fx"
jqeq "base behind: count" '.baseBehind' '3'
fx=$(fixture t3n)
echo '[{"user":{"login":"bot-a"},"body":"inline"}]' > "$fx/pulls-comments.json"
echo '[{"user":{"login":"rev"},"state":"COMMENTED","body":"r"}]' > "$fx/pulls-reviews.json"
echo '[{"user":{"login":"bot-a"},"body":"summary $(touch /tmp/never)"}]' > "$fx/issues-comments.json"
ready_case 0 "comments counted" "$fx"
jqeq "comments: counts and authors" '[.comments.pullsComments, .comments.pullsReviews, .comments.issuesComments, .comments.authors]' '[1,1,1,["bot-a","rev"]]'

# ── Task 4: reviewed bytes equal merged bytes ────────────────────────────────────────────────────
G="git -c user.name=t -c user.email=t@t -c commit.gpgsign=false"
R4="$tmp/r4"
mkrepo4() {   # main with c.txt; branch feat/x adds a.sh and b.md; origin/main set by hand
  rm -rf "$R4"; git init -q -b main "$R4"
  echo base > "$R4/c.txt"; git -C "$R4" add c.txt; $G -C "$R4" commit -q -m base
  git -C "$R4" update-ref refs/remotes/origin/main HEAD
  git -C "$R4" switch -q -c feat/x
  echo a > "$R4/a.sh"; echo doc > "$R4/b.md"; git -C "$R4" add a.sh b.md; $G -C "$R4" commit -q -m feat
}
blob4() { git -C "$R4" ls-tree HEAD -- "$1" | awk '{print $3}'; }
# record4 <branch> <file>=<blob>...: review-branch's state for the round that reviewed these blobs
record4() {
  local branch=$1; shift
  printf '%s\n' "$@" | jq -R 'split("=") | {file: .[0], blob: .[1], status: "reviewed"}' | jq -s --arg b "$branch" '{branch: $b, head: "x", scopedFiles: .}' > "$R4/.git/review-branch-last.json"
}
# cov_case <want> <label> [args]: ready against the r4 repo, the PR's head being r4's HEAD
cov_case() {
  local want=$1 label=$2 sha; shift 2
  sha=$(git -C "$R4" rev-parse HEAD)
  ready_case "$want" "$label" "$(fixture "t4-$RANDOM" "$P.headRefOid = \"$sha\" | $P.headRefName = \"feat/x\"")" --repo-dir "$R4" "$@"
}
mkrepo4; record4 feat/x "a.sh=$(blob4 a.sh)" "b.md=$(blob4 b.md)"
cov_case 0 "reviewed blobs are the merged blobs"
jqeq "covered" '.coverage.status' '"covered"'
old=$(blob4 a.sh); echo a2 > "$R4/a.sh"; $G -C "$R4" commit -q -am fix
cov_case 6 "a file changed after the review"
jqeq "unreviewed: gate" '.gate' '"unreviewed"'
jqeq "unreviewed: named" '.coverage.unreviewed' '["a.sh"]'
mkrepo4; record4 feat/x "a.sh=$(blob4 a.sh)" "b.md=$(blob4 b.md)"
echo c > "$R4/c.sh"; git -C "$R4" add c.sh; $G -C "$R4" commit -q -m new
cov_case 6 "a file the review never saw"
jqeq "never seen: named" '.coverage.unreviewed' '["c.sh"]'
mkrepo4; h=$(blob4 a.sh); record4 feat/x "a.sh=$h" "b.md=$(blob4 b.md)"
chmod +x "$R4/a.sh"; git -C "$R4" add a.sh; $G -C "$R4" commit -q -m mode
cov_case 6 "executable bit added after the review"
record4 feat/x "a.sh=$h+x" "b.md=$(blob4 b.md)"
cov_case 0 "executable recorded as +x"
# a symlink is recorded as link:<hash>: git stores it as a blob of its target text, and only the
# mode tells it from a regular file with those bytes
mkrepo4; ln -s b.md "$R4/l.sh"; git -C "$R4" add l.sh; $G -C "$R4" commit -q -m link
record4 feat/x "a.sh=$(blob4 a.sh)" "b.md=$(blob4 b.md)" "l.sh=link:$(blob4 l.sh)"
cov_case 0 "symlink recorded as link:"
record4 feat/x "a.sh=$(blob4 a.sh)" "b.md=$(blob4 b.md)" "l.sh=$(blob4 l.sh)"
cov_case 6 "a file reviewed, a symlink with the same bytes merged"
jqeq "symlink for a file: named" '.coverage.unreviewed' '["l.sh"]'
mkrepo4; record4 feat/x "a.sh=$(blob4 a.sh)" "b.md=$(blob4 b.md)"
echo doc2 > "$R4/b.md"; $G -C "$R4" commit -q -am docs
cov_case 0 "only a document changed after the review"
jqeq "docs only: listed" '.coverage.docsOnly' '["b.md"]'
mkrepo4
cov_case 0 "no review record"
jqeq "no record: unknown" '.coverage.status' '"unknown"'
record4 feat/other "a.sh=$(blob4 a.sh)"
cov_case 0 "record from another branch"
jqeq "other branch: unknown" '.coverage.status' '"unknown"'
record4 feat/x "a.sh=$(blob4 a.sh)" "b.md=$(blob4 b.md)"
ready_case 0 "head not in the local clone" "$(fixture t4h "$P.headRefOid = \"9999999999999999999999999999999999999999\" | $P.headRefName = \"feat/x\"")" --repo-dir "$R4"
jqeq "head not here: unknown" '.coverage.status' '"unknown"'
mkrepo4; record4 feat/x "a.sh=$(blob4 a.sh)" "b.md=$(blob4 b.md)"
echo a2 > "$R4/a.sh"; $G -C "$R4" commit -q -am fix
cov_case 0 "accepted with a reason" --accept-unreviewed "a.sh=codex r3 reviewed it"
jqeq "accepted: recorded" '[.coverage.status, .coverage.accepted[0].path, .coverage.accepted[0].reason]' '["covered","a.sh","codex r3 reviewed it"]'
cov_case 7 "accepted without a reason" --accept-unreviewed "a.sh="
cov_case 6 "accepting another file does not cover this one" --accept-unreviewed "z.sh=not this one"
# a closed PR is the more basic fact: not-open outranks unreviewed when both hold
mkrepo4; record4 feat/x "a.sh=$(blob4 a.sh)" "b.md=$(blob4 b.md)"; echo a2 > "$R4/a.sh"; $G -C "$R4" commit -q -am fix
sha=$(git -C "$R4" rev-parse HEAD)
ready_case 6 "merged and unreviewed" "$(fixture t4m "$P.headRefOid = \"$sha\" | $P.headRefName = \"feat/x\" | $P.state = \"MERGED\"")" --repo-dir "$R4"
jqeq "merged and unreviewed: gate" '.gate' '"not-open"'

# ── Task 5: unarchived openspec changes (a warning, never the exit) ───────────────────────────────
mkrepo4; cov_case 0 "no openspec dir"
jqeq "no openspec: absent" '.openspec.present' 'false'
mkdir -p "$R4/openspec/changes/foo" "$R4/openspec/changes/bar"
echo t > "$R4/openspec/changes/foo/tasks.md"; echo t > "$R4/openspec/changes/bar/tasks.md"
git -C "$R4" add openspec; $G -C "$R4" commit -q -m changes
printf '%s\n' "process.stdout.write(process.argv[2] === 'verify' ? 'stale:tasks\n' : ''); process.exitCode = 3;" > "$tmp/fake-reconcile.cjs"
RECONCILE_CHECK="$tmp/fake-reconcile.cjs" cov_case 0 "two unarchived changes"
jqeq "unarchived: named, sorted" '[.openspec.unarchivedChanges[].name]' '["bar","foo"]'
jqeq "unarchived: verify read" '.openspec.unarchivedChanges[0].verify' '"stale:tasks"'
cov_case 0 "verify script not found"
jqeq "not found: unavailable" '.openspec.unarchivedChanges[0].verify' '"unavailable"'
# verify shares the run's deadline: a checker that hangs is cut off and reported as unavailable
printf '%s\n' "Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 6000); process.stdout.write('stale:tasks\n'); process.exitCode = 3;" > "$tmp/slow-reconcile.cjs"
RECONCILE_CHECK="$tmp/slow-reconcile.cjs" PR_CLOSEOUT_DEADLINE_MS=3000 cov_case 0 "verify script hangs"
jqeq "verify hangs: unavailable" '.openspec.unarchivedChanges[0].verify' '"unavailable"'
mkrepo4; mkdir -p "$R4/openspec/changes/archive/2026-11-09-foo"; echo t > "$R4/openspec/changes/archive/2026-11-09-foo/tasks.md"
git -C "$R4" add openspec; $G -C "$R4" commit -q -m archived
cov_case 0 "only an archived change"
jqeq "archived only: none" '[.openspec.present, .openspec.unarchivedChanges]' '[true,[]]'

# ── Task 6: landed ───────────────────────────────────────────────────────────────────────────────
O6="$tmp/o6.git"; C6="$tmp/c6"
mkrepo6() {   # origin with main; the clone pushes feat/y, then a squash commit lands on origin/main
  rm -rf "$O6" "$C6"; git init -q --bare -b main "$O6"; git init -q -b main "$C6"; git -C "$C6" remote add origin "$O6"
  echo base > "$C6/c.txt"; git -C "$C6" add c.txt; $G -C "$C6" commit -q -m base; git -C "$C6" push -q origin main 2>/dev/null
  git -C "$C6" switch -q -c feat/y; echo y > "$C6/y.sh"; git -C "$C6" add y.sh; $G -C "$C6" commit -q -m y
  git -C "$C6" push -q origin feat/y 2>/dev/null; H6=$(git -C "$C6" rev-parse HEAD)
  git -C "$C6" switch -q main; echo y > "$C6/y.sh"; git -C "$C6" add y.sh; $G -C "$C6" commit -q -m "y (squash)"
  git -C "$C6" push -q origin main 2>/dev/null; MC6=$(git -C "$C6" rev-parse HEAD)
}
# lfix <name> [jq on pull.json] [open pulls json]: a landed fixture dir
lfix() {
  local d="$tmp/lfx/$1"; rm -rf "$d"; mkdir -p "$d"
  jq -n --arg h "$H6" --arg m "$MC6" '{merged_at:"2026-11-09T00:00:00Z", head:{sha:$h, ref:"feat/y"}, merge_commit_sha:$m, base:{ref:"main"}}' | jq "${2:-.}" > "$d/pull.json"
  printf '%s' "${3:-[]}" > "$d/open-pulls.json"
  printf '%s' "$d"
}
landed_case() { local want=$1 label=$2 fx=$3; shift 3; run_cli "$want" "$label" landed example/repo 1 --fixture "$fx" --repo-dir "$C6" "$@"; }
mkrepo6
landed_case 0 "merged, head matches, on base" "$(lfix l1)" --expect-head "$H6"
jqeq "landed: facts" '[.headMatches, .onBase]' '[true,true]'
landed_case 6 "not merged" "$(lfix l2 '.merged_at = null')" --expect-head "$H6"
jqeq "not merged: gate" '.gate' '"not-merged"'
landed_case 6 "another head was merged" "$(lfix l3)" --expect-head 2222222222222222222222222222222222222222
jqeq "other head: gate" '.gate' '"head-mismatch"'
git -C "$C6" switch -q -c side "$MC6~1"; echo s > "$C6/s.txt"; git -C "$C6" add s.txt; $G -C "$C6" commit -q -m side; SIDE=$(git -C "$C6" rev-parse HEAD); git -C "$C6" switch -q main
landed_case 6 "merge commit not on the base" "$(lfix l4 ".merge_commit_sha = \"$SIDE\"")" --expect-head "$H6"
jqeq "not on base: gate" '.gate' '"not-on-base"'
landed_case 6 "remote branch still there" "$(lfix l5)" --expect-head "$H6" --branch feat/y
jqeq "remote still there: where" '[.branch.remote, .branch.local]' '[true,true]'
git -C "$C6" push -q origin --delete feat/y 2>/dev/null
landed_case 6 "local branch still there" "$(lfix l6)" --expect-head "$H6" --branch feat/y
jqeq "local still there: where" '[.branch.remote, .branch.local]' '[false,true]'
git -C "$C6" branch -q -D feat/y
landed_case 6 "an open PR on the branch" "$(lfix l7 . '[{"number":5}]')" --expect-head "$H6" --branch feat/y
jqeq "open PR: counted" '.branch.openPulls' '1'
landed_case 0 "everything cleaned up" "$(lfix l8)" --expect-head "$H6" --branch feat/y
mkdir -p "$tmp/gshim"; printf '#!/bin/bash\ncase " $* " in *" fetch "*) echo "git: forced fetch failure" >&2; exit 128 ;; esac\nexec %q "$@"\n' "$(command -v git)" > "$tmp/gshim/git"; chmod +x "$tmp/gshim/git"
PATH="$tmp/gshim:$PATH" landed_case 7 "fetch fails" "$(lfix l9)" --expect-head "$H6"
landed_case 7 "landed without --expect-head" "$(lfix l10)"

# ── Task 8: the skill body names only what the script has ────────────────────────────────────────
SKILL="$here/../skills/pr-closeout/SKILL.md"
if [ -f "$SKILL" ] && head -5 "$SKILL" | command grep -q '^name: pr-closeout$' && head -5 "$SKILL" | command grep -q '^description: .'; then ok; else failed "[skill frontmatter] name: pr-closeout and a description"; fi
usage=$(node "$SCRIPT" 2>&1 >/dev/null)
for w in $(command grep -o -E 'pr-closeout\.mjs (ready|landed)|--(expect-head|repo-dir|branch|fixture|accept-unreviewed)' "$SKILL" 2>/dev/null | sed 's/^pr-closeout\.mjs //' | sort -u); do
  if [[ $usage == *"$w"* ]]; then ok; else failed "[skill names $w] not in the script's usage"; fi
done
skill_words=$(command grep -c -E 'pr-closeout\.mjs (ready|landed)' "$SKILL" 2>/dev/null)
if [ "${skill_words:-0}" -ge 2 ]; then ok; else failed "[skill shows both subcommands] found ${skill_words:-0}"; fi

# ── found by the final review ───────────────────────────────────────────────────────────────────
# round 2+: review-branch records a file it did not re-read as skipped with unchangedSince — settled
mkrepo4; jq -n --arg a "$(blob4 a.sh)" --arg b "$(blob4 b.md)" '{branch:"feat/x", head:"x", scopedFiles:[{file:"a.sh",blob:$a,status:"skipped",skipReason:"unchanged since r1 (blob match)",unchangedSince:1},{file:"b.md",blob:$b,status:"reviewed"}]}' > "$R4/.git/review-branch-last.json"
cov_case 0 "skipped as unchanged since an earlier round"
jqeq "skipped unchanged: covered" '.coverage.status' '"covered"'
jq '.scopedFiles[0] |= del(.unchangedSince) | .scopedFiles[0].skipReason = "out of focus"' "$R4/.git/review-branch-last.json" > "$tmp/rb.json" && mv "$tmp/rb.json" "$R4/.git/review-branch-last.json"
cov_case 6 "skipped for another reason"
# a prompt file carries behaviour in a plugin repo: not a document
mkrepo4; mkdir -p "$R4/skills/s"; echo s > "$R4/skills/s/SKILL.md"; git -C "$R4" add skills; $G -C "$R4" commit -q -m skill
record4 feat/x "a.sh=$(blob4 a.sh)" "b.md=$(blob4 b.md)"
cov_case 6 "a skill file is not a document"
jqeq "skill file: unreviewed" '.coverage.unreviewed' '["skills/s/SKILL.md"]'
mkrepo4; echo req > "$R4/requirements-dev.txt"; git -C "$R4" add requirements-dev.txt; $G -C "$R4" commit -q -m req
record4 feat/x "a.sh=$(blob4 a.sh)" "b.md=$(blob4 b.md)"
cov_case 6 "a requirements file is not a document"
# a slow GitHub ends in exit 7 inside the deadline, never past the hook's own timeout
printf '#!/bin/bash\ncase " $* " in *" auth token "*) echo T; exit 0 ;; esac\nsleep 5; exit 1\n' > "$tmp/shim/gh"
printf '#!/bin/bash\ncat >/dev/null; sleep 5; exit 1\n' > "$tmp/shim/curl"; chmod +x "$tmp/shim/gh" "$tmp/shim/curl"
t0=$(date +%s)
PATH="$tmp/shim:$PATH" PR_CLOSEOUT_DEADLINE_MS=1500 run_cli 7 "slow GitHub hits the deadline" ready example/repo 1
t1=$(date +%s); if [ $((t1 - t0)) -le 4 ]; then ok; else failed "[deadline] took $((t1 - t0))s, expected under 4s"; fi

# a deletion is a change too: review-branch records a reviewed deletion as blob "deleted"
mkrepo4; git -C "$R4" switch -q main; echo z > "$R4/z.sh"; git -C "$R4" add z.sh; $G -C "$R4" commit -q -m z
git -C "$R4" update-ref refs/remotes/origin/main HEAD; git -C "$R4" switch -q feat/x; git -C "$R4" -c user.name=t -c user.email=t@t rebase -q main
record4 feat/x "a.sh=$(blob4 a.sh)" "b.md=$(blob4 b.md)"
git -C "$R4" rm -q z.sh; $G -C "$R4" commit -q -m "drop z"
cov_case 6 "a deletion the review never saw"
jqeq "unreviewed deletion: named" '.coverage.unreviewed' '["z.sh"]'
record4 feat/x "a.sh=$(blob4 a.sh)" "b.md=$(blob4 b.md)" "z.sh=deleted"
cov_case 0 "a deletion the review saw"

# ── pr-watch Task 1: ready lists every comment and the cross-repo flag ───────────────────────────
fx=$(fixture comments)
printf '[{"id":11,"updated_at":"2026-11-25T01:00:00Z","body":"inline","user":{"login":"claude[bot]"}}]' > "$fx/pulls-comments.json"
printf '[{"id":22,"submitted_at":"2026-11-25T02:00:00Z","body":"  ","user":{"login":"claude[bot]"}}]' > "$fx/pulls-reviews.json"
printf '[{"id":33,"updated_at":"2026-11-25T03:00:00Z","body":"summary","user":{"login":"someone"}}]' > "$fx/issues-comments.json"
ready_case 0 "comment items listed" "$fx"
jqeq "comment items: three" '.comments.items | length' '3'
jqeq "comment items: inline updatedAt" '[.comments.items[] | select(.endpoint == "pulls/comments") | .updatedAt]' '["2026-11-25T01:00:00Z"]'
jqeq "comment items: review uses submitted_at" '[.comments.items[] | select(.endpoint == "pulls/reviews") | .updatedAt]' '["2026-11-25T02:00:00Z"]'
jqeq "comment items: blank review is emptyBody" '[.comments.items[] | select(.emptyBody) | .id]' '[22]'
jqeq "comment items: issue comment not emptyBody" '[.comments.items[] | select(.endpoint == "issues/comments") | .emptyBody]' '[false]'
jqeq "comment items: author" '[.comments.items[] | select(.id == 33) | .author]' '["someone"]'
ready_case 0 "cross-repo flag false" "$(fixture base)"
jqeq "cross-repo flag false" '.isCrossRepository' 'false'
ready_case 0 "cross-repo flag true" "$(fixture fork '.data.repository.pullRequest.isCrossRepository = true')"
jqeq "cross-repo flag true" '.isCrossRepository' 'true'

# ── pr-watch Task 2: comment pages, body hash, detailsUrl ────────────────────────────────────────
page100() { jq -n --argjson from "$1" '[range($from; $from + 100) | {id: ., updated_at: "2026-11-25T00:00:00Z", body: "b\(.)", user: {login: "u"}}]'; }
fx=$(fixture pages2)
page100 1 > "$fx/pulls-comments.json"
printf '[{"id":9001,"updated_at":"2026-11-25T00:00:00Z","body":"last","user":{"login":"u"}}]' > "$fx/pulls-comments.2.json"
ready_case 0 "101 comments over two pages read in full" "$fx"
jqeq "two pages: count" '.comments.pullsComments' '101'
jqeq "two pages: last one listed" '[.comments.items[] | select(.id == 9001) | .id]' '[9001]'
fx=$(fixture pages-exact)
page100 1 > "$fx/issues-comments.json"
ready_case 0 "exactly 100 comments, no second page" "$fx"
jqeq "exactly 100: count" '.comments.issuesComments' '100'
fx=$(fixture pages10)
page100 1 > "$fx/pulls-reviews.json"
for n in 2 3 4 5 6 7 8 9 10; do page100 $((n * 1000)) > "$fx/pulls-reviews.$n.json"; done
ready_case 7 "ten full pages is more than read" "$fx"
jqeq "ten full pages: query-failed" '.hits[0].code' '"query-failed"'
fx=$(fixture hash)
printf '[{"id":1,"updated_at":"t","body":"same","user":{"login":"u"}},{"id":2,"updated_at":"t","body":"same","user":{"login":"u"}},{"id":3,"updated_at":"t","body":"other","user":{"login":"u"}}]' > "$fx/issues-comments.json"
ready_case 0 "body hash" "$fx"
jqeq "body hash: 16 hex" '[.comments.items[].bodyHash | test("^[0-9a-f]{16}$")] | all' 'true'
jqeq "body hash: same body same hash" '[.comments.items[] | .bodyHash] | (.[0] == .[1]) and (.[0] != .[2])' 'true'
ready_case 0 "detailsUrl carried" "$(fixture details "$CX[0].detailsUrl = \"https://github.com/o/r/actions/runs/77/job/88\"")"
jqeq "detailsUrl carried" '.checks[0].detailsUrl' '"https://github.com/o/r/actions/runs/77/job/88"'

# ── pr-watch Task 3: state file, watch-ack ───────────────────────────────────────────────────────
WD="$tmp/wd3"; mkdir -p "$WD/.claude"; ST="$WD/.claude/pr-watch.1.local.json"
K1="issues/comments:33:0123456789abcdef"; K2="pulls/reviews:22:fedcba9876543210"
state_json() {   # <pr> <version>: a valid state with one seen key
  printf '{"version":%s,"pr":%s,"active":true,"startedAt":"2026-11-25T00:00:00.000Z","round":3,"seen":["%s"],"headSeen":{},"lastSignature":null,"noProgressRounds":0,"unchangedRounds":0,"queryFailures":0,"lastTickAt":null}' "$2" "$1" "$K1"
}
rm -f "$ST"
run_cli 7 "watch-ack without a state file" watch-ack example/repo 1 --repo-dir "$WD" --comment "$K1"
if [ -e "$ST" ]; then failed "[watch-ack without a state file] created one"; else ok; fi
state_json 1 1 > "$ST"
run_cli 0 "watch-ack adds keys" watch-ack example/repo 1 --repo-dir "$WD" --comment "$K1" --comment "$K2" --comment "$K2"
jqeq "watch-ack: seen deduplicated" '.state.seen' "[\"$K1\",\"$K2\"]"
if [ "$(jq -c .seen "$ST")" = "[\"$K1\",\"$K2\"]" ]; then ok; else failed "[watch-ack: written] $(jq -c .seen "$ST")"; fi
run_cli 7 "watch-ack rejects a malformed key" watch-ack example/repo 1 --repo-dir "$WD" --comment "issues/comments:33"
run_cli 7 "watch-ack needs a comment" watch-ack example/repo 1 --repo-dir "$WD"
for bad in broken v2 otherpr; do
  case $bad in broken) printf '{not json' > "$ST" ;; v2) state_json 1 2 > "$ST" ;; otherpr) state_json 2 1 > "$ST" ;; esac
  cp "$ST" "$tmp/st-before"
  run_cli 7 "state $bad refused" watch-ack example/repo 1 --repo-dir "$WD" --comment "$K2"
  if cmp -s "$ST" "$tmp/st-before"; then ok; else failed "[state $bad refused] file changed"; fi
done
# startState keeps what was seen and resets the rest (watch --start uses it; Task 5 runs it end to end)
got=$(node --input-type=module -e "
  import { startState } from '$SCRIPT';
  const s = startState({ version: 1, pr: 1, seen: ['a'], round: 9, startedAt: 'x', headSeen: { h: 1 }, lastSignature: 's', noProgressRounds: 2, unchangedRounds: 4, queryFailures: 2, lastTickAt: 'y', active: false }, 1, new Date('2026-11-25T10:00:00Z'));
  console.log(JSON.stringify([s.seen, s.round, s.active, s.startedAt, s.headSeen, s.lastSignature, s.noProgressRounds, s.unchangedRounds, s.queryFailures]));" 2>&1)
if [ "$got" = '[["a"],0,true,"2026-11-25T10:00:00.000Z",{},null,0,0,0]' ]; then ok; else failed "[startState keeps seen, resets the rest] $got"; fi
got=$(node --input-type=module -e "import { startState } from '$SCRIPT'; console.log(JSON.stringify(startState(null, 4, new Date(0)).seen))" 2>&1)
if [ "$got" = '[]' ]; then ok; else failed "[startState from nothing] $got"; fi

# ── pr-watch Task 4: watchVerdict, one round at a time ───────────────────────────────────────────
# A ready verdict is recorded from a fixture, then fed to watchVerdict with a state file that each
# round rewrites, so a sequence of rounds reads like a watch: wstart, then wround per round.
cat > "$tmp/wv.mjs" <<'JS'
import fs from 'node:fs';
const [script, vf, qerr, sf, localJ, extraJ, now] = process.argv.slice(2);
const m = await import(script);
const verdict = vf === '-' ? null : JSON.parse(fs.readFileSync(vf, 'utf8'));
const state = JSON.parse(fs.readFileSync(sf, 'utf8'));
const r = m.watchVerdict(verdict, qerr || null, state, JSON.parse(localJ), JSON.parse(extraJ), new Date(now));
fs.writeFileSync(sf, JSON.stringify(r.state));
console.log(JSON.stringify(r));
JS
H1=1111111111111111111111111111111111111111
LOCAL='{"head":"'$H1'","headKnown":true,"headAllowed":true,"unpushed":0,"dirty":false}'
WST="$tmp/wv-state.json"
T0=2026-11-25T00:00:00Z
mkv() {   # <name> <fixture dir> [env assignments…]: records ready's verdict, prints its path
  local name=$1 fx=$2; shift 2
  env "$@" node "$SCRIPT" ready example/repo 1 --fixture "$fx" > "$tmp/v-$name.json" 2>/dev/null
  printf '%s' "$tmp/v-$name.json"
}
wstart() {   # [now]: a new stretch of watching on top of whatever state is there
  node --input-type=module -e "
    import fs from 'node:fs'; import { startState } from '$SCRIPT';
    const prev = fs.existsSync('$WST') ? JSON.parse(fs.readFileSync('$WST', 'utf8')) : null;
    fs.writeFileSync('$WST', JSON.stringify(startState(prev, 1, new Date('${1:-$T0}'))));"
}
fresh() { rm -f "$WST"; wstart "$@"; }
wround() {   # <label> <verdict|-> <minutes after T0> [local json] [query error] [extra json]
  local at; at=$(node -e "console.log(new Date(Date.parse('$T0') + $3 * 60000).toISOString())")
  if node "$tmp/wv.mjs" "$SCRIPT" "$2" "${5:-}" "$WST" "${4:-$LOCAL}" "${6:-{\}}" "$at" > "$tmp/out.json" 2> "$tmp/err"; then ok
  else failed "[$1] watchVerdict threw: $(head -c 300 "$tmp/err")"; fi
}
stops() { jqeq "$1" '.watch.stop.reason // "none"' "\"$2\""; }   # <label> <reason or none>

V_BASE=$(mkv base "$(fixture wv-base)")
V_MERGED=$(mkv merged "$(fixture wv-merged "$P.state = \"MERGED\"")")
V_CLOSED=$(mkv closed "$(fixture wv-closed "$P.state = \"CLOSED\"")")
V_FORK=$(mkv fork "$(fixture wv-fork "$P.isCrossRepository = true")")
V_FORKRED=$(mkv forkred "$(fixture wv-forkred "$P.isCrossRepository = true | $CX[0].conclusion = \"FAILURE\"")")
V_NOFLAG=$(mkv noflag "$(fixture wv-noflag "del($P.isCrossRepository)")")
V_THREAD=$(mkv thread "$(fixture wv-thread "$P.reviewThreads.nodes = [$THREAD]")")
V_CONFLICT=$(mkv conflict "$(fixture wv-conflict "$P.mergeable = \"CONFLICTING\"")")
V_PENDING=$(mkv pending "$(fixture wv-pending "$CX[0].status = \"IN_PROGRESS\"")")
V_NOROLLUP=$(mkv norollup "$(fixture wv-norollup "$P.commits.nodes[0].commit.statusCheckRollup = null")")
V_RED=$(mkv red "$(fixture wv-red "$CX[0].conclusion = \"FAILURE\" | $CX[0].detailsUrl = \"https://github.com/o/r/actions/runs/77/job/1\"")")
V_RED2=$(mkv red2 "$(fixture wv-red2 "$CX[1].conclusion = \"FAILURE\"")")
V_WEIRD=$(mkv weird "$(fixture wv-weird "$P.mergeable = \"WEIRD\"")")
printf '{"example/repo":{"required":["absent-check"]}}' > "$tmp/req.json"
V_MISSING=$(mkv missing "$(fixture wv-missing)" PR_CLOSEOUT_CONFIG="$tmp/req.json")
fx=$(fixture wv-comment); printf '[{"id":33,"updated_at":"t","body":"please fix","user":{"login":"claude[bot]"}}]' > "$fx/issues-comments.json"
V_COMMENT=$(mkv comment "$fx")
fx=$(fixture wv-comment2); printf '[{"id":33,"updated_at":"t","body":"please fix","user":{"login":"claude[bot]"}},{"id":35,"updated_at":"t","body":"one more","user":{"login":"r[bot]"}}]' > "$fx/issues-comments.json"
V_COMMENT2=$(mkv comment2 "$fx")
fx=$(fixture wv-threadcomment "$P.reviewThreads.nodes = [$THREAD]"); printf '[{"id":34,"updated_at":"t","body":"new","user":{"login":"claude[bot]"}}]' > "$fx/issues-comments.json"
V_THREADCOMMENT=$(mkv threadcomment "$fx")
fx=$(fixture wv-review1); printf '[{"id":22,"submitted_at":"t","body":"first","user":{"login":"r"}},{"id":23,"submitted_at":"t","body":" ","user":{"login":"r"}}]' > "$fx/pulls-reviews.json"
V_REVIEW1=$(mkv review1 "$fx")
fx=$(fixture wv-review2); printf '[{"id":22,"submitted_at":"t","body":"edited","user":{"login":"r"}},{"id":23,"submitted_at":"t","body":" ","user":{"login":"r"}}]' > "$fx/pulls-reviews.json"
V_REVIEW2=$(mkv review2 "$fx")
fx=$(fixture wv-noid); printf '[{"id":null,"updated_at":"t","body":"x","user":{"login":"u"}}]' > "$fx/issues-comments.json"
V_NOID=$(mkv noid "$fx")
ackall() {   # acks the keys the last round reported, as the skill does: the key is watch's, never rebuilt here
  node -e "const o=require('$tmp/out.json'); const s=require('$WST'); s.seen=[...new Set([...s.seen, ...o.watch.newComments])]; require('fs').writeFileSync('$WST', JSON.stringify(s))"
}

# not-open, fork, head-not-allowed: the first round already knows
fresh; wround "merged" "$V_MERGED" 1; stops "merged stops" not-open; jqeq "merged: exit 8" '.exit' '8'; jqeq "stop clears active" '.state.active' 'false'
fresh; wround "closed" "$V_CLOSED" 1; stops "closed stops" not-open
fresh; wround "fork, green" "$V_FORK" 1; stops "fork, green stops" fork
fresh; wround "fork, red" "$V_FORKRED" 1; stops "fork, red stops" fork
fresh; wround "head not in the clone" "$V_BASE" 1 '{"head":"'$H1'","headKnown":false,"headAllowed":false,"unpushed":null,"dirty":false}'
stops "head not in the clone stops" head-not-allowed
fresh; wround "head not an ancestor" "$V_BASE" 1 '{"head":"'$H1'","headKnown":true,"headAllowed":false,"unpushed":null,"dirty":false}'
stops "head not an ancestor stops" head-not-allowed
# query-failed: only the third failure in a row stops; a good round in between resets the count
fresh; wround "query fails 1" - 1 "$LOCAL" "boom"; stops "query fails 1: not yet" none; jqeq "query fails 1: flagged" '.watch.queryFailed' 'true'; jqeq "query fails 1: exit 0" '.exit' '0'
wround "query fails 2" - 7 "$LOCAL" "boom"; stops "query fails 2: not yet" none
wround "query fails 3" - 13 "$LOCAL" "boom"; stops "query fails 3 stops" query-failed
fresh; wround "unknown value 1" "$V_WEIRD" 1; wround "unknown value 2" "$V_WEIRD" 7; wround "unknown value 3" "$V_WEIRD" 13; stops "unknown value three times stops" query-failed
fresh; wround "fail, ok, fail" - 1 "$LOCAL" "boom"; wround "fail, ok, fail: ok" "$V_BASE" 7; wround "fail, ok, fail: fail" - 13 "$LOCAL" "boom"
wround "fail, ok, fail: fail again" - 19 "$LOCAL" "boom"; stops "a good round resets the count" none
fresh; wround "isCrossRepository missing" "$V_NOFLAG" 1; jqeq "isCrossRepository missing: a query failure" '.watch.queryFailed' 'true'
fresh; wround "comment without id" "$V_NOID" 1; jqeq "comment without id: a query failure" '.watch.queryFailed' 'true'
# limit
fresh; wround "a day later" "$V_PENDING" $((25 * 60)); stops "a day later stops" limit
fresh; node -e "const f='$WST', s=require(f); s.round=60; require('fs').writeFileSync(f, JSON.stringify(s))"
wround "sixtieth round" "$V_PENDING" 1; stops "sixtieth round stops" limit
# ready: never in the round a head is first seen
fresh; wround "base, first round" "$V_BASE" 1; stops "base, first round: grace" none; jqeq "base, first round: inGrace" '.watch.inGrace' 'true'
wround "base, second round" "$V_BASE" 6; stops "base, second round" ready
fresh; wround "seen comment r1" "$V_COMMENT" 1; ackall; wround "seen comment r2" "$V_COMMENT" 6; stops "a seen comment does not hold ready" ready
fresh; wround "no rollup r1" "$V_NOROLLUP" 1; stops "no rollup, first round: not ready" none
# needs-user
fresh; wround "thread r1" "$V_THREAD" 1; stops "thread r1: grace" none; wround "thread r2" "$V_THREAD" 6; stops "only a thread left" needs-user
fresh; wround "conflict r1" "$V_CONFLICT" 1; wround "conflict r2" "$V_CONFLICT" 6; stops "only a conflict left" needs-user
UNPUSHED='{"head":"'$H1'","headKnown":true,"headAllowed":true,"unpushed":1,"dirty":false}'
fresh; wround "fixed locally r1" "$V_RED" 1 "$UNPUSHED"; wround "fixed locally r2" "$V_RED" 6 "$UNPUSHED"
stops "fixed locally, not pushed" needs-user; jqeq "fixed locally: staleRemote" '.watch.staleRemote' 'true'; jqeq "fixed locally: no runs to act on" '.watch.failedRuns' '[]'
# no-progress: the skill gets one settled round to act, then two unchanged settled rounds stop
fresh; wround "red r1" "$V_RED" 1; stops "red r1: grace" none
wround "red r2" "$V_RED" 6 "$LOCAL" "" '{"runAttempts":{"77":2}}'; stops "red r2: one round to act" none
jqeq "red r2: run and attempt" '.watch.failedRuns' '[{"name":"security-review","runId":"77","attempt":2}]'
wround "red r3" "$V_RED" 16; stops "red, nothing changed" no-progress
fresh; wround "red2 r1" "$V_RED2" 1; wround "red2 r2" "$V_RED2" 6; wround "red2 r3" "$V_RED2" 16; stops "another red, nothing changed" no-progress
fresh; wround "red then other red r1" "$V_RED" 1; wround "r2" "$V_RED" 6; wround "r3 changes" "$V_RED2" 16; stops "a different failure is progress" none
# counter-cases
fresh; for n in 1 2 3 4 5; do wround "pending $n" "$V_PENDING" $((n * 5)); done
stops "pending five rounds" none; jqeq "pending: no progress counted" '.watch.noProgressRounds' '0'; jqeq "pending: unchanged counted" '.watch.unchangedRounds' '4'
fresh; wround "thread+comment r1" "$V_THREADCOMMENT" 1; wround "thread+comment r2" "$V_THREADCOMMENT" 6
stops "a new comment holds needs-user" none; jqeq "new comment listed" '.watch.newComments | length' '1'
fresh; wround "required check missing r1" "$V_MISSING" 1; wround "required check missing r2" "$V_MISSING" 6
stops "a missing required check is unsettled" none; jqeq "missing required: not settled" '.watch.settled' 'false'; jqeq "missing required: no runs" '.watch.failedRuns' '[]'
wround "required check missing r3" "$V_MISSING" 11; jqeq "missing required r3: still unsettled" '.watch.settled' 'false'
wround "required check missing r4" "$V_MISSING" 16; jqeq "missing required after the window: settled" '.watch.settled' 'true'
wround "required check missing r5" "$V_MISSING" 26; stops "missing required for good: no-progress" no-progress
# the window counts from the round a head is first seen, not from the start of the stretch
V_MISSING_H2=$(mkv missing-h2 "$(fixture wv-missing-h2 "$P.headRefOid = \"2222222222222222222222222222222222222222\"")" PR_CLOSEOUT_CONFIG="$tmp/req.json")
fresh; wround "pending, then a new head r1" "$V_PENDING" 1; wround "r2" "$V_PENDING" 6; wround "new head missing required r3" "$V_MISSING_H2" 11
wround "new head missing required r4" "$V_MISSING_H2" 16; wround "new head missing required r5" "$V_MISSING_H2" 21
jqeq "missing required: window from the head's first round" '.watch.settled' 'false'
# a second comment arriving after the first was triaged is progress, never no-progress
fresh; wround "comment then another r1" "$V_COMMENT" 1; wround "comment then another r2" "$V_COMMENT" 6; ackall
wround "comment then another r3" "$V_COMMENT2" 11; stops "a new comment is not no-progress" none
jqeq "the second comment is listed" '.watch.newComments | map(split(":")[1])' '["35"]'
fresh; wround "limit then restart" "$V_PENDING" $((25 * 60)); wstart 2026-11-26T02:00:00Z
wround "after restart" "$V_BASE" $((26 * 60 + 5)); stops "restart after limit" none; jqeq "restart: round 1" '.watch.round' '1'
fresh; wround "needs-user then restart r1" "$V_THREAD" 1; wround "r2" "$V_THREAD" 6; wstart 2026-11-25T00:10:00Z
wround "after restart r1" "$V_THREAD" 11; stops "restart after needs-user: grace" none
# comment keys: an edited review is new again, a blank review never is
fresh; wround "review r1" "$V_REVIEW1" 1; jqeq "review r1: one new" '.watch.newComments | length' '1'; ackall
wround "review r2 edited" "$V_REVIEW2" 6; jqeq "edited review is new" '.watch.newComments | length' '1'
fresh; wround "blank review r1" "$V_REVIEW1" 1; jqeq "blank review never listed" '[.watch.newComments[] | select(startswith("pulls/reviews:23:"))]' '[]'

# ── pr-watch Task 5: watch from the command line, with a real clone ──────────────────────────────
R5="$tmp/r5"; rm -rf "$R5"; git init -q -b main "$R5"
echo a > "$R5/a.txt"; git -C "$R5" add a.txt; $G -C "$R5" commit -q -m a
git -C "$R5" switch -q -c feat/x; echo b > "$R5/b.txt"; git -C "$R5" add b.txt; $G -C "$R5" commit -q -m b
H5=$(git -C "$R5" rev-parse HEAD); ST5="$R5/.claude/pr-watch.1.local.json"
FX5=$(fixture w5 "$P.headRefOid = \"$H5\"")
wcli() { local want=$1 label=$2 at=$3; shift 3; run_cli "$want" "$label" watch example/repo 1 --repo-dir "$R5" --fixture "${FX:-$FX5}" --now "$at" "$@"; }
run_cli 7 "watch before any start" watch example/repo 1 --repo-dir "$R5" --fixture "$FX5" --now 2026-11-25T00:00:00Z
if [ -e "$ST5" ]; then failed "[watch before any start] wrote a state"; else ok; fi
wcli 0 "watch --start" 2026-11-25T00:00:00Z --start
jqeq "start: round 1 in grace" '[.watch.round, .watch.inGrace, .watch.headAllowed, .watch.unpushed]' '[1,true,true,0]'
if [ -f "$ST5" ]; then ok; else failed "[watch --start] no state file"; fi
jqeq "start: ready's own exit kept" '.readyExit' '0'
cp "$ST5" "$tmp/st5"; wcli 7 "ten seconds later is too soon" 2026-11-25T00:00:10Z
if cmp -s "$ST5" "$tmp/st5"; then ok; else failed "[too soon] state changed"; fi
has "too soon: says so" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "too-soon"
wcli 8 "second round is ready" 2026-11-25T00:05:00Z
jqeq "second round: ready" '.watch.stop.reason' '"ready"'
jqeq "stateIgnored: no .gitignore" '.watch.stateIgnored' 'false'
cp "$ST5" "$tmp/st5"; wcli 7 "a tick after a stop" 2026-11-25T00:06:00Z
has "tick after a stop: says so" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "stopped"
if cmp -s "$ST5" "$tmp/st5"; then ok; else failed "[tick after a stop] state changed"; fi
wcli 0 "--start right after a stop" 2026-11-25T00:05:10Z --start
cp "$ST5" "$tmp/st5"; wcli 7 "--start while another session watches" 2026-11-25T00:05:20Z --start
has "--start while watched: too soon" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "too-soon"
if cmp -s "$ST5" "$tmp/st5"; then ok; else failed "[--start while watched] state changed"; fi
run_cli 7 "watch --start --stop" watch example/repo 1 --repo-dir "$tmp/r5none" --fixture "$FX5" --start --stop
run_cli 7 "watch-ack --stop" watch-ack example/repo 1 --repo-dir "$R5" --stop --comment "issues/comments:1:0123456789abcdef"
run_cli 0 "watch --stop" watch example/repo 1 --repo-dir "$R5" --fixture "$FX5" --stop
jqeq "watch --stop: inactive" '.watch.active' 'false'
if [ "$(jq -r '.active' "$ST5")" = false ]; then ok; else failed "[watch --stop] state still active"; fi
rm -rf "$tmp/r5none"; mkdir -p "$tmp/r5none"
run_cli 7 "watch --stop with nothing watched" watch example/repo 1 --repo-dir "$tmp/r5none" --stop
# another branch checked out: the clone says nothing about this PR
git -C "$R5" switch -q main; cp "$ST5" "$tmp/st5"
wcli 7 "wrong branch" 2026-11-25T00:10:00Z --start
has "wrong branch: says so" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "wrong-branch"
if cmp -s "$ST5" "$tmp/st5"; then ok; else failed "[wrong branch] state changed"; fi
git -C "$R5" switch -q feat/x
# a commit on top of the PR head: still allowed, one unpushed; a dirty tree shows
echo c > "$R5/c.txt"; git -C "$R5" add c.txt; $G -C "$R5" commit -q -m c; echo d > "$R5/d.txt"
# an untracked file (a triage or review result) is not a dirty tree: the fix commit names its files
wcli 0 "local commit on top" 2026-11-25T00:15:00Z --start
jqeq "local commit on top: allowed, one unpushed, untracked is clean" '[.watch.headAllowed, .watch.unpushed, .watch.dirty]' '[true,1,false]'
echo changed >> "$R5/a.txt"
wcli 0 "tracked change" 2026-11-25T00:16:00Z --start
jqeq "tracked change: dirty" '.watch.dirty' 'true'
git -C "$R5" checkout -q -- a.txt; git -C "$R5" add d.txt
wcli 0 "staged new file" 2026-11-25T00:17:00Z --start
jqeq "staged new file: dirty" '.watch.dirty' 'true'
git -C "$R5" rm -q --cached d.txt; rm -f "$R5/d.txt"
# a PR head this clone has never seen
FX=$(fixture w5-unknown "$P.headRefOid = \"2222222222222222222222222222222222222222\"") wcli 8 "unknown PR head" 2026-11-25T00:20:00Z --start
jqeq "unknown PR head: stops" '.watch.stop.reason' '"head-not-allowed"'
# a failed Actions run: its attempt comes from runs.json (the REST answer in fixture mode)
git -C "$R5" reset -q --hard "$H5"
FXR=$(fixture w5-red "$P.headRefOid = \"$H5\" | $CX[0].conclusion = \"FAILURE\" | $CX[0].detailsUrl = \"https://github.com/o/r/actions/runs/77/job/1\"")
printf '{"77":2}' > "$FXR/runs.json"
FX=$FXR wcli 0 "red r1" 2026-11-25T00:25:00Z --start
FX=$FXR wcli 0 "red r2" 2026-11-25T00:30:00Z
jqeq "red r2: attempt from runs.json" '.watch.failedRuns' '[{"name":"security-review","runId":"77","attempt":2}]'
printf '*.local.json\n' > "$R5/.gitignore"
wcli 0 "ignored state" 2026-11-25T00:35:00Z --start
jqeq "stateIgnored: ignored" '.watch.stateIgnored' 'true'

# ── pr-watch-state-ack-hardening: a state file this script cannot read ───────────────────────────
# Anything loadState cannot accept is refused as `foreign-state:` (exit 7) with the file untouched;
# only `watch --stop --force` may move it (below). The directory case is a path the script cannot read.
W7="$tmp/w7"; rm -rf "$W7"; mkdir -p "$W7/.claude"; ST7="$W7/.claude/pr-watch.1.local.json"
alien() { rm -rf "$ST7"; printf '%s' "$1" > "$ST7"; cp "$ST7" "$tmp/st7"; }   # a state the script must neither read nor touch
V2='{"version":2,"pr":1,"active":true,"seen":[]}'
OTHER_PR='{"version":1,"pr":2,"active":true,"startedAt":"2026-11-25T00:00:00Z","round":0,"seen":[],"headSeen":{},"noProgressRounds":0,"unchangedRounds":0,"queryFailures":0}'
for v in "version 2|$V2" 'not JSON|{' 'empty file|' 'whitespace|  ' 'null|null' 'array|[]' "other PR|$OTHER_PR"; do
  name=${v%%|*}; alien "${v#*|}"
  run_cli 7 "$name: --stop" watch example/repo 1 --repo-dir "$W7" --stop
  d=$(jq -r '.hits[0].detail' "$tmp/out.json")
  if [[ $d == "foreign-state:"* ]]; then ok; else failed "[$name: says foreign-state] does not start with foreign-state: $d"; fi
  has "$name: names --force" "$d" "--stop --force"
  has "$name: names the upgrade" "$d" "upgrade the plugin"
  if cmp -s "$ST7" "$tmp/st7"; then ok; else failed "[$name: refused, file untouched] changed"; fi
done
rm -rf "$ST7"; mkdir "$ST7"
run_cli 7 "a directory: --stop" watch example/repo 1 --repo-dir "$W7" --stop
has "a directory: says foreign-state" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "foreign-state:"
if [ -d "$ST7" ]; then ok; else failed "[a directory: left alone]"; fi
rm -rf "$ST7"
foreign_case() {   # <label> <args…>: refused as foreign-state, the file as it was
  local label=$1; shift
  run_cli 7 "$label" "$@"
  has "$label: says foreign-state" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "foreign-state:"
  if cmp -s "$ST7" "$tmp/st7"; then ok; else failed "[$label: file untouched] changed"; fi
}
alien "$V2"
foreign_case "version 2: --start" watch example/repo 1 --repo-dir "$W7" --fixture "$FX5" --start
foreign_case "version 2: a round" watch example/repo 1 --repo-dir "$W7" --fixture "$FX5" --now 2026-11-25T00:40:00Z
foreign_case "version 2: watch-ack" watch-ack example/repo 1 --repo-dir "$W7" --comment "issues/comments:1:0123456789abcdef"

# `watch --stop --force` moves such a file aside, in the same directory, under a name the guard's glob misses
NOW7=2026-11-25T00:40:00Z; MOVED7="$W7/.claude/foreign-pr-watch.1.20261125T004000Z.local.json"
force() { run_cli "$1" "$2" watch example/repo 1 --repo-dir "$W7" --now "$NOW7" --stop --force; }   # <want exit> <label>
moved_case() {   # <label> <state text>: moved aside, bytes kept, reported
  local label=$1; alien "$2"; rm -f "$MOVED7"
  force 0 "$label"
  if [ -f "$MOVED7" ]; then ok; else failed "[moved name: foreign-pr-watch.1.20261125T004000Z.local.json missing for $label] $(ls "$W7/.claude" | tr '\n' ' ')"; fi
  if [ ! -e "$ST7" ] && cmp -s "$MOVED7" "$tmp/st7"; then ok; else failed "[$label: original gone, copy identical]"; fi
  jqeq "$label: reports it" '.watch.movedAside' "\"${MOVED7//\/\//\/}\"" # path.join collapses the // that a TMPDIR ending in / leaves
  jqeq "$label: inactive" '.watch.active' 'false'
  rm -f "$MOVED7"
}
moved_case "--force moves a version 2 state aside" "$V2"
moved_case "not JSON: moved aside" '{'
moved_case "empty file: moved aside" ''
moved_case "other PR: moved aside" "$OTHER_PR"
rm -rf "$ST7"; mkdir "$ST7"; rm -rf "$MOVED7"
force 0 "a directory: moved aside"
if [ -d "$MOVED7" ] && [ ! -e "$ST7" ]; then ok; else failed "[a directory: moved aside, original gone]"; fi
rm -rf "$MOVED7"
b7=$(basename "$(jq -r '.watch.movedAside' "$tmp/out.json")")   # the name the script reported, not this suite's constant
if [[ $b7 == pr-watch.*.local.json ]]; then failed "[moved name: inside the guard's glob]"; else ok; fi
if [[ $b7 == *.local.json ]]; then ok; else failed "[moved name: outside *.local.json]"; fi
# a state this script can read is only stopped: it stays, and what was seen stays
alien '{"version":1,"pr":1,"active":true,"startedAt":"2026-11-25T00:00:00Z","round":3,"seen":["issues/comments:1:0123456789abcdef"],"headSeen":{},"noProgressRounds":0,"unchangedRounds":0,"queryFailures":0}'
force 0 "readable state: --force is a plain stop"
if [ -f "$ST7" ] && [ ! -e "$MOVED7" ]; then ok; else failed "[readable state: stays in place]"; fi
if [ "$(jq -c '[.active, .seen]' "$ST7")" = '[false,["issues/comments:1:0123456789abcdef"]]' ]; then ok; else failed "[readable state: stopped, seen kept] $(cat "$ST7")"; fi
jqeq "readable state: nothing moved" '.watch.movedAside // "none"' '"none"'
# --force belongs to watch --stop alone (a readable state, so a wrongly accepted flag would show)
alien '{"version":1,"pr":1,"active":true,"startedAt":"2026-11-25T00:00:00Z","round":3,"seen":[],"headSeen":{},"noProgressRounds":0,"unchangedRounds":0,"queryFailures":0}'
run_cli 7 "--force with watch-ack" watch-ack example/repo 1 --repo-dir "$W7" --force --comment "issues/comments:1:0123456789abcdef"
has "--force with watch-ack: says so" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "--force is for watch --stop only"
if cmp -s "$ST7" "$tmp/st7"; then ok; else failed "[--force with watch-ack: state untouched] changed"; fi
run_cli 7 "--force with --start" watch example/repo 1 --repo-dir "$W7" --fixture "$FX5" --now "$NOW7" --start --force
has "--force with --start: says so" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "--force is for watch --stop only"
run_cli 7 "--force with ready" ready example/repo 1 --fixture "$BASE" --force
has "--force with ready: says so" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "--force is for watch --stop only"
run_cli 7 "--force with landed" landed example/repo 1 --expect-head 0000000000000000000000000000000000000000 --repo-dir "$W7" --force
has "--force with landed: says so" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "--force is for watch --stop only"
run_cli 7 "--force without --stop" watch example/repo 1 --repo-dir "$W7" --fixture "$FX5" --now "$NOW7" --force
has "--force without --stop: says so" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "--force is for watch --stop only"
# --start and --stop together are refused before anything is read or moved, foreign state or not
alien "$V2"
run_cli 7 "--start --stop --force on a foreign state" watch example/repo 1 --repo-dir "$W7" --now "$NOW7" --start --stop --force
has "--start --stop --force on a foreign state: says so" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "--start and --stop together"
if cmp -s "$ST7" "$tmp/st7" && [ ! -e "$MOVED7" ]; then ok; else failed "[--start --stop --force on a foreign state: nothing moved]"; fi
# the destination is never overwritten
alien "$V2"; printf 'taken' > "$MOVED7"
force 7 "dest exists: refused"
if cmp -s "$ST7" "$tmp/st7" && [ "$(cat "$MOVED7")" = taken ]; then ok; else failed "[dest exists: nothing changed]"; fi
rm -f "$MOVED7"
alien "$V2"; ln -s "$W7/nowhere" "$MOVED7"   # a dangling symlink is an entry too: fs.existsSync follows it and says no
force 7 "dest is a dangling symlink: refused"
if cmp -s "$ST7" "$tmp/st7" && [ -L "$MOVED7" ]; then ok; else failed "[dest is a dangling symlink: nothing changed]"; fi
rm -f "$MOVED7"
# nothing to move
rm -rf "$ST7"
force 7 "no state file: --force"
has "no state file: --force: not-started" "$(jq -r '.hits[0].detail' "$tmp/out.json")" "not-started"
# the real guard: it blocks on the foreign state, and lets go once --force has moved it
G7() {
  local out rc
  out=$(jq -cn --arg c 'gh pr comment 1 -b x' '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$W7" bash "$here/../hooks/pr-watch-guard.sh" 2>/dev/null); rc=$?
  if [ "$rc" = 2 ] || [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" = deny ]; then echo deny; else echo allow; fi
}
alien "$V2"; rm -f "$MOVED7"
if [ "$(G7)" = deny ]; then ok; else failed "[guard: blocks before --force]"; fi
force 0 "guard wiring: --force"
if [ "$(G7)" = allow ]; then ok; else failed "[guard: allows after --force]"; fi
rm -f "$MOVED7"

# ── summary and mutants ──────────────────────────────────────────────────────────────────────────
MIN_PASS=300
if [ "$pass" -lt "$MIN_PASS" ] && [ "${STOP_ON_FAIL:-0}" != 1 ]; then failed "only $pass checks passed, expected at least $MIN_PASS"; fi
echo "pr-closeout: $pass passed, $fail failed"

mut_bad=0; mut_n=0
# Each mutant is a run of this whole suite on a mutated copy. They run side by side, MUT_JOBS at a time
# (the machine's processors, at most 8; MUT_JOBS=1 for one after another), and a run leaves only its log
# and exit status: all are judged after the last one ends, in the order they are listed below.
MUT_JOBS=${MUT_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null)}
[[ $MUT_JOBS =~ ^[1-9][0-9]*$ ]] || MUT_JOBS=2
[ "$MUT_JOBS" -le 8 ] || MUT_JOBS=8
mut_labels=(); mut_wants=()
mutant() {   # <label> <substring of the case that must kill it> <perl substitution>: starts the run
  local label=$1 m="$tmp/mutant-$1.mjs"
  perl -pe "$3" "$SCRIPT" > "$m" || { echo "MUTANT [$label] perl failed"; mut_bad=1; return; }
  if cmp -s "$m" "$SCRIPT"; then echo "MUTANT [$label] substitution did not apply"; mut_bad=1; return; fi
  while [ "$(jobs -rp | wc -l)" -ge "$MUT_JOBS" ]; do sleep 0.1; done
  mut_labels+=("$label"); mut_wants+=("$2")
  ( SCRIPT="$m" NO_MUTANTS=1 STOP_ON_FAIL=1 bounded 300 bash "$0" > "$tmp/mutant-$label.log" 2>&1
    echo $? > "$tmp/mutant-$label.rc" ) &
}
mutants_judged() {   # waits for every run started above, then judges each
  local i label want rc first
  wait
  for i in "${!mut_labels[@]}"; do
    label=${mut_labels[$i]}; want=${mut_wants[$i]}
    rc=$(cat "$tmp/mutant-$label.rc" 2>/dev/null || echo none)
    mut_n=$((mut_n + 1))
    first=$(command grep -a -m1 '^FAIL' "$tmp/mutant-$label.log")   # -a: a truncated multibyte char must not make GNU grep call the log binary
    if [ "$rc" = 0 ]; then echo "MUTANT [$label] suite stayed green"; mut_bad=1
    elif [ "$rc" = none ]; then echo "MUTANT [$label] run left no exit status"; mut_bad=1
    elif [ -z "$first" ]; then echo "MUTANT [$label] crashed before any case failed"; mut_bad=1
    elif [[ $first != *"$want"* ]]; then echo "MUTANT [$label] killed by [${first:0:90}], expected [$want]"; mut_bad=1
    else echo "mutant [$label]: suite red as required (by [$want])"; fi
  done
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
  mutant required      "[required missing: security-review]" "s/if \(missing\.length\) hits\.push/if (false) hits.push/"
  mutant min-seconds   "[suspected skip: named]"           "s/seconds\(c\) < min/seconds(c) < 0/"
  mutant config-error  "[config not JSON]"                 "s/if \(config && config\.error\) hits\.push/if (false) hits.push/"
  mutant precedent     "[precedent squash: method]"        "s/parents === 1 \? 'squash' : parents === 2 \? 'merge'/parents === 1 ? 'merge' : parents === 2 ? 'squash'/"
  mutant rollup-field   "[rollup field missing]"            "s/if \(r !== null && typeof r !== 'object'\) unknown/if (false) unknown/"
  mutant mode-norm     "[executable bit added after the review]" "s/if \(mode === '100755'\) return/if (false) return/"
  mutant docs-exempt   "[only a document changed after the review]" "s/if \(DOC_PATH\.test\(file\) && !NOT_DOC_PATH\.test\(file\)\) out\.docsOnly/if (false) out.docsOnly/"
  mutant reason-req    "[accepted without a reason]"       "s/if \(!p \|\| !reason\) throw/if (!p) throw/"
  mutant branch-check  "[other branch: unknown]" "s/state\.branch !== headRefName\) return/false) return/"
  mutant accept-any    "[accepting another file does not cover this one]" "s/accept\.find\(\(a\) => a\.path === file\)/accept[0]/"
  mutant archive-excl  "[archived only: none]"             "s/m && m\[1\] !== 'archive'/m/"
  mutant verify-read   "[unarchived: verify read]"         "s/if \(r\.status === 0 \|\| r\.status === 3\) verify/if (false) verify/"
  mutant tip-ancestor  "[merged, head matches, on base]"   "s/\['merge-base', '--is-ancestor', mc,/['merge-base', '--is-ancestor', pull.head.sha,/"
  mutant remote-left   "[remote still there: where]"       "s/remote: ls\.out\.trim\(\) !== ''/remote: false/"
  mutant open-pulls    "[an open PR on the branch]"        "s/\[open\.length && /[0 && /"
  mutant not-merged    "[not merged]"                      "s/if \(!pull\.merged_at\) gate/if (false) gate/"
  mutant settled       "[skipped as unchanged since an earlier round]" "s/\(f\.status === 'reviewed' \|\| \(f\.status === 'skipped' && Number\.isInteger\(f\.unchangedSince\)\)\)/f.status === 'reviewed'/"
  mutant not-doc       "[a skill file is not a document]" "s/DOC_PATH\.test\(file\) && !NOT_DOC_PATH\.test\(file\)/DOC_PATH.test(file)/"
  mutant deadline      "[deadline]"                        "s/, timeout: left, killSignal: 'SIGKILL'//"
  mutant link-norm     "[symlink recorded as link:]"       "s/if \(mode === '120000'\) return/if (false) return/"
  mutant verify-time   "[verify hangs: unavailable]"       "s/, timeout: verifyLeft\(\), killSignal: 'SIGKILL'//"
  mutant deletions     "[a deletion the review never saw]" "s/const changed = git\(repoDir, \['diff', '--name-only', '-z', /const changed = git(repoDir, ['diff', '--name-only', '-z', '--diff-filter=d', /"
  # pr-watch: each rule of watchVerdict dies on the case written for it
  mutant w-limit       "[a day later stops]"               "s/if \(now - Date\.parse\(s\.startedAt\) > LIMIT_MS \|\| s\.round >= LIMIT_ROUNDS\)/if (false)/"
  mutant w-pending     "[pending five rounds]"             "s/w\.settled && unchanged \? s\.noProgressRounds/unchanged ? s.noProgressRounds/"
  mutant w-grace       "[base, first round: grace]"        "s/w\.inGrace = s\.headSeen\[verdict\.head\] === w\.round;/w.inGrace = false;/"
  mutant w-stale       "[fixed locally, not pushed]"       "s/w\.staleRemote = w\.unpushed > 0;/w.staleRemote = false;/"
  mutant w-hash        "[edited review is new]"            's/\$\{i\.endpoint\}:\$\{i\.id\}:\$\{i\.bodyHash\}/\${i.endpoint}:\${i.id}:x/'
  mutant w-queries     "[query fails 1: not yet]"          "s/QUERY_FAILURES_TO_STOP = 3;/QUERY_FAILURES_TO_STOP = 1;/"
  mutant w-required    "[missing required: not settled]" "s/REQUIRED_MISSING_ROUNDS && hits\.some/REQUIRED_MISSING_ROUNDS && false \&\& hits.some/"
  mutant w-progress    "[red r2: one round to act]"        "s/NO_PROGRESS_TO_STOP = 2;/NO_PROGRESS_TO_STOP = 1;/"
  mutant w-head        "[head not in the clone stops]"     "s/w\.headAllowed = !!\(local && local\.headKnown && local\.headAllowed\);/w.headAllowed = true;/"
  mutant w-untracked  "[local commit on top: allowed, one unpushed, untracked is clean]" "s/, '--untracked-files=no'\]/]/"
  mutant w-stopped     "[a tick after a stop]"             "s/else if \(!s\.active\) throw/else if (false) throw/"
  mutant w-stop        "[watch --stop]"                    "s/  if \(o\.stop\) \{/  if (false) {/"
  mutant w-soon-start  "[--start while another session watches]" "s/const tooSoon = s && s\.active &&/const tooSoon = !o.start \&\& s \&\& s.active \&\&/"
  mutant w-req-head    "[missing required: window from the head's first round]" "s/w\.round - s\.headSeen\[verdict\.head\] < REQUIRED_MISSING_ROUNDS/w.round - 1 < REQUIRED_MISSING_ROUNDS/"
  mutant w-start-stop  "[watch --start --stop]"            "s/  if \(o\.start && o\.stop\) throw/  if (false) throw/"
  mutant w-req-window  "[missing required after the window: settled]" "s/w\.round - s\.headSeen\[verdict\.head\] < REQUIRED_MISSING_ROUNDS && //"
  mutant w-keys        "[a new comment is not no-progress]" "s/\[\.\.\.w\.newComments\]\.sort\(\)\]/w.newComments.length]/"
  # an unreadable state: refused as foreign-state, moved aside only by watch --stop --force
  mutant f-class       "[--force moves a version 2 state aside]" "s/e instanceof ForeignStateError/false/"
  mutant f-overwrite   "[dest exists: refused]"            "s/if \(taken\) throw/if (false) throw/"
  mutant f-prefix      "[moved name: foreign-pr-watch"     "s/foreign-pr-watch\./pr-watch.foreign./"
  mutant f-usage       "[--force with --start: says so]" "s/if \(o\.force && !\(o\.cmd === 'watch' && o\.stop\)\) throw/if (false) throw/"
  mutant f-usage-cmd   "[--force with ready: says so]"    "s/if \(flag === '--force' && cmd !== 'watch'\) throw/if (false) throw/"
  mutant f-json        "[not JSON: says foreign-state]"    "s/throw foreign\(file, 'not JSON'\)/throw new QueryError('x')/"
  mutants_judged
  MUT_WANT_N=61
  if [ "$mut_n" != "$MUT_WANT_N" ]; then echo "FAIL: $mut_n of $MUT_WANT_N mutants ran"; mut_bad=1; fi
  [ "$mut_bad" = 0 ] || fail=$((fail + 1))
fi
[ "$fail" = 0 ]

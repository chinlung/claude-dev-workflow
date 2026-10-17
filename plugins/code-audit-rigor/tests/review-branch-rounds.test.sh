#!/bin/bash
# code-audit-rigor: review-branch-rounds.cjs (plan / annotate) and resolve-rules.cjs tests
# 用法：bash plugins/code-audit-rigor/tests/review-branch-rounds.test.sh
# 消費者：提交前手跑 + CI（.github/workflows/validate.yml）+ 本地 PostToolUse hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$SCRIPT_DIR/.."
ROUNDS="$PLUGIN/scripts/review-branch-rounds.cjs"
RULES="$PLUGIN/scripts/resolve-rules.cjs"
VALIDATOR="$PLUGIN/validators/validate-review-branch-results.cjs"
FIXTURES="$PLUGIN/tests/fixtures/code-audit-rigor"
PASS=0; FAIL=0

# 帶模板：無模板的 mktemp -d 在 macOS 會落到 /var/folders/…，sandbox 只准寫 $TMPDIR
TMPBASE="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "${TMPBASE%/}/review-branch-rounds-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# ---- helpers ----
check() {        # check <name> <actual> <expected substring (grep BRE)>
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — got: $2"; fi
}
check_eq() {     # check_eq <name> <actual> <expected exact>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected [$3], got [$2]"; fi
}
check_flag() {   # check_flag <name> <path> <exists|absent>
  if [ "$3" = exists ] && [ -e "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  elif [ "$3" = absent ] && [ ! -e "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — flag state wrong: $2"; fi
}
# jget <json file> <dotted path> → scalar as text, object/array as compact JSON, "undefined" when absent
jget() {
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const v = process.argv[2].split(".").reduce((a, k) => (a == null ? a : a[k]), j);
    console.log(v === undefined ? "undefined" : (typeof v === "object" ? JSON.stringify(v) : String(v)));
  ' "$1" "$2"
}
# rc <cmd…> → prints the exit status without tripping set -e
rc() { local s=0; "$@" >/dev/null 2>"$WORK/stderr.txt" || s=$?; echo "$s"; }

REPO="$WORK/repo"
G() { git -C "$REPO" -c core.fsmonitor=false -c user.email=t@t.t -c user.name=t -c commit.gpgsign=false "$@"; }

# ---- fixture repo: base commit, a branch commit that changes a.ts line 2, an untracked c.ts ----
mkdir -p "$REPO/src"
git -C "$REPO" init -q 2>/dev/null
G config core.fsmonitor false 2>/dev/null
printf 'l1\nl2\nl3\n' > "$REPO/src/a.ts"
printf 'x\n' > "$REPO/src/b.ts"
printf 'BIN\0v1\n' > "$REPO/img.bin"          # a real binary: git shows "-" in --numstat and prints no hunk
G add src/a.ts src/b.ts img.bin
G commit -q -m base
BASE=$(G rev-parse HEAD)
G checkout -q -b feature/x
printf 'l1\nL2 changed\nl3\n' > "$REPO/src/a.ts"
printf 'BIN\0v2\n' > "$REPO/img.bin"
G commit -q -am "change a and the binary"
printf 'new\n' > "$REPO/src/c.ts"
printf 'src/a.ts\nsrc/c.ts\n' > "$WORK/files.txt"
R="$REPO/review-branch-results.json"

echo "== plan: round 1 (no previous results)"
node "$ROUNDS" plan --root "$REPO" --base "$BASE" --files "$WORK/files.txt" > "$WORK/plan1.json"
check_eq "plan r1: round is 1" "$(jget "$WORK/plan1.json" round)" 1
check_eq "plan r1: scopeMode full" "$(jget "$WORK/plan1.json" scopeMode)" full
check_eq "plan r1: nothing unchanged" "$(jget "$WORK/plan1.json" unchanged)" "[]"
check_eq "plan r1: nothing dismissed" "$(jget "$WORK/plan1.json" dismissed)" "[]"
check "plan r1: blob is a 40-hex object id" "$(jget "$WORK/plan1.json" files.0.blob)" '^[0-9a-f]\{40\}$'
check_flag "plan r1: plan file lands in the git dir" "$REPO/.git/review-branch-plan.json" exists

echo "== annotate: round 1"
cat > "$R" <<'EOF'
{ "branch": "feature/x",
  "scopedFiles": [ {"file":"src/a.ts","status":"reviewed","source":"committed"},
                   {"file":"src/c.ts","status":"reviewed","source":"untracked"} ],
  "suggestions": [
    {"file":"src/a.ts","line":2,"quotedCode":"L2 changed","description":"on the changed line","severity":"LOW"},
    {"file":"src/a.ts","line":1,"quotedCode":"l1","description":"pre-existing line","severity":"LOW"},
    {"file":"src/c.ts","line":1,"quotedCode":"new","description":"untracked file","severity":"LOW"},
    {"file":"img.bin","line":1,"quotedCode":"BIN","description":"modified binary","severity":"LOW"} ],
  "verifications": [ {"id":"V-001","verdict":"PASS","suggestion":0},
                     {"id":"V-002","verdict":"FAIL","suggestion":1},
                     {"id":"V-003","verdict":"PASS","suggestion":2},
                     {"id":"V-004","verdict":"SKIP","suggestion":3} ] }
EOF
check_eq "validator rejects a results file that was never annotated (introduced missing)" "$(rc node "$VALIDATOR" "$R")" 1
check_eq "annotate r1 exits 0" "$(rc node "$ROUNDS" annotate "$R" --root "$REPO" --base "$BASE")" 0
check_eq "annotate r1: changed line → introduced" "$(jget "$R" suggestions.0.introduced)" true
check_eq "annotate r1: untouched line of a changed file → pre-existing" "$(jget "$R" suggestions.1.introduced)" false
check_eq "annotate r1: untracked file → introduced" "$(jget "$R" suggestions.2.introduced)" true
check_eq "annotate r1: modified binary (no text hunk) → introduced" "$(jget "$R" suggestions.3.introduced)" true
check_eq "annotate r1: round recorded" "$(jget "$R" round)" 1
check_eq "annotate r1: scopeMode recorded" "$(jget "$R" scopeMode)" full
check_eq "annotate r1: this round's FAIL becomes dismissed" "$(jget "$R" dismissed.0.quotedCode)" l1
check_eq "annotate r1: dismissed carries the round" "$(jget "$R" dismissed.0.round)" 1
check_eq "annotate r1: exactly one dismissed" "$(jget "$R" dismissed.length)" 1
check "annotate r1: scoped file gets a blob" "$(jget "$R" scopedFiles.1.blob)" '^[0-9a-f]\{40\}$'
check_eq "validator accepts the annotated file" "$(rc node "$VALIDATOR" "$R")" 0

echo "== plan: round 2 with nothing changed since round 1"
node "$ROUNDS" plan --root "$REPO" --base "$BASE" --files "$WORK/files.txt" > "$WORK/plan2.json"
check_eq "plan r2: round is 2" "$(jget "$WORK/plan2.json" round)" 2
check_eq "plan r2: scopeMode since-last" "$(jget "$WORK/plan2.json" scopeMode)" since-last
check_eq "plan r2: both files unchanged" "$(jget "$WORK/plan2.json" unchanged)" '["src/a.ts","src/c.ts"]'
check_eq "plan r2: the two PASS suggestions are carried" "$(jget "$WORK/plan2.json" carried.length)" 2
check_eq "plan r2: carried keeps its round" "$(jget "$WORK/plan2.json" carried.0.round)" 1
check_eq "plan r2: dismissed carried forward" "$(jget "$WORK/plan2.json" dismissed.0.quotedCode)" l1

echo "== plan: --full ignores unchanged files but keeps the round count"
node "$ROUNDS" plan --root "$REPO" --base "$BASE" --files "$WORK/files.txt" --full > "$WORK/plan2f.json"
check_eq "plan --full: round still 2" "$(jget "$WORK/plan2f.json" round)" 2
check_eq "plan --full: scopeMode full" "$(jget "$WORK/plan2f.json" scopeMode)" full
check_eq "plan --full: nothing skipped" "$(jget "$WORK/plan2f.json" unchanged)" "[]"
check_eq "plan --full: dismissed still carried" "$(jget "$WORK/plan2f.json" dismissed.length)" 1

echo "== plan: round 2 after c.ts changed"
printf 'new2\n' > "$REPO/src/c.ts"
node "$ROUNDS" plan --root "$REPO" --base "$BASE" --files "$WORK/files.txt" > "$WORK/plan2b.json"
check_eq "plan r2b: only a.ts unchanged" "$(jget "$WORK/plan2b.json" unchanged)" '["src/a.ts"]'
check_eq "plan r2b: only the a.ts PASS is carried" "$(jget "$WORK/plan2b.json" carried.length)" 1
check_eq "plan r2b: carried is the a.ts suggestion" "$(jget "$WORK/plan2b.json" carried.0.quotedCode)" "L2 changed"

echo "== annotate: refuses to write a results file that re-posts a dismissed anchor"
cat > "$R" <<'EOF'
{ "branch": "feature/x",
  "scopedFiles": [ {"file":"src/a.ts","status":"skipped","skipReason":"unchanged since r1 (blob match)","source":"committed"},
                   {"file":"src/c.ts","status":"reviewed","source":"untracked"} ],
  "suggestions": [ {"file":"src/a.ts","line":1,"quotedCode":"l1","description":"same old","severity":"LOW"} ],
  "verifications": [ {"id":"V-001","verdict":"PASS","suggestion":0} ] }
EOF
check_eq "annotate repost: exit 1" "$(rc node "$ROUNDS" annotate "$R" --root "$REPO" --base "$BASE")" 1
check "annotate repost: names the problem" "$(cat "$WORK/stderr.txt")" 'dismissed in an earlier round'
check_eq "annotate repost: file left without introduced (not written)" "$(jget "$R" suggestions.0.introduced)" undefined

echo "== annotate: round 2 proper"
cat > "$R" <<'EOF'
{ "branch": "feature/x",
  "scopedFiles": [ {"file":"src/a.ts","status":"skipped","skipReason":"unchanged since r1 (blob match)","source":"committed"},
                   {"file":"src/c.ts","status":"reviewed","source":"untracked"} ],
  "suggestions": [ {"file":"src/c.ts","line":1,"quotedCode":"new2","description":"fresh","severity":"LOW","class":"naming"} ],
  "verifications": [ {"id":"V-001","verdict":"FAIL","suggestion":0} ] }
EOF
check_eq "annotate r2 exits 0" "$(rc node "$ROUNDS" annotate "$R" --root "$REPO" --base "$BASE")" 0
check_eq "annotate r2: round 2" "$(jget "$R" round)" 2
check_eq "annotate r2: scopeMode since-last" "$(jget "$R" scopeMode)" since-last
check_eq "annotate r2: dismissed = earlier + this round" "$(jget "$R" dismissed.length)" 2
check_eq "annotate r2: this round's FAIL tagged round 2" "$(jget "$R" dismissed.1.round)" 2
check_eq "annotate r2: carried comes from the plan" "$(jget "$R" carried.length)" 1
check_eq "annotate r2: the plan's unchanged file is flagged with the round that settled it" "$(jget "$R" scopedFiles.0.unchangedSince)" 1
check_eq "annotate r2: a reviewed file carries no flag" "$(jget "$R" scopedFiles.1.unchangedSince)" undefined
check_eq "validator accepts round 2" "$(rc node "$VALIDATOR" "$R")" 0

echo "== plan: round 3 — a file skipped as unchanged in round 2 stays unchanged, and its carried finding survives"
# round 2 recorded a.ts as skipped (unchanged since r1) and the plan flagged it; nothing changed since. Round 3
# must still see a.ts as unchanged and keep carrying the round-1 PASS on it — otherwise files alternate between
# skipped and re-reviewed every other round, and verified-but-unfixed findings vanish on the third round.
node "$ROUNDS" plan --root "$REPO" --base "$BASE" --files "$WORK/files.txt" > "$WORK/plan3.json"
check_eq "plan r3: round is 3" "$(jget "$WORK/plan3.json" round)" 3
check_eq "plan r3: a.ts (flagged skip) and c.ts (reviewed in r2) are both unchanged" "$(jget "$WORK/plan3.json" unchanged)" '["src/a.ts","src/c.ts"]'
check_eq "plan r3: the round-1 PASS on a.ts is still carried" "$(jget "$WORK/plan3.json" carried.0.quotedCode)" "L2 changed"
check_eq "plan r3: carried keeps its original round" "$(jget "$WORK/plan3.json" carried.0.round)" 1
check_eq "plan r3: both dismissed anchors carried forward" "$(jget "$WORK/plan3.json" dismissed.length)" 2

echo "== annotate: the unchanged flag is the plan's fact, not the reviewer's sentence"
# A skip that claims "unchanged since …" for a file the plan did not report is refused: otherwise a file nobody
# reviewed could be skipped on every later round on the strength of a sentence.
cat > "$R" <<'EOF'
{ "branch": "feature/x",
  "scopedFiles": [ {"file":"src/a.ts","status":"skipped","skipReason":"unchanged since r2 (blob match)","source":"committed"},
                   {"file":"src/c.ts","status":"reviewed","source":"untracked"},
                   {"file":"src/b.ts","status":"skipped","skipReason":"unchanged since r2 (blob match)","source":"committed"} ],
  "suggestions": [], "verifications": [] }
EOF
check_eq "annotate refuses a false unchanged claim (b.ts is not in the plan's unchanged)" "$(rc node "$ROUNDS" annotate "$R" --root "$REPO" --base "$BASE" --plan "$WORK/plan3.json")" 1
check "annotate false claim: names the problem" "$(cat "$WORK/stderr.txt")" 'plan did not report them unchanged'
# A file skipped for another reason but reported unchanged by the plan is flagged anyway: the fact wins the text.
cat > "$R" <<'EOF'
{ "branch": "feature/x",
  "scopedFiles": [ {"file":"src/a.ts","status":"skipped","skipReason":"unchanged since r2 (blob match)","source":"committed"},
                   {"file":"src/c.ts","status":"skipped","skipReason":"docs only, no logic","source":"untracked"} ],
  "suggestions": [], "verifications": [] }
EOF
check_eq "annotate r3 exits 0" "$(rc node "$ROUNDS" annotate "$R" --root "$REPO" --base "$BASE" --plan "$WORK/plan3.json")" 0
check_eq "annotate r3: flag records the round that last settled the file" "$(jget "$R" scopedFiles.0.unchangedSince)" 2
check_eq "annotate r3: a plan-unchanged file skipped for another reason is still flagged" "$(jget "$R" scopedFiles.1.unchangedSince)" 2

echo "== validator: fixtures for the round memory"
check_eq "fixture round2 is VALID (same-round dismissed anchor is not a re-post)" "$(rc node "$VALIDATOR" "$FIXTURES/review-branch-valid-round2.json")" 0
check_eq "fixture reposted-dismissed is INVALID" "$(rc node "$VALIDATOR" "$FIXTURES/review-branch-invalid-reposted-dismissed.json")" 1
check "fixture reposted-dismissed: message names the round" "$(cat "$WORK/stderr.txt")" 'dismissed in round 1'

echo "== resolve-rules: layers and risk tier"
mkdir -p "$REPO/.reviewrules" "$REPO/src/auth" "$REPO/src/billing" "$REPO/.github/workflows"
cat > "$REPO/.reviewrules/manifest.json" <<'EOF'
{ "rules": [ { "pattern": "**/*.ts", "doc": "ts.md" } ],
  "risk":  [ { "pattern": "**/billing/**", "tier": "deep", "why": "money" },
             { "pattern": "**/auth/legacy-*.ts", "tier": "standard", "why": "frozen, reviewed 2026-01" } ] }
EOF
printf 'src/auth/login.ts\nsrc/auth/legacy-shim.ts\nsrc/billing/x.ts\nREADME.md\n.github/workflows/ci.yml\n' > "$WORK/rfiles.txt"
rm -f "$REPO/.git/review-branch-rules.json"
node "$RULES" --root "$REPO" --files "$WORK/rfiles.txt" --user-manifest "$WORK/no-such-manifest.json" > "$WORK/rules.json"
check_eq "rules: .ts resolves to the project layer" "$(jget "$WORK/rules.json" files.0.layer)" project
check "rules: project doc path is absolute under .reviewrules" "$(jget "$WORK/rules.json" files.0.doc)" '/\.reviewrules/ts\.md$'
check_eq "rules: README falls through to built-in default" "$(jget "$WORK/rules.json" files.3.layer)" built-in
check "rules: built-in default doc" "$(jget "$WORK/rules.json" files.3.doc)" 'rule_docs/default\.md$'
check_eq "risk: auth path is deep (built-in)" "$(jget "$WORK/rules.json" files.0.risk.tier)" deep
check_eq "risk: project override to standard wins over built-in deep" "$(jget "$WORK/rules.json" files.1.risk.tier)" standard
check_eq "risk: project deep entry" "$(jget "$WORK/rules.json" files.2.risk.layer)" project
check_eq "risk: README standard" "$(jget "$WORK/rules.json" files.3.risk.tier)" standard
check_eq "risk: CI workflow deep" "$(jget "$WORK/rules.json" files.4.risk.tier)" deep
check_eq "risk: review tier deep with 3 hits" "$(jget "$WORK/rules.json" risk.hits.length)" 3
check_flag "rules: file written to the git dir" "$REPO/.git/review-branch-rules.json" exists

echo "== resolve-rules: --no-write and glob edge cases"
rm -f "$REPO/.git/review-branch-rules.json"
printf 'Dockerfile.prod\ndeploy/k8s/app.yaml\nsrc/design.ts\n' > "$WORK/rfiles2.txt"
node "$RULES" --root "$REPO" --files "$WORK/rfiles2.txt" --user-manifest "$WORK/no-such-manifest.json" --no-write > "$WORK/rules2.json"
check_flag "rules --no-write: nothing written" "$REPO/.git/review-branch-rules.json" absent
check_eq "glob: top-level Dockerfile* matches **/Dockerfile*" "$(jget "$WORK/rules2.json" files.0.risk.tier)" deep
check_eq "glob: {deploy,…}/** matches a nested path" "$(jget "$WORK/rules2.json" files.1.risk.tier)" deep
check_eq "glob: a plain source file is standard" "$(jget "$WORK/rules2.json" files.2.risk.tier)" standard

echo "== annotate embeds risk from resolve-rules when present"
node "$RULES" --root "$REPO" --files "$WORK/rfiles.txt" --user-manifest "$WORK/no-such-manifest.json" > /dev/null
check_eq "annotate (risk) exits 0" "$(rc node "$ROUNDS" annotate "$R" --root "$REPO" --base "$BASE")" 0
check_eq "annotate: risk tier embedded" "$(jget "$R" risk.tier)" deep
check_eq "validator accepts the embedded risk" "$(rc node "$VALIDATOR" "$R")" 0

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

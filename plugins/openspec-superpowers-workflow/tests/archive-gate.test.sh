#!/bin/bash
# archive-gate hook fixture 測試
# 用法:bash plugins/openspec-superpowers-workflow/tests/archive-gate.test.sh   (GATE=<路徑> 測副本)
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml 列舉 plugins/*/tests/*.test.sh)
# 只有全部通過、且實際跑到的斷言數達下限才 exit 0
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE=${GATE:-"$SCRIPT_DIR/../hooks/archive-gate.sh"}
CHECK="$SCRIPT_DIR/../skills/openspec-superpowers-workflow/validators/reconcile-check.cjs"
HOOKS_JSON="$SCRIPT_DIR/../hooks/hooks.json"
command -v node >/dev/null 2>&1 || { echo "archive-gate.test: node is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "archive-gate.test: jq is required"; exit 1; }
BASH_BIN=$(command -v bash)

TMPBASE="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "${TMPBASE%/}/archive-gate-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# input_json <session_id> <cwd> <command>
input_json() { jq -cn --arg s "$1" --arg c "$2" --arg cmd "$3" '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd}}'; }
# run_gate <input_json> <tmpdir> <project_dir> [PATH 覆寫]
run_gate() {
  if [ -n "${4:-}" ]; then
    printf '%s' "$1" | env PATH="$4" TMPDIR="$2" CLAUDE_PROJECT_DIR="$3" "$BASH_BIN" "$GATE" 2>/dev/null || true
  else
    printf '%s' "$1" | TMPDIR="$2" CLAUDE_PROJECT_DIR="$3" "$BASH_BIN" "$GATE" 2>/dev/null || true
  fi
}
# contains <名稱> <實際輸出> <固定字串>
contains() {
  if printf '%s' "$2" | command grep -qF -- "$3"; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — output lacks [$3]: $(printf '%s' "$2" | head -c 300)"; fi
}
# empty <名稱> <實際輸出>(allow = 靜默放行)
empty() {
  if [ -z "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected empty, got: $(printf '%s' "$2" | head -c 300)"; fi
}
# exists <名稱> <路徑>
exists() {
  if [ -e "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — missing $2"; fi
}

# make_change <專案根> <名稱>：一份完整合法、review 已標 final 的 change
make_change() {
  local d="$1/openspec/changes/$2"
  mkdir -p "$d/specs/api"
  printf '# Proposal\n\nWhy: x.\n' > "$d/proposal.md"
  printf '# Design\n\nDecision: y.\n' > "$d/design.md"
  printf '# Tasks\n\n- [x] 1.1 build\n' > "$d/tasks.md"
  printf '### Requirement: Export\nThe system SHALL export.\n' > "$d/specs/api/spec.md"
  printf '# Review Notes\n\n## Round 1 - PR Review (2026-11-01, final)\n- [CODE] N - rename\n' > "$d/review-notes.md"
}
# verified <專案根> <名稱>：建 change 並跑 check 產生 pass verdict
verified() { make_change "$1" "$2"; node "$CHECK" check "$1/openspec/changes/$2" > /dev/null 2>&1; }

DENY='"permissionDecision":"deny"'

# ---- cases ----

# 未核查 → deny，原因 no-verdict
P=$WORK/p1; T=$WORK/t1; mkdir -p "$T"; make_change "$P" foo
out=$(run_gate "$(input_json s1 "$P" 'openspec archive foo --yes')" "$T" "$P")
contains "unverified CLI archive → deny" "$out" "$DENY"
contains "unverified → reason no-verdict" "$out" "no-verdict"
contains "deny names the check command" "$out" "reconcile-check.cjs check"
contains "deny names the bypass" "$out" "OPENSPEC_ARCHIVE_OK=1"

# 已核查 → 放行並留歸檔標記
P=$WORK/p2; T=$WORK/t2; mkdir -p "$T"; verified "$P" foo
out=$(run_gate "$(input_json s2 "$P" 'openspec archive foo --yes')" "$T" "$P")
empty "verified CLI archive → allow" "$out"
exists "allow leaves the archived marker" "$T/claude-openspec-archived-s2"

# 核查後改 design.md → deny，stale:design
printf 'More.\n' >> "$P/openspec/changes/foo/design.md"
out=$(run_gate "$(input_json s2b "$P" 'openspec archive foo --yes')" "$T" "$P")
contains "edited after check → deny" "$out" "$DENY"
contains "edited after check → stale:design" "$out" "stale:design"

# 旗標位置不影響名稱（Review Focus 2）
P=$WORK/p1; T=$WORK/t1
out=$(run_gate "$(input_json s3 "$P" 'openspec archive -y foo')" "$T" "$P")
contains "flag before name → deny" "$out" "$DENY"
contains "flag before name → names foo" "$out" "foo"
out=$(run_gate "$(input_json s3 "$P" 'openspec archive foo --yes --skip-specs')" "$T" "$P")
contains "flags after name → deny" "$out" "$DENY"
contains "flags after name → names foo" "$out" "foo"

# 範本的 mkdir + mv 路徑
out=$(run_gate "$(input_json s4 "$P" 'mkdir -p openspec/changes/archive && mv openspec/changes/foo openspec/changes/archive/2026-11-09-foo')" "$T" "$P")
contains "template mv → deny" "$out" "$DENY"

# 引號與絕對路徑的 mv（Review Focus 1）
out=$(run_gate "$(input_json s5 "$P" "mv \"$P/openspec/changes/foo/\" \"$P/openspec/changes/archive/2026-11-09-foo\"")" "$T" "$P")
contains "quoted absolute mv → deny" "$out" "$DENY"

# bulk：bar 已核查、foo 沒有 → deny 並點名 foo（Review Focus 5）
P=$WORK/p3; T=$WORK/t3; mkdir -p "$T"; verified "$P" bar; make_change "$P" foo
out=$(run_gate "$(input_json s6 "$P" 'mv openspec/changes/bar openspec/changes/archive/2026-11-09-bar && mv openspec/changes/foo openspec/changes/archive/2026-11-09-foo')" "$T" "$P")
contains "bulk with one unverified → deny" "$out" "$DENY"
contains "bulk deny names foo" "$out" "foo: no-verdict"

# 已核查的 change 走範本的 mv 路徑 → 放行，同樣留下歸檔標記
P=$WORK/p4; T=$WORK/t4; mkdir -p "$T"; verified "$P" baz
out=$(run_gate "$(input_json s10 "$P" 'mkdir -p openspec/changes/archive && mv openspec/changes/baz openspec/changes/archive/2026-11-09-baz')" "$T" "$P")
empty "verified template mv → allow" "$out"
exists "template mv allow leaves the archived marker" "$T/claude-openspec-archived-s10"

# 繞過字樣
P=$WORK/p1; T=$WORK/t1
out=$(run_gate "$(input_json s7 "$P" 'OPENSPEC_ARCHIVE_OK=1 openspec archive foo --yes')" "$T" "$P")
empty "bypass prefix → allow" "$out"

# 與歸檔無關的命令
out=$(run_gate "$(input_json s8 "$P" 'mv a.txt b.txt')" "$T" "$P"); empty "unrelated mv → allow" "$out"
out=$(run_gate "$(input_json s8 "$P" 'git status')" "$T" "$P"); empty "unrelated command → allow" "$out"
out=$(run_gate "$(input_json s8 "$P" "git commit -m 'docs: openspec archive foo --yes'")" "$T" "$P")
empty "archive words inside a quoted commit message → allow" "$out"

# fail-open
out=$(run_gate "$(input_json s9 "$P" 'openspec archive nope --yes')" "$T" "$P"); empty "change dir missing → allow" "$out"
out=$(run_gate "$(input_json s9 "$P" 'openspec archive')" "$T" "$P"); empty "no change name → allow" "$out"
out=$(run_gate '{not json' "$T" "$P"); empty "malformed input → allow" "$out"
mkdir -p "$WORK/nonode"
for t in jq perl touch; do ln -s "$(command -v "$t")" "$WORK/nonode/$t"; done
out=$(run_gate "$(input_json s9 "$P" 'openspec archive foo --yes')" "$T" "$P" "$WORK/nonode"); empty "no node on PATH → allow" "$out"

# hooks.json 註冊兩個帶 if 的 handler
n=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select((.command | test("archive-gate.sh")) and (.if != null))] | length' "$HOOKS_JSON" 2>/dev/null)
if [ "$n" = 2 ]; then PASS=$((PASS+1)); echo "PASS: hooks.json registers two archive-gate handlers with if"
else FAIL=$((FAIL+1)); echo "FAIL: hooks.json archive-gate handlers with if — got [$n]"; fi

# ---- summary ----
MIN=27
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then
  echo "FAIL: ran $((PASS + FAIL)) assertions, expected at least $MIN"; FAIL=$((FAIL+1))
fi
echo "archive-gate: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

#!/bin/bash
# The plugin's documents make claims about the OpenSpec CLI and its /opsx:* slash commands. This test
# checks them against the real CLI so they cannot drift again: every `openspec <sub>` is a real
# subcommand, every flag exists, the docs name every upstream /opsx command, two known-wrong sentences
# stay gone, and the tasks.md format claim holds (OpenSpec counts one task per checkbox).
# 用法:bash plugins/openspec-superpowers-workflow/tests/cli-claims.test.sh
#   DOCS_DIR=<路徑> 測副本;OPENSPEC_BIN=<路徑> 指定 CLI。版本以 tests/openspec-version 為準(CI 安裝同一個字串)
# 缺 openspec:CI=true 時失敗(條件式 skip 會讓 CI 綠得不真實),本機只印 SKIP 後 exit 0
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/.."
DOCS_DIR=${DOCS_DIR:-"$PLUGIN_DIR"}
OPENSPEC=${OPENSPEC_BIN:-openspec}
PINNED=$(tr -d '[:space:]' < "$SCRIPT_DIR/openspec-version")

# ---- 取得 CLI:缺就依 CI 與否失敗或 skip ----
if ! command -v "$OPENSPEC" >/dev/null 2>&1; then
  if [ "${CI:-}" = "true" ]; then echo "FAIL: openspec CLI not found in CI (expected $PINNED, see tests/openspec-version)"; exit 1; fi
  echo "SKIP: openspec CLI not found; install @fission-ai/openspec@$PINNED to run cli-claims locally"; exit 0
fi
[ -n "${CLI_CLAIMS_INNER:-}" ] && { echo "inner run: CLI present"; exit 0; }
command -v node >/dev/null 2>&1 || { echo "cli-claims.test: node is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "cli-claims.test: jq is required"; exit 1; }

TMPBASE="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "${TMPBASE%/}/cli-claims.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"; else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected [$2] got [$3]"; fi; }
# 隔離 OpenSpec 的全域設定,不吃這台機器的 profile
mkdir -p "$WORK/xdg" "$WORK/home"
# OPENSPEC_TELEMETRY=0: the isolated HOME would otherwise discard a contributor's telemetry opt-out and mint a new anonymous id per run
ox() { OPENSPEC_TELEMETRY=0 XDG_CONFIG_HOME="$WORK/xdg" HOME="$WORK/home" "$OPENSPEC" "$@"; }

ver=$(ox --version 2>/dev/null | tr -d '[:space:]')
if [ "$ver" != "$PINNED" ]; then
  if [ "${CI:-}" = "true" ]; then eq "installed openspec is the pinned version" "$PINNED" "$ver"
  else echo "NOTE: openspec $ver is installed, the docs are checked against $PINNED"; fi
fi

# ---- 文件裡的 `openspec <sub> …` 宣稱 ----
node - "$DOCS_DIR" > "$WORK/claims.tsv" <<'NODE'
const fs = require('fs'), path = require('path');
const root = process.argv[2];
const files = [];
(function walk(d) {
  for (const n of fs.readdirSync(d).sort()) {
    const p = path.join(d, n), st = fs.statSync(p);
    if (st.isDirectory()) { if (!['node_modules', 'evals', 'tests', 'scripts', '.git'].includes(n) && !n.startsWith('evals')) walk(p); }
    else if (n.endsWith('.md') && n !== 'CHANGELOG.md') files.push(p);
  }
})(root);
for (const f of files) {
  const rel = path.relative(root, f);
  let fence = false;
  fs.readFileSync(f, 'utf8').split('\n').forEach((line, i) => {
    for (const m of line.matchAll(/\/opsx:([a-z][a-z-]*)/g)) console.log(['OPSX', m[1], `${rel}:${i + 1}`].join('\x1f'));
    if (/^\s*```/.test(line)) { fence = !fence; return; }
    const segs = fence ? [line] : [...line.matchAll(/`([^`]+)`/g)].map((m) => m[1]);
    for (const s of segs) {
      for (const m of s.matchAll(/(?:^|[\s;&|(])openspec\s+([a-z][a-z-]*)((?:\s+[^\s;&|)`]+)*)/g)) {
        const toks = m[2].trim() ? m[2].trim().split(/\s+/) : [];
        const second = toks[0] && /^[a-z][a-z-]*$/.test(toks[0]) ? toks[0] : '';
        const flags = toks.filter((t) => /^--?[A-Za-z][\w-]*/.test(t)).map((t) => t.replace(/=.*/, ''));
        console.log(['CLAIM', m[1], second, flags.join(','), `${rel}:${i + 1}`].join('\x1f'));
      }
    }
  });
}
NODE
claim_count=$(command grep -c '^CLAIM' "$WORK/claims.tsv")
eq "at least 10 openspec claims were extracted from the docs" yes "$([ "$claim_count" -ge 10 ] && echo yes || echo no)"

# 第一層命令表與各子命令 help(快取)
ox --help > "$WORK/help.top" 2>&1
# cmds_of <help file>:the names in its Commands: table
cmds_of() { sed -nE '/^Commands:/,$ s/^  ([a-z][a-z-]*)([[:space:]].*)?$/\1/p' "$1"; }
cmds_of "$WORK/help.top" > "$WORK/top.cmds"
subhelp() { # <sub> [second]
  local f="$WORK/help.$1${2:+.$2}"
  [ -f "$f" ] || ox "$1" ${2:+"$2"} --help > "$f" 2>&1
  printf '%s' "$f"
}
sub_bad=""; flag_bad=""
# 欄位分隔用 US(0x1f):tab 是 IFS 空白字元,會把空的 second 欄合併掉而讓後面的欄位左移
while IFS=$'\x1f' read -r kind sub second flags where; do
  [ "$kind" = CLAIM ] || continue
  if ! command grep -qx -- "$sub" "$WORK/top.cmds"; then sub_bad+=" $where(openspec $sub)"; continue; fi
  hf=$(subhelp "$sub")
  helpfiles=("$hf")
  if command grep -q '^Commands:' "$hf" && [ -n "$second" ]; then
    if cmds_of "$hf" | command grep -qx -- "$second"; then helpfiles+=("$(subhelp "$sub" "$second")")
    else sub_bad+=" $where(openspec $sub $second)"; continue; fi
  fi
  IFS=, read -r -a flist <<< "$flags"
  for fl in ${flist[@]+"${flist[@]}"}; do
    [ -n "$fl" ] || continue
    found=no
    for h in "${helpfiles[@]}"; do command grep -qE -- "(^|[[:space:],])$fl([[:space:]=,<]|\$)" "$h" && found=yes; done
    [ "$found" = yes ] || flag_bad+=" $where($sub $fl)"
  done
done < "$WORK/claims.tsv"
eq "every documented openspec subcommand exists" "" "$sub_bad"
eq "every documented openspec flag exists" "" "$flag_bad"

# ---- /opsx:* 名稱:由完整 profile 的 init 產生,不手抄 ----
# 十二個名稱是 OpenSpec 1.16 的 ALL_WORKFLOWS;profile 只能這樣非互動地選(config profile 只認 core)
ox config set profile custom > /dev/null 2>&1
ox config set workflows '["propose","explore","new","continue","apply","update","ff","sync","archive","bulk-archive","verify","onboard"]' > /dev/null 2>&1
mkdir -p "$WORK/full"
(cd "$WORK/full" && git init -q . && ox init . --tools claude < /dev/null > /dev/null 2>&1)
ls "$WORK/full/.claude/commands/opsx" 2>/dev/null | sed 's/\.md$//' | sort > "$WORK/opsx.names"
eq "a full-profile init generates 12 command templates" 12 "$(wc -l < "$WORK/opsx.names" | tr -d ' ')"
PH="$DOCS_DIR/skills/openspec-superpowers-workflow/phases.md"
missing=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  command grep -qF -- "/opsx:$name" "$PH" || missing+=" $name"
done < "$WORK/opsx.names"
eq "phases.md names every upstream /opsx command" "" "$missing"
unknown=""
while IFS=$'\x1f' read -r kind name where; do
  [ "$kind" = OPSX ] || continue
  command grep -qx -- "$name" "$WORK/opsx.names" || unknown+=" $where(/opsx:$name)"
done < "$WORK/claims.tsv"
eq "every /opsx name in the docs is an upstream command" "" "$unknown"

# ---- 已知錯誤的敘述不能回來 ----
eq "phases.md no longer says apply has no CLI equivalent" 0 "$(command grep -cF 'no direct CLI equivalent' "$PH")"
eq "phases.md no longer tells to use --yes to get past the incomplete-task warning" 0 "$(command grep -cF 'use `--yes` to proceed' "$PH")"

# ---- tasks.md 格式主張:每個 Task 一個框 → OpenSpec 算出的 task 數等於 Task 標題數 ----
# the full-profile project above is already an OpenSpec root; reuse it instead of a second init
proj="$WORK/full"
(cd "$proj" && ox new change demo > /dev/null 2>&1)
cd_="$proj/openspec/changes/demo"; mkdir -p "$cd_/specs/x"
printf '## Why\nx\n## What Changes\n- x\n## Capabilities\n### New Capabilities\n- `x`: y\n' > "$cd_/proposal.md"
printf '### Requirement: A\nThe system SHALL do a.\n#### Scenario: s\n- **WHEN** a\n- **THEN** b\n' > "$cd_/specs/x/spec.md"
printf '## Context\nx\n' > "$cd_/design.md"
SAMPLE=${TASKS_SAMPLE:-"$PLUGIN_DIR/tests/fixtures/openspec-workflow/tasks-format/tasks.md"}
cp "$SAMPLE" "$cd_/tasks.md"
want=$(command grep -c '^### Task ' "$SAMPLE")
# progress → "total/complete" from one CLI call
progress() { (cd "$proj" && ox instructions apply --change demo --json 2>/dev/null) | jq -r '"\(.progress.total)/\(.progress.complete)"'; }
eq "format sample: OpenSpec counts one task per Task heading, none complete before ticking" "$want/0" "$(progress)"
perl -pi -e 's/\[ \]/[x]/' "$cd_/tasks.md"
eq "format sample: ticking every box completes every task" "$want/$want" "$(progress)"

# ---- task 定義以 OpenSpec 為 oracle:共用模組算出的 total/completed 必須等於 instructions apply 的 progress ----
TL="$PLUGIN_DIR/skills/openspec-superpowers-workflow/validators/task-line.cjs"
printf -- '- [ ] a\n* [x] b\n+ [ ] c\n1. [X] d\n2) [ ] e\n- [~] f\n- [] g\n- [doc](./doc.md)\n- [ ](./still.md)\n  - [ ] nested\n- [x]done\n' > "$cd_/tasks.md"
ours=$(node -e 'const t=require(process.argv[1]).parseTaskLines(require("fs").readFileSync(process.argv[2],"utf8")); console.log(t.length+"/"+t.filter(x=>x.done).length)' "$TL" "$cd_/tasks.md" 2>/dev/null)
eq "task-line.cjs agrees with OpenSpec on total/complete for every bullet and marker form" "$(progress)" "$ours"

# ---- 缺 CLI 時的行為:CI 失敗、本機 skip(以自己的內層呼叫驗證) ----
out=$(CLI_CLAIMS_INNER=1 CI=true OPENSPEC_BIN=/nonexistent/openspec bash "${BASH_SOURCE[0]}" 2>&1); rc=$?
eq "CI without openspec fails" 1 "$rc"
out=$(CLI_CLAIMS_INNER=1 CI= OPENSPEC_BIN=/nonexistent/openspec bash "${BASH_SOURCE[0]}" 2>&1); rc=$?
eq "local without openspec exits 0" 0 "$rc"
eq "local without openspec says SKIP" yes "$(case "$out" in SKIP:*) echo yes;; *) echo no;; esac)"

# ---- summary ----
MIN=14
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then echo "FAIL: ran $((PASS + FAIL)) assertions, expected at least $MIN"; FAIL=$((FAIL+1)); fi
echo "cli-claims: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

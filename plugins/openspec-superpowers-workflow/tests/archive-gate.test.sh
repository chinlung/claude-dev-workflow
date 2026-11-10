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
  printf '%s' "$1" | env ${4:+PATH="$4"} TMPDIR="$2" CLAUDE_PROJECT_DIR="$3" "$BASH_BIN" "$GATE" 2>/dev/null || true
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
# 欄位不得左移:session_id 為空字串時標記仍要落在 unknown;沒有 cwd 時仍要能判定
out=$(run_gate "$(input_json '' "$P" 'openspec archive foo --yes')" "$T" "$P")
empty "empty session_id → allow" "$out"
exists "empty session_id → marker named unknown" "$T/claude-openspec-archived-unknown"
out=$(run_gate "$(jq -cn --arg cmd 'openspec archive foo --yes' '{session_id:"s2c",tool_name:"Bash",tool_input:{command:$cmd}}')" "$T" "$P")
exists "input without cwd → marker still written" "$T/claude-openspec-archived-s2c"

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

# heredoc 剝除只認真正的 heredoc：here-string 與引號內的 << 不是 heredoc，其後的行仍是命令。
# 每個案例都帶一行「收尾」：沒有它，未收尾的本體一律放回當命令，這些案例不論剝除對錯都會 deny
out=$(run_gate "$(input_json s11 "$P" $'cat <<< hello\nopenspec archive foo --yes\nhello')" "$T" "$P")
contains "archive after a here-string → deny" "$out" "$DENY"
out=$(run_gate "$(input_json s11 "$P" $'cat <<<EOF\nopenspec archive foo --yes\nEOF')" "$T" "$P")
contains "archive after a here-string without a space → deny" "$out" "$DENY"
out=$(run_gate "$(input_json s11 "$P" $'echo "<<EOF"\nopenspec archive foo --yes\nEOF')" "$T" "$P")
contains "archive after << inside double quotes → deny" "$out" "$DENY"
out=$(run_gate "$(input_json s11 "$P" $'echo \'x <<EOF\'\nmv openspec/changes/foo openspec/changes/archive/2026-11-09-foo\nEOF')" "$T" "$P")
contains "mv after << inside single quotes → deny" "$out" "$DENY"
# 引號字串拿掉後不得把兩個 < 拼成 <<：cat <"a.md"<EOF 是兩個輸入重導向，不是 heredoc
out=$(run_gate "$(input_json s11 "$P" $'cat <"a.md"<EOF\nopenspec archive foo --yes\nEOF')" "$T" "$P")
contains "archive after two redirects around a quoted word → deny" "$out" "$DENY"
# 沒有收尾行的「heredoc」不是 heredoc（算術位移 $((1<<n)) 就長這樣）：其後的行仍是命令
out=$(run_gate "$(input_json s11 "$P" $'echo $((1<<n))\nopenspec archive foo --yes')" "$T" "$P")
contains "archive after an arithmetic shift → deny" "$out" "$DENY"
out=$(run_gate "$(input_json s11 "$P" $'cat <<EOF\nopenspec archive foo --yes')" "$T" "$P")
contains "archive in a heredoc that never closes → deny" "$out" "$DENY"
# 真正的 heredoc 本體不是命令：delimiter 不加引號、加引號、加反斜線，以及 commit 訊息的 $(cat <<'EOF' 寫法
out=$(run_gate "$(input_json s11 "$P" $'cat > n.md <<EOF\nopenspec archive foo --yes\nEOF')" "$T" "$P")
empty "archive words in a heredoc body → allow" "$out"
out=$(run_gate "$(input_json s11 "$P" $'cat > n.md <<\'EOF\'\nopenspec archive foo --yes\nEOF')" "$T" "$P")
empty "archive words in a quoted-delimiter heredoc body → allow" "$out"
out=$(run_gate "$(input_json s11 "$P" $'cat > n.md <<\\EOF\nopenspec archive foo --yes\nEOF')" "$T" "$P")
empty "archive words in a backslash-delimiter heredoc body → allow" "$out"
out=$(run_gate "$(input_json s11 "$P" $'cat > n.md <<EOF-TEXT\nopenspec archive foo --yes\nEOF-TEXT')" "$T" "$P")
empty "archive words in a heredoc whose delimiter has punctuation → allow" "$out"
out=$(run_gate "$(input_json s11 "$P" $'cat > n.md <<\'END.OF_TEXT\'\nopenspec archive foo --yes\nEND.OF_TEXT')" "$T" "$P")
empty "archive words in a heredoc with a quoted dotted delimiter → allow" "$out"
out=$(run_gate "$(input_json s11 "$P" $'git commit -m "$(cat <<\'EOF\'\nopenspec archive foo --yes\nEOF\n)"')" "$T" "$P")
empty "archive words in a commit-message heredoc → allow" "$out"
# 引號狀態跨行延續：跨行字串在某一行收尾、同一行接著開 heredoc，收尾引號不得與 delimiter 的開頭引號配成一對
out=$(run_gate "$(input_json s11 "$P" $'echo \'line one\nline two\' && cat <<\'EOF\'\nit\'s fine\nEOF\nopenspec archive foo --yes')" "$T" "$P")
contains "archive after a heredoc opened where a multi-line string closes → deny" "$out" "$DENY"
out=$(run_gate "$(input_json s11 "$P" $'echo \'a\n<<EOF b\'\nopenspec archive foo --yes\nEOF')" "$T" "$P")
contains "archive after << inside a multi-line string → deny" "$out" "$DENY"
out=$(run_gate "$(input_json s11 "$P" $'cat <<EOF \'a\nEOF\nb\'\nopenspec archive foo --yes\nEOF')" "$T" "$P")
empty "heredoc opened while a string is open: body starts after the string closes → allow" "$out"
out=$(run_gate "$(input_json s11 "$P" $'grep -c \\\' f <<\'EOF\'\nopenspec archive foo --yes\nEOF')" "$T" "$P")
empty "an escaped quote before a quoted delimiter → allow" "$out"
# 放回的行再找一次 heredoc
out=$(run_gate "$(input_json s11 "$P" $'let x=1<<n\ncat > n.md <<EOF\nopenspec archive foo --yes\nEOF')" "$T" "$P")
empty "a real heredoc after a shift outside \$(( )) → allow" "$out"
# DELIM) 不是收尾行：接受它會把同一行後面的命令、或算術位移之後 case 分支前的命令一起丟掉
out=$(run_gate "$(input_json s11 "$P" $'x=$(cat <<EOF\ntext\nEOF); openspec archive foo --yes')" "$T" "$P")
contains "archive after EOF) on the same line → deny" "$out" "$DENY"
out=$(run_gate "$(input_json s11 "$P" $'n=1; echo $((1<<n))\nopenspec archive foo --yes\ncase n in\nn) :;;\nesac')" "$T" "$P")
contains "archive between an arithmetic shift and a case branch → deny" "$out" "$DENY"
# "$( … )" 是獨立的命令：外層的 " 還開著，裡面的 heredoc 照樣算；本體落單的 " 不得與外層配對
out=$(run_gate "$(input_json s11 "$P" $'git commit -m "$(cat <<\'EOF\'\nsay "hi\nEOF\n)"\nopenspec archive foo --yes')" "$T" "$P")
contains "archive after a commit-message heredoc whose body has a lone quote → deny" "$out" "$DENY"
# $(( … )) 裡的 << 是位移，幾個都不是 heredoc
out=$(run_gate "$(input_json s11 "$P" $'true=1; echo $((1<<true<<true))\ntrue\nopenspec archive foo --yes\ntrue')" "$T" "$P")
contains "archive between lines that equal two shift operands → deny" "$out" "$DENY"
# 註解不是命令文字：裡面的落單引號不得延續到後面的行
out=$(run_gate "$(input_json s11 "$P" $'# don\'t archive yet\ncat > n.md <<EOF\nit\'s\nopenspec archive foo --yes\nEOF')" "$T" "$P")
empty "a lone quote in a comment before a heredoc → allow" "$out"
# 重掃未收尾的 heredoc 時，引號與巢狀狀態要延續：opener 在 "$( 裡，重掃後的 ) 要回到外層的 "
out=$(run_gate "$(input_json s11 "$P" $'x="$(echo ${u:-<<NEVER}\n) <<true #"\nopenspec archive foo --yes\ntrue')" "$T" "$P")
contains "archive after an unclosed heredoc inside a quoted substitution → deny" "$out" "$DENY"
# 行尾反斜線續行：命令行還沒結束，本體從續行之後才開始；偶數個反斜線不是續行
out=$(run_gate "$(input_json s11 "$P" $'cat <<EOF \\\n&& openspec archive foo --yes\nbody\nEOF')" "$T" "$P")
contains "archive on the continuation line of a heredoc opener → deny" "$out" "$DENY"
out=$(run_gate "$(input_json s11 "$P" $'echo a\\\\ <<EOF\nopenspec archive foo --yes\nEOF')" "$T" "$P")
empty "an escaped backslash before the heredoc is not a continuation → allow" "$out"
out=$(run_gate "$(input_json s11 "$P" $'cat <<EOF \\\\\nopenspec archive foo --yes\nEOF')" "$T" "$P")
empty "an escaped backslash at the end of the opener line is not a continuation → allow" "$out"
# 同一行多個 <<：每個 delimiter 依序各有本體；等不到收尾的那個（算術位移）略過，後面的照常
out=$(run_gate "$(input_json s11 "$P" $'let x=1<<n && cat > n.md <<EOF\nopenspec archive foo --yes\nEOF')" "$T" "$P")
empty "a real heredoc on the same line as a shift outside \$(( )) → allow" "$out"
out=$(run_gate "$(input_json s11 "$P" $'cat <<A <<B\nx\nA\nopenspec archive foo --yes\nB')" "$T" "$P")
empty "the second of two heredocs on one line → allow" "$out"

# 跨 hook 契約：archive-gate 放行時留下的標記，就是 skip-gate 讀的那一個（名稱只改一邊，這裡會紅）。
# 聲明比 archive/ 目錄新、比標記舊，所以 deny 只可能來自標記；同一份聲明換個沒有標記的 session 則放行。
SKIP_GATE="$SCRIPT_DIR/../hooks/skip-gate.sh"
edit_json() { jq -cn --arg s "$1" --arg c "$2" --arg f "$3" '{session_id:$s,cwd:$c,tool_name:"Edit",tool_input:{file_path:$f}}'; }
run_skip() { printf '%s' "$1" | TMPDIR="$2" CLAUDE_PROJECT_DIR="$3" "$BASH_BIN" "$SKIP_GATE" 2>/dev/null || true; }
P=$WORK/p20; T=$WORK/t20; mkdir -p "$T" "$P/.claude" "$P/src"; verified "$P" foo
for s in s20 s20x; do
  printf '契約面：API=否 資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 跨模組=否 ｜ 理由：x\n' > "$P/.claude/openspec-skip.$s.local.md"
  touch -t 202001020000 "$P/.claude/openspec-skip.$s.local.md"
done
out=$(run_gate "$(input_json s20 "$P" 'openspec archive foo --yes')" "$T" "$P")
empty "contract: verified archive → allow" "$out"
mkdir -p "$P/openspec/changes/archive"; mv "$P/openspec/changes/foo" "$P/openspec/changes/archive/2026-11-09-foo"
touch -t 202001010000 "$P/openspec/changes/archive"
out=$(run_skip "$(edit_json s20 "$P" "$P/src/a.js")" "$T" "$P")
contains "contract: skip-gate reads the marker archive-gate left" "$out" "本 session 已歸檔"
out=$(run_skip "$(edit_json s20x "$P" "$P/src/a.js")" "$T" "$P")
empty "contract: a session without the marker is not held to it" "$out"

# fail-open
P=$WORK/p1; T=$WORK/t1
out=$(run_gate "$(input_json s9 "$P" 'openspec archive nope --yes')" "$T" "$P"); empty "change dir missing → allow" "$out"
out=$(run_gate "$(input_json s9 "$P" 'openspec archive')" "$T" "$P"); empty "no change name → allow" "$out"
out=$(run_gate '{not json' "$T" "$P"); empty "malformed input → allow" "$out"
mkdir -p "$WORK/nonode"
for t in jq perl touch; do ln -s "$(command -v "$t")" "$WORK/nonode/$t"; done
out=$(run_gate "$(input_json s9 "$P" 'openspec archive foo --yes')" "$T" "$P" "$WORK/nonode"); empty "no node on PATH → allow" "$out"

# reconcile-check.cjs 自身崩潰(exit 1 但 stdout 不是 no-verdict / stale)→ 放行,不是以空原因 deny。
# 以 hook 副本指向壞掉的 validator 副本測:語法錯誤、以及 require 不存在的模組(runtime 例外)。
crash_tree() {  # crash_tree <目錄> <validator 內容>
  mkdir -p "$1/hooks" "$1/skills/openspec-superpowers-workflow/validators"
  cp "$GATE" "$1/hooks/archive-gate.sh"
  printf '%s\n' "$2" > "$1/skills/openspec-superpowers-workflow/validators/reconcile-check.cjs"
}
P=$WORK/p10; T=$WORK/t10; mkdir -p "$T"; verified "$P" foo
crash_tree "$WORK/crash-syntax" 'this is not javascript ('
out=$(GATE="$WORK/crash-syntax/hooks/archive-gate.sh" run_gate "$(input_json s10 "$P" 'openspec archive foo --yes')" "$T" "$P")
empty "validator syntax error → allow" "$out"
crash_tree "$WORK/crash-runtime" "require('./validate-openspec-workflow.cjs'); console.log('fresh');"
out=$(GATE="$WORK/crash-runtime/hooks/archive-gate.sh" run_gate "$(input_json s10 "$P" 'openspec archive foo --yes')" "$T" "$P")
empty "validator runtime exception → allow" "$out"

# hooks.json 註冊兩個帶 if 的 handler
n=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select((.command | test("archive-gate.sh")) and (.if != null))] | length' "$HOOKS_JSON" 2>/dev/null)
if [ "$n" = 2 ]; then PASS=$((PASS+1)); echo "PASS: hooks.json registers two archive-gate handlers with if"
else FAIL=$((FAIL+1)); echo "FAIL: hooks.json archive-gate handlers with if — got [$n]"; fi

# ---- summary ----
MIN=64
if [ "$((PASS + FAIL))" -lt "$MIN" ]; then
  echo "FAIL: ran $((PASS + FAIL)) assertions, expected at least $MIN"; FAIL=$((FAIL+1))
fi
echo "archive-gate: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]

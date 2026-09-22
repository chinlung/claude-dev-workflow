# scope-ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `scope-ledger` plugin — a per-worktree scope ledger file, four fail-open hooks that force review findings through triage and stop a session from ending with the original goal unfinished, and a `/scope-ledger:scope` skill to maintain the ledger.

**Architecture:** One shared bash helper (`hooks/_ledger.sh`) parses the ledger; four small hook scripts source it and each own one event. The skill is prose the model executes with Read/Write/Edit. One bash test suite drives every hook with JSON on stdin, the same way `openspec-superpowers-workflow/tests/skip-gate.test.sh` does.

**Tech Stack:** bash 3.2-compatible shell, `jq`, `awk`, `git`; Claude Code plugin layout (`.claude-plugin/plugin.json`, `hooks/hooks.json`, `skills/<name>/SKILL.md`, `tests/*.test.sh`).

**Spec:** `docs/scope-ledger-design-2026-09-23.md`

## Global Constraints

- Every hook is fail-open: any unexpected condition → `exit 0` with no output; missing `jq` → no-op.
- bash 3.2 (macOS `/bin/bash`): no `mapfile`, no associative arrays, no `${var,,}`, no `declare -A`.
- Ledger path is always `<project>/.claude/scope-ledger.local.md`; `<project>` = `$CLAUDE_PROJECT_DIR`, falling back to the hook input's `cwd`.
- Nothing under `plugins/` or `scripts/` may be written from sandboxed Bash — use the Write/Edit tools (repo `.claude/settings.json` denyWrite). Tests write only under `$TMPDIR`.
- Plugin version starts at `1.0.0`; marketplace `metadata.version` goes `1.10.13` → `1.11.0` (new plugin = minor). All four places carry the version: `plugin.json`, `marketplace.json` entry, `plugins/scope-ledger/CHANGELOG.md`, both root CHANGELOGs.
- Commits: `--no-gpg-sign` inside the sandbox; stage files by name; end the message with the session attribution line.
- Public repo: no project names, session ids or people in any shipped file.

---

### Task 1: Ledger helper + test harness

**Files:**
- Create: `plugins/scope-ledger/hooks/_ledger.sh`
- Create: `plugins/scope-ledger/tests/scope-hooks.test.sh`

**Interfaces:**
- Produces (sourced by every hook): `LEDGER_REL`, `ledger_path <proj>`, `ledger_field <file> <key>`, `ledger_unchecked <file>`, `ledger_rounds <file>`, `ledger_bump_rounds <file>`.

- [ ] **Step 1: Write the failing test file (harness + helper cases only)**

```bash
#!/bin/bash
# scope-ledger hook fixture tests
# 用法：bash plugins/scope-ledger/tests/scope-hooks.test.sh
# 消費者：提交前手跑 + CI（.github/workflows/validate.yml）+ 本地 PostToolUse hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$SCRIPT_DIR/../hooks"
PASS=0; FAIL=0

# 帶模板：無模板的 mktemp -d 在 macOS 會落到 /var/folders/…，sandbox 只准寫 $TMPDIR
TMPBASE="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "${TMPBASE%/}/scope-hooks-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# ---- helpers ----
check() {        # check <name> <actual> <expected substring>
  if printf '%s' "$2" | grep -q -- "$3"; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — got: $2"; fi
}
check_empty() {  # check_empty <name> <actual>
  if [ -z "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected empty, got: $2"; fi
}
check_eq() {     # check_eq <name> <actual> <expected exact>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — expected [$3], got [$2]"; fi
}
check_flag() {   # check_flag <name> <path> <exists|absent>
  if [ "$3" = exists ] && [ -f "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  elif [ "$3" = absent ] && [ ! -f "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — flag state wrong: $2"; fi
}
# run_hook <script> <json> <tmpdir> <project_dir>
run_hook() { printf '%s' "$2" | TMPDIR="$3" CLAUDE_PROJECT_DIR="$4" bash "$HOOKS/$1" 2>/dev/null || true; }

# make_repo <dir> [branch]：git worktree fixture
make_repo() {
  mkdir -p "$1/src" "$1/.claude"
  git -C "$1" init -q 2>/dev/null
  git -C "$1" config core.fsmonitor false 2>/dev/null
  # 需要一個 commit：unborn branch 上 `rev-parse --abbrev-ref HEAD` 會失敗，gate 會 fail-open 放行
  git -C "$1" -c user.email=t@t.t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m init 2>/dev/null
  git -C "$1" checkout -q -b "${2:-feature/x}" 2>/dev/null
}
# write_ledger <dir> <branch> <rounds> <in-scope lines…>
write_ledger() {
  local d="$1" b="$2" r="$3"; shift 3
  {
    printf -- '---\ngoal: 修好通知漏發\nbranch: %s\nopened: 2026-09-23\nreview_rounds: %s\n---\n## In scope\n' "$b" "$r"
    for l in "$@"; do printf '%s\n' "$l"; done
    printf '## Deferred\n## Log\n'
  } > "$d/.claude/scope-ledger.local.md"
}

# ===== _ledger.sh helpers =====
. "$HOOKS/_ledger.sh"
p=$WORK/h1; make_repo "$p"
write_ledger "$p" feature/x 2 '- [ ] A ← 來源: user' '- [x] B ← 來源: user' '- [ ] C ← 來源: review-branch@r1'
L="$p/.claude/scope-ledger.local.md"
check_eq "H1 ledger_path" "$(ledger_path "$p/")" "$p/.claude/scope-ledger.local.md"
check_eq "H2 ledger_field branch" "$(ledger_field "$L" branch)" "feature/x"
check_eq "H3 ledger_field goal" "$(ledger_field "$L" goal)" "修好通知漏發"
check_eq "H4 ledger_rounds" "$(ledger_rounds "$L")" "2"
check_eq "H5 ledger_unchecked 只列 In scope 的未勾項" "$(ledger_unchecked "$L")" "$(printf -- '- [ ] A ← 來源: user\n- [ ] C ← 來源: review-branch@r1')"
check_eq "H6 bump → 3" "$(ledger_bump_rounds "$L")" "3"
check_eq "H6b 檔案內已更新" "$(ledger_rounds "$L")" "3"
# rounds key missing → inserted before closing ---
printf -- '---\ngoal: g\nbranch: b\n---\n## In scope\n- [ ] x\n' > "$L"
check_eq "H7 缺 review_rounds → 視為 0" "$(ledger_rounds "$L")" "0"
check_eq "H7b bump 補上鍵 → 1" "$(ledger_bump_rounds "$L")" "1"
check_eq "H7c 補在 frontmatter 內" "$(ledger_field "$L" review_rounds)" "1"
# non-numeric rounds → 0
printf -- '---\nreview_rounds: abc\n---\n## In scope\n' > "$L"
check_eq "H8 非數字 rounds → 0" "$(ledger_rounds "$L")" "0"
# Deferred section's unticked-looking lines are not In scope
printf -- '---\n---\n## In scope\n- [x] done\n## Deferred\n- [ ] not mine\n' > "$L"
check_empty "H9 Deferred 段的 [ ] 不算未完成" "$(ledger_unchecked "$L")"
# missing file → empty, no crash
check_empty "H10 檔案不存在 → 空" "$(ledger_unchecked "$WORK/nope.md")"
check_eq "H10b 檔案不存在 rounds → 0" "$(ledger_rounds "$WORK/nope.md")" "0"

# ---- summary ----
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash plugins/scope-ledger/tests/scope-hooks.test.sh`
Expected: exits non-zero at `. "$HOOKS/_ledger.sh"` (file missing).

- [ ] **Step 3: Write the helper**

```bash
#!/bin/bash
# Shared ledger helpers for the scope-ledger hooks. Sourced, not executed.
# Every function is quiet on error and prints nothing / a safe default; callers fail-open.

LEDGER_REL=".claude/scope-ledger.local.md"

# ledger_path <proj> → absolute ledger path (existence not checked)
ledger_path() { printf '%s/%s\n' "${1%/}" "$LEDGER_REL"; }

# ledger_field <file> <key> → value of "<key>: …" inside the leading --- frontmatter block
ledger_field() {
  [ -f "$1" ] || return 0
  awk -v k="$2" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, k ":") == 1 { s = substr($0, length(k) + 2); sub(/^[ \t]+/, "", s); print s; exit }
  ' "$1" 2>/dev/null
}

# ledger_unchecked <file> → every "- [ ] …" line inside "## In scope" (empty when none)
ledger_unchecked() {
  [ -f "$1" ] || return 0
  awk '
    /^## / { insec = ($0 == "## In scope"); next }
    insec && /^- \[ \] / { print }
  ' "$1" 2>/dev/null
}

# ledger_rounds <file> → review_rounds as a non-negative integer (0 when missing / not numeric)
ledger_rounds() {
  local v
  v=$(ledger_field "$1" review_rounds)
  case "$v" in '' | *[!0-9]*) echo 0 ;; *) echo "$v" ;; esac
}

# ledger_bump_rounds <file> → review_rounds + 1, written back in place (key added when absent);
# prints the new value. Returns 1 (prints nothing) when the file cannot be rewritten.
ledger_bump_rounds() {
  local f="$1" n tmp
  [ -f "$f" ] || return 1
  n=$(( $(ledger_rounds "$f") + 1 ))
  tmp="$f.tmp.$$"
  if awk -v n="$n" '
      NR == 1 && $0 == "---" { fm = 1; print; next }
      fm && !done && $0 == "---" { print "review_rounds: " n; done = 1; fm = 0; print; next }
      fm && !done && index($0, "review_rounds:") == 1 { print "review_rounds: " n; done = 1; next }
      { print }
    ' "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f" 2>/dev/null; then
    echo "$n"
  else
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
}
```

- [ ] **Step 4: Run the suite, expect all H* cases PASS**

Run: `bash plugins/scope-ledger/tests/scope-hooks.test.sh`
Expected: `PASS=14 FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git -C /Users/scl/web/claude-dev-workflow add plugins/scope-ledger/hooks/_ledger.sh plugins/scope-ledger/tests/scope-hooks.test.sh
git -C /Users/scl/web/claude-dev-workflow commit --no-gpg-sign -m "feat(scope-ledger): ledger parsing helpers with fixture tests"
```

---

### Task 2: `scope-gate.sh` (PreToolUse deny-once)

**Files:**
- Create: `plugins/scope-ledger/hooks/scope-gate.sh`
- Modify: `plugins/scope-ledger/tests/scope-hooks.test.sh` (append cases before `# ---- summary ----`)

**Interfaces:**
- Consumes: `_ledger.sh` (`ledger_path`, `ledger_field`).
- Hook input: `{session_id, cwd, tool_input.file_path|notebook_path}`; output on deny: PreToolUse `permissionDecision: deny` JSON, exit 0.

- [ ] **Step 1: Append failing tests**

```bash
# ===== scope-gate.sh =====
gate_json() { printf '{"session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" "$2" "$3"; }

# G1 非 git 目錄 → allow
p=$WORK/g1; mkdir -p "$p/src"; t=$WORK/gt1; mkdir -p "$t"
check_empty "G1 非 git 目錄 → allow" "$(run_hook scope-gate.sh "$(gate_json s1 "$p" "$p/src/a.php")" "$t" "$p")"
check_flag  "G1 不留 flag" "$t/claude-scope-gate-s1" absent

# G2 git + 程式碼檔 + 無帳本 → deny 一次 + flag
p=$WORK/g2; make_repo "$p"; t=$WORK/gt2; mkdir -p "$t"
rc=0; out=$(printf '%s' "$(gate_json s2 "$p" "$p/src/a.php")" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/scope-gate.sh" 2>/dev/null) || rc=$?
check "G2 無帳本首次編輯 → deny" "$out" '"permissionDecision":"deny"'
check "G2 exit 0" "$rc" '^0$'
check "G2 訊息指向 init" "$out" 'scope init'
check_flag "G2 留 flag" "$t/claude-scope-gate-s2" exists
# G3a 批次窗內手足編輯 → 續 deny；G3b 窗外重試 → allow
check "G3a 批次窗內 → 續 deny" "$(run_hook scope-gate.sh "$(gate_json s2 "$p" "$p/src/b.ts")" "$t" "$p")" '"permissionDecision":"deny"'
touch -t 202001010000 "$t/claude-scope-gate-s2"
check_empty "G3b 窗外重試 → allow" "$(run_hook scope-gate.sh "$(gate_json s2 "$p" "$p/src/b.ts")" "$t" "$p")"

# G4 帳本存在且 branch 相符 → allow、不留 flag（兩種副檔名）
p=$WORK/g4; make_repo "$p" feature/x; t=$WORK/gt4; mkdir -p "$t"
write_ledger "$p" feature/x 0 '- [ ] A'
check_empty "G4 帳本相符 .php → allow" "$(run_hook scope-gate.sh "$(gate_json s4 "$p" "$p/src/a.php")" "$t" "$p")"
check_empty "G4 帳本相符 .go → allow" "$(run_hook scope-gate.sh "$(gate_json s4 "$p" "$p/src/a.go")" "$t" "$p")"
check_flag  "G4 不留 flag" "$t/claude-scope-gate-s4" absent

# G5 帳本 branch 不符 → deny，訊息含兩個分支名
p=$WORK/g5; make_repo "$p" feature/y; t=$WORK/gt5; mkdir -p "$t"
write_ledger "$p" feature/x 0 '- [ ] A'
out=$(run_hook scope-gate.sh "$(gate_json s5 "$p" "$p/src/a.php")" "$t" "$p")
check "G5 branch 不符 → deny" "$out" '"permissionDecision":"deny"'
check "G5 訊息含帳本分支" "$out" 'feature/x'
check "G5 訊息含當前分支" "$out" 'feature/y'
# G5b 帳本 branch 欄空白 → fail-open allow
write_ledger "$p" "" 0 '- [ ] A'
check_empty "G5b 帳本 branch 空白 → allow" "$(run_hook scope-gate.sh "$(gate_json s5b "$p" "$p/src/a.php")" "$WORK/gt5b" "$p")"

# G6 非程式碼檔（md / json）→ allow，即使無帳本
p=$WORK/g6; make_repo "$p"; t=$WORK/gt6; mkdir -p "$t"
check_empty "G6 .md → allow" "$(run_hook scope-gate.sh "$(gate_json s6 "$p" "$p/README.md")" "$t" "$p")"
check_empty "G6 .json → allow" "$(run_hook scope-gate.sh "$(gate_json s6 "$p" "$p/package.json")" "$t" "$p")"
check_flag  "G6 不留 flag" "$t/claude-scope-gate-s6" absent
# G6c workflow yaml 算程式碼 → deny
check "G6c .github/workflows/*.yml → deny" "$(run_hook scope-gate.sh "$(gate_json s6c "$p" "$p/.github/workflows/ci.yml")" "$t" "$p")" '"permissionDecision":"deny"'

# G7 豁免路徑：.claude/（帳本本身）與 openspec/ → allow
p=$WORK/g7; make_repo "$p"; t=$WORK/gt7; mkdir -p "$t"
check_empty "G7 .claude/ 內 → allow" "$(run_hook scope-gate.sh "$(gate_json s7 "$p" "$p/.claude/scope-ledger.local.md")" "$t" "$p")"
check_empty "G7 openspec/ 內 .sh → allow" "$(run_hook scope-gate.sh "$(gate_json s7 "$p" "$p/openspec/changes/x/run.sh")" "$t" "$p")"
# G8 專案外路徑 → allow
check_empty "G8 專案外 → allow" "$(run_hook scope-gate.sh "$(gate_json s8 "$p" "$WORK/elsewhere/x.php")" "$t" "$p")"
# G9 無 file_path → allow
check_empty "G9 無 file_path → allow" "$(printf '{"session_id":"s9","cwd":"%s","tool_name":"Edit","tool_input":{}}' "$p" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/scope-gate.sh" 2>/dev/null || true)"
# G10 session_id 消毒
p=$WORK/g10; make_repo "$p"; t=$WORK/gt10; mkdir -p "$t"
check "G10 消毒後仍 deny" "$(run_hook scope-gate.sh "$(gate_json 's10/../evil' "$p" "$p/src/a.php")" "$t" "$p")" '"permissionDecision":"deny"'
check_flag "G10 flag 落在消毒後路徑" "$t/claude-scope-gate-s10_.._evil" exists
```

- [ ] **Step 2: Run, expect G* cases FAIL (script missing → empty output, deny checks fail)**

- [ ] **Step 3: Write the gate**

```bash
#!/bin/bash
# scope-ledger PreToolUse gate — matcher: Edit|Write|MultiEdit|NotebookEdit
#
# The first edit of a SOURCE file (code / shell / SQL / IaC / CI workflow — not Markdown, JSON,
# plain YAML) in a git worktree that has no scope ledger, or whose ledger is bound to another
# branch, is denied ONCE with a message asking for `/scope-ledger:scope init`. The retry passes:
# the gate forces the scope to be written down, it does not judge it. Same batch-window and
# session-flag mechanics as openspec-superpowers-workflow's skip-gate.sh.
#
# Fail-open everywhere: any unexpected condition exits 0 silently — this hook must never be the
# reason an edit cannot happen.
set -uo pipefail
allow() { exit 0; }
trap allow ERR

BATCH_WINDOW_SECS=5
SRC_RE='\.(php|js|jsx|mjs|cjs|ts|tsx|vue|svelte|py|rb|go|rs|java|kt|kts|scala|swift|m|mm|c|cc|cpp|h|hpp|cs|sh|bash|zsh|sql|tf|hcl)$|(^|/)Dockerfile$|(^|/)\.github/workflows/[^/]+\.ya?ml$'

input=$(cat)
command -v jq >/dev/null 2>&1 || allow
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_ledger.sh" || allow

session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
session_id="${session_id//[^a-zA-Z0-9._-]/_}"
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
[ -n "$file_path" ] || allow

proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || allow
proj="${proj%/}"

# Path exemptions come BEFORE the batch window so a sibling write to .claude/ (the ledger
# itself, written right after the deny) is never caught by the window.
case "$file_path" in
  "$proj/.claude/"* | "$proj/openspec/"*) allow ;;
  "$proj/"*) : ;;
  *) allow ;;
esac
printf '%s' "$file_path" | grep -Eq "$SRC_RE" || allow
git -C "$proj" rev-parse --is-inside-work-tree >/dev/null 2>&1 || allow

ledger=$(ledger_path "$proj")
if [ -f "$ledger" ]; then
  lb=$(ledger_field "$ledger" branch)
  cb=$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [ -z "$lb" ] || [ -z "$cb" ] || [ "$lb" = "$cb" ]; then allow; fi
  reason="⛔ scope-ledger：帳本 $ledger 綁定分支「$lb」，目前分支是「$cb」。這是另一項工作：先 \`/scope-ledger:scope done\`（或 status 看舊帳本）收掉舊的，再 \`/scope-ledger:scope init \"<這次的原始請求>\"\` 建新帳本，然後重試本次編輯（同一並行批次的編輯會一併被攔；本閘每 session 只完整觸發一輪）。"
else
  reason="⛔ scope-ledger：本 session 首次編輯程式碼，但 $ledger 不存在。先 \`/scope-ledger:scope init \"<使用者的原始請求，逐字一句>\"\` 建立帳本（goal ＋ In scope 清單），再重試本次編輯。之後 review／scan 的每條 finding 都先進帳本 triage 再動手；結束前 Stop hook 會對照 In scope 未勾項。（同一並行批次的編輯會一併被攔；本閘每 session 只完整觸發一輪。）"
fi

deny() {
  jq -cn --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

flag_file="${TMPDIR:-/tmp}/claude-scope-gate-${session_id}"
if [ -f "$flag_file" ]; then
  now=$(date +%s) || allow
  mtime=$(stat -c %Y "$flag_file" 2>/dev/null || stat -f %m "$flag_file" 2>/dev/null) || allow
  case "$now" in '' | *[!0-9]*) allow ;; esac
  case "$mtime" in '' | *[!0-9]*) allow ;; esac
  if [ $((now - mtime)) -lt "$BATCH_WINDOW_SECS" ]; then deny; fi
  allow
fi
touch "$flag_file"
deny
```

- [ ] **Step 4: Run, expect all H* and G* PASS (`FAIL=0`)**

- [ ] **Step 5: Commit** — `feat(scope-ledger): deny-once gate on the first source edit without a ledger`

---

### Task 3: `scope-review-triage.sh` (PostToolUse context injection)

**Files:**
- Create: `plugins/scope-ledger/hooks/scope-review-triage.sh`
- Modify: `plugins/scope-ledger/tests/scope-hooks.test.sh` (append)

**Interfaces:**
- Consumes: `_ledger.sh` (`ledger_path`, `ledger_rounds`, `ledger_bump_rounds`).
- Hook input: `{tool_name, tool_input.skill | tool_input.subagent_type | tool_input.description, cwd}`; output: PostToolUse `additionalContext` JSON.

- [ ] **Step 1: Append failing tests**

```bash
# ===== scope-review-triage.sh =====
skill_json() { printf '{"session_id":"%s","cwd":"%s","tool_name":"Skill","tool_input":{"skill":"%s"}}' "$1" "$2" "$3"; }
agent_json() { printf '{"session_id":"%s","cwd":"%s","tool_name":"Agent","tool_input":{"subagent_type":"%s","description":"%s"}}' "$1" "$2" "$3" "$4"; }

p=$WORK/r1; make_repo "$p"; t=$WORK/rt1; mkdir -p "$t"
write_ledger "$p" feature/x 0 '- [ ] A'
L="$p/.claude/scope-ledger.local.md"
# R1 非 review skill → 靜默、rounds 不動（兩例）
check_empty "R1 brainstorming → 靜默" "$(run_hook scope-review-triage.sh "$(skill_json s1 "$p" superpowers:brainstorming)" "$t" "$p")"
check_empty "R1 commit → 靜默" "$(run_hook scope-review-triage.sh "$(skill_json s1 "$p" commit-commands:commit)" "$t" "$p")"
check_eq "R1 rounds 仍 0" "$(ledger_rounds "$L")" "0"
# R2 review skill + 帳本 → 注入 triage 政策，rounds 1；再一次 → 2
out=$(run_hook scope-review-triage.sh "$(skill_json s2 "$p" code-audit-rigor:review-branch)" "$t" "$p")
check "R2 注入 additionalContext" "$out" '"additionalContext"'
check "R2 政策：input 不是工單" "$out" '不是工單'
check "R2 標第 1 輪" "$out" '第 1 輪'
check_eq "R2 rounds 寫回 1" "$(ledger_rounds "$L")" "1"
out=$(run_hook scope-review-triage.sh "$(skill_json s2 "$p" security-review)" "$t" "$p")
check "R2b 第 2 輪" "$out" '第 2 輪'
check_empty "R2b 未達門檻無告警" "$(printf '%s' "$out" | grep -o '收斂告警' || true)"
# R3 第 3 輪 → 收斂告警（兩例：3 與 4）
out=$(run_hook scope-review-triage.sh "$(skill_json s3 "$p" codex-review-bg)" "$t" "$p")
check "R3 第 3 輪出現收斂告警" "$out" '收斂告警'
out=$(run_hook scope-review-triage.sh "$(skill_json s3 "$p" claude-security)" "$t" "$p")
check "R3b 第 4 輪仍告警" "$out" '收斂告警'
check_eq "R3b rounds 4" "$(ledger_rounds "$L")" "4"
# R4 Agent 型 review（subagent_type 命中）→ 注入並計輪；非 review agent → 靜默
p=$WORK/r4; make_repo "$p"; t=$WORK/rt4; mkdir -p "$t"; write_ledger "$p" feature/x 0 '- [ ] A'
check "R4 pr-review-toolkit:code-reviewer → 注入" "$(run_hook scope-review-triage.sh "$(agent_json s4 "$p" pr-review-toolkit:code-reviewer "look at diff")" "$t" "$p")" '"additionalContext"'
check "R4b high-precision-dev:critic → 注入" "$(run_hook scope-review-triage.sh "$(agent_json s4 "$p" high-precision-dev:critic "x")" "$t" "$p")" '"additionalContext"'
check_eq "R4 rounds 2" "$(ledger_rounds "$p/.claude/scope-ledger.local.md")" "2"
check_empty "R4c Explore agent → 靜默" "$(run_hook scope-review-triage.sh "$(agent_json s4 "$p" Explore "find files")" "$t" "$p")"
# R4d subagent_type 空、description 提 review → 注入（fallback）
check "R4d 無 subagent_type、description 含 review → 注入" "$(run_hook scope-review-triage.sh "$(agent_json s4 "$p" "" "review the auth module")" "$t" "$p")" '"additionalContext"'
# R5 review skill 但無帳本 → 仍注入政策並點名 init；不崩潰
p=$WORK/r5; make_repo "$p"; t=$WORK/rt5; mkdir -p "$t"
out=$(run_hook scope-review-triage.sh "$(skill_json s5 "$p" review-branch)" "$t" "$p")
check "R5 無帳本 → 注入" "$out" '"additionalContext"'
check "R5 無帳本 → 指向 init" "$out" 'scope init'
# R6 其他工具 → 靜默（兩例）
check_empty "R6 Bash → 靜默" "$(printf '{"session_id":"s6","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git review"}}' "$p" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/scope-review-triage.sh" 2>/dev/null || true)"
check_empty "R6 Edit → 靜默" "$(printf '{"session_id":"s6","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"review.php"}}' "$p" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/scope-review-triage.sh" 2>/dev/null || true)"
```

- [ ] **Step 2: Run, expect R* FAIL**

- [ ] **Step 3: Write the hook**

```bash
#!/bin/bash
# scope-ledger PostToolUse — matcher: Skill|Agent
#
# When a review / scan / audit skill is loaded, or a review-type subagent is dispatched, inject the
# triage policy as context and count the round in the ledger. From WARN_ROUNDS on, add a
# convergence warning. With no ledger, still inject the policy and point at `init`.
# Fires at dispatch time (before the review's own output lands), which is the right moment: the
# policy is read before the findings are.
# Fail-open: any unexpected condition exits 0 silently.
set -uo pipefail
quiet() { exit 0; }
trap quiet ERR

REVIEW_RE='review|security|audit|codex|simplify|critic|adversar|verif|debate'
WARN_ROUNDS=3

input=$(cat)
command -v jq >/dev/null 2>&1 || quiet
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_ledger.sh" || quiet

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
case "$tool" in
  Skill) name=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty') ;;
  Agent) name=$(printf '%s' "$input" | jq -r '(.tool_input.subagent_type // "") as $t | if $t == "" then (.tool_input.description // "") else $t end') ;;
  *) quiet ;;
esac
[ -n "$name" ] || quiet
printf '%s' "$name" | grep -Eiq "$REVIEW_RE" || quiet

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || quiet
ledger=$(ledger_path "${proj%/}")

n=""
if [ -f "$ledger" ]; then
  n=$(ledger_bump_rounds "$ledger" 2>/dev/null || true)
  case "$n" in '' | *[!0-9]*) n=$(ledger_rounds "$ledger") ;; esac
fi
tag="$name@r${n:-?}"

policy="scope-ledger｜review／scan 的產出是 input、不是工單。每條 finding 先進帳本 $ledger triage 再動手：採納→In scope（附「← 來源: $tag」）；延後→Deferred（附理由與去處：issue／專案記憶／review-notes／won't-fix）；噪音→Log 一行。未進帳本的 finding 不得直接修。原目標（goal）的 In scope 未全部勾完前，只採納「屬於本次變更且 Must-fix」的 finding，其餘一律 Deferred。"

if [ -n "$n" ]; then
  msg="$policy 本分支 review 累計第 $n 輪。"
  if [ "$n" -ge "$WARN_ROUNDS" ]; then
    msg="$msg ⚠️ 收斂告警：已達 $n 輪。先在回覆中列出 In scope 剩餘項與 Deferred 清單（/scope-ledger:scope status），確認原目標是否已達成、是否該收尾，再決定要不要再開一輪。"
  fi
else
  msg="$policy ⚠️ 目前沒有帳本（$ledger 不存在），finding 的 triage 無處落地——先 \`/scope-ledger:scope init \"<使用者的原始請求>\"\`，再處理這次 review 的結果。"
fi

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
exit 0
```

- [ ] **Step 4: Run, expect `FAIL=0`**

- [ ] **Step 5: Commit** — `feat(scope-ledger): inject the finding-triage policy after review skills and count rounds`

---

### Task 4: `scope-stop-check.sh` (Stop block-once per state)

**Files:**
- Create: `plugins/scope-ledger/hooks/scope-stop-check.sh`
- Modify: `plugins/scope-ledger/tests/scope-hooks.test.sh` (append)

**Interfaces:**
- Consumes: `_ledger.sh` (`ledger_path`, `ledger_unchecked`).
- Hook input: `{session_id, cwd, stop_hook_active}`; output on block: `{"decision":"block","reason":…}`, exit 0.

- [ ] **Step 1: Append failing tests**

```bash
# ===== scope-stop-check.sh =====
stop_json() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$1" "$2" "$3"; }

# S1 stop_hook_active=true → 靜默（即使有未完成項）
p=$WORK/s1; make_repo "$p"; t=$WORK/st1; mkdir -p "$t"; write_ledger "$p" feature/x 0 '- [ ] A' '- [ ] B'
check_empty "S1 stop_hook_active → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s1 "$p" true)" "$t" "$p")"
# S2 無帳本 → 靜默
p=$WORK/s2; make_repo "$p"; t=$WORK/st2; mkdir -p "$t"
check_empty "S2 無帳本 → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s2 "$p" false)" "$t" "$p")"
# S3 全勾 → 靜默（兩例：1 項全勾、3 項全勾）
p=$WORK/s3; make_repo "$p"; t=$WORK/st3; mkdir -p "$t"; write_ledger "$p" feature/x 0 '- [x] A'
check_empty "S3 全勾 → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s3 "$p" false)" "$t" "$p")"
write_ledger "$p" feature/x 0 '- [x] A' '- [x] B' '- [x] C'
check_empty "S3b 三項全勾 → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s3 "$p" false)" "$t" "$p")"
# S4 兩項未勾 → block、列出項目與數量；同狀態再停 → 靜默；狀態變（勾掉一項）→ 再 block 一次
p=$WORK/s4; make_repo "$p"; t=$WORK/st4; mkdir -p "$t"; write_ledger "$p" feature/x 0 '- [ ] 修三條路徑' '- [x] 補測試' '- [ ] 姊妹缺口'
rc=0; out=$(printf '%s' "$(stop_json s4 "$p" false)" | TMPDIR="$t" CLAUDE_PROJECT_DIR="$p" bash "$HOOKS/scope-stop-check.sh" 2>/dev/null) || rc=$?
check "S4 未勾 → block" "$out" '"decision":"block"'
check "S4 exit 0" "$rc" '^0$'
check "S4 數量 2" "$out" '2 項'
check "S4 列出項目 1" "$out" '修三條路徑'
check "S4 列出項目 2" "$out" '姊妹缺口'
check_flag "S4 記錄狀態" "$t/claude-scope-stop-s4" exists
check_empty "S4b 同狀態再停 → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s4 "$p" false)" "$t" "$p")"
write_ledger "$p" feature/x 0 '- [x] 修三條路徑' '- [x] 補測試' '- [ ] 姊妹缺口'
out=$(run_hook scope-stop-check.sh "$(stop_json s4 "$p" false)" "$t" "$p")
check "S4c 狀態變 → 再 block" "$out" '"decision":"block"'
check "S4c 數量 1" "$out" '1 項'
check_empty "S4d 又同狀態 → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s4 "$p" false)" "$t" "$p")"
# S5 不同 session 各自記狀態
check "S5 另一 session 同帳本 → block" "$(run_hook scope-stop-check.sh "$(stop_json s5 "$p" false)" "$t" "$p")" '"decision":"block"'
# S6 畸形帳本（無 In scope 段）→ 靜默
p=$WORK/s6; make_repo "$p"; t=$WORK/st6; mkdir -p "$t"; printf 'goal only\n' > "$p/.claude/scope-ledger.local.md"
check_empty "S6 畸形帳本 → 靜默" "$(run_hook scope-stop-check.sh "$(stop_json s6 "$p" false)" "$t" "$p")"
```

- [ ] **Step 2: Run, expect S* FAIL**

- [ ] **Step 3: Write the hook**

```bash
#!/bin/bash
# scope-ledger Stop hook
#
# If the ledger still has unticked In-scope items, block the stop ONCE per distinct state: the
# reason lists the items and the three legitimate ways out (finish; move to Deferred with reason and
# destination; name the points that need the user's decision). `stop_hook_active` → allow, so a
# blocked stop that stops again always passes. The unticked list's checksum is remembered per
# session, so a conversation that pauses mid-work is not bounced every turn.
# Fail-open: any unexpected condition exits 0 silently.
set -uo pipefail
allow() { exit 0; }
trap allow ERR

input=$(cat)
command -v jq >/dev/null 2>&1 || allow
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_ledger.sh" || allow

active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
if [ "$active" = "true" ]; then allow; fi

session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
session_id="${session_id//[^a-zA-Z0-9._-]/_}"
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || allow
ledger=$(ledger_path "${proj%/}")
[ -f "$ledger" ] || allow

open=$(ledger_unchecked "$ledger")
[ -n "$open" ] || allow
count=$(printf '%s\n' "$open" | grep -c .)
sig=$(printf '%s\n' "$open" | cksum | awk '{print $1}')
case "$sig" in '' | *[!0-9]*) allow ;; esac

state="${TMPDIR:-/tmp}/claude-scope-stop-${session_id}"
if [ -f "$state" ] && [ "$(cat "$state" 2>/dev/null)" = "$sig" ]; then allow; fi
printf '%s' "$sig" > "$state" || allow

reason="scope-ledger：帳本 $ledger 尚有 $count 項 In scope 未完成：
$open
請擇一後再結束：①繼續做完 ②確定本輪不做的項目移到 Deferred（附理由與去處：issue／專案記憶／review-notes／won't-fix） ③需要使用者裁定的點在回覆中明列。若以上已處理、只是在等使用者回覆，直接再結束即可（同一狀態只提醒一次）。"

jq -cn --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
```

- [ ] **Step 4: Run, expect `FAIL=0`**

- [ ] **Step 5: Commit** — `feat(scope-ledger): block a stop once per state while in-scope items are open`

---

### Task 5: `scope-session-start.sh` + `hooks.json`

**Files:**
- Create: `plugins/scope-ledger/hooks/scope-session-start.sh`
- Create: `plugins/scope-ledger/hooks/hooks.json`
- Modify: `plugins/scope-ledger/tests/scope-hooks.test.sh` (append)

- [ ] **Step 1: Append failing tests**

```bash
# ===== scope-session-start.sh =====
start_json() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "$1" "$2" "$3"; }
# T1 無帳本 → 靜默（兩種 source）
p=$WORK/t1; make_repo "$p"; t=$WORK/tt1; mkdir -p "$t"
check_empty "T1 無帳本 startup → 靜默" "$(run_hook scope-session-start.sh "$(start_json s1 "$p" startup)" "$t" "$p")"
check_empty "T1 無帳本 compact → 靜默" "$(run_hook scope-session-start.sh "$(start_json s1 "$p" compact)" "$t" "$p")"
# T2 有帳本 → 印 goal、未完成數、輪數
p=$WORK/t2; make_repo "$p"; t=$WORK/tt2; mkdir -p "$t"; write_ledger "$p" feature/x 2 '- [ ] A' '- [x] B' '- [ ] C'
out=$(run_hook scope-session-start.sh "$(start_json s2 "$p" compact)" "$t" "$p")
check "T2 含 goal" "$out" '修好通知漏發'
check "T2 未完成 2 項" "$out" '未完成 2 項'
check "T2 review 2 輪" "$out" '2 輪'
check "T2 含清單行" "$out" '- \[ \] C'
# T2b 全勾 → 仍印（未完成 0 項）
write_ledger "$p" feature/x 0 '- [x] A'
check "T2b 全勾仍印、0 項" "$(run_hook scope-session-start.sh "$(start_json s2 "$p" resume)" "$t" "$p")" '未完成 0 項'
# T3 hooks.json 合法且四個事件都掛
check "T3 hooks.json PreToolUse" "$(jq -r '.hooks.PreToolUse[0].matcher' "$HOOKS/hooks.json")" 'Edit|Write|MultiEdit|NotebookEdit'
check "T3 hooks.json PostToolUse" "$(jq -r '.hooks.PostToolUse[0].matcher' "$HOOKS/hooks.json")" 'Skill|Agent'
check "T3 hooks.json Stop" "$(jq -r '.hooks.Stop[0].hooks[0].command' "$HOOKS/hooks.json")" 'scope-stop-check.sh'
check "T3 hooks.json SessionStart" "$(jq -r '.hooks.SessionStart[0].matcher' "$HOOKS/hooks.json")" 'startup|resume|compact|clear'
# T4 每個被 hooks.json 指到的腳本都存在
for s in $(jq -r '.. | .command? // empty' "$HOOKS/hooks.json" | sed -E 's/.*\/hooks\/([^"]+)".*/\1/'); do
  check_flag "T4 $s 存在" "$HOOKS/$s" exists
done
```

- [ ] **Step 2: Run, expect T* FAIL**

- [ ] **Step 3: Write the hook and `hooks.json`**

```bash
#!/bin/bash
# scope-ledger SessionStart — matcher: startup|resume|compact|clear
#
# When the project has a ledger, print it (first 60 lines) plus the open-item and round counts.
# stdout of a SessionStart hook becomes context, so this is what brings the original goal back
# after a compaction or a resume.
# Fail-open: any unexpected condition exits 0 silently.
set -uo pipefail
quiet() { exit 0; }
trap quiet ERR

input=$(cat)
command -v jq >/dev/null 2>&1 || quiet
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_ledger.sh" || quiet

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || quiet
ledger=$(ledger_path "${proj%/}")
[ -f "$ledger" ] || quiet

open=$(ledger_unchecked "$ledger")
count=0
if [ -n "$open" ]; then count=$(printf '%s\n' "$open" | grep -c .); fi
rounds=$(ledger_rounds "$ledger")

echo "scope-ledger｜工作範圍帳本 $ledger：In scope 未完成 $count 項、review 累計 $rounds 輪。原目標（goal）與清單如下；用 /scope-ledger:scope status 重看、review finding 先進帳本再動手："
head -60 "$ledger"
exit 0
```

```json
{
  "description": "scope-ledger：以 .claude/scope-ledger.local.md 為工作範圍帳本——首次改程式碼無帳本 deny 一次、review/scan skill 後注入 finding triage 政策並計輪、Stop 時對照未完成項 block 一次、SessionStart 把帳本印回 context；全面 fail-open",
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/scope-gate.sh\"", "timeout": 10 } ] }
    ],
    "PostToolUse": [
      { "matcher": "Skill|Agent",
        "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/scope-review-triage.sh\"", "timeout": 10 } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/scope-stop-check.sh\"", "timeout": 10 } ] }
    ],
    "SessionStart": [
      { "matcher": "startup|resume|compact|clear",
        "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/scope-session-start.sh\"", "timeout": 10 } ] }
    ]
  }
}
```

- [ ] **Step 4: Run, expect `FAIL=0`**

- [ ] **Step 5: Commit** — `feat(scope-ledger): replay the ledger at session start; register the four hooks`

---

### Task 6: The `scope` skill

**Files:**
- Create: `plugins/scope-ledger/skills/scope/SKILL.md`

**Interfaces:**
- Invoked as `/scope-ledger:scope <init "<goal>" | status | defer … | done>`; the gate and triage hooks name it in their messages exactly as `/scope-ledger:scope init`.

- [ ] **Step 1: Write the skill**

Frontmatter: `name: scope`, `description` ≤ 1536 chars (measure it), `argument-hint: "[init \"<goal>\" | status | defer <item> --why <reason> --to <destination> | done]"`. No `disable-model-invocation` — the hooks ask the model to run it.

Body sections, in this order, all in Traditional Chinese with the ledger template verbatim:

1. **What the ledger is** — the file, the template (exact block from the design doc), the three rules: `goal` is the user's words verbatim; every In scope line ends with `← 來源: user` or `← 來源: <tool>@r<N>`; every Deferred line carries `理由:` and `去處:`.
2. **`init "<goal>"`** — steps: (a) `git rev-parse --abbrev-ref HEAD` for `branch`; (b) if `openspec/changes/<name>/` (not `archive`) exists, In scope is the three phase items (`完成 tasks.md 全部任務`, `Phase 5 review-notes 收斂`, `Phase 6 archive`); otherwise derive 1–7 items from the request as stated, nothing speculative; (c) Write the file; (d) `git check-ignore -q -- .claude/scope-ledger.local.md; echo "check-ignore rc=$?"` — rc 0 → fine; rc 1 → `git ls-files --error-unmatch` first, then tell the user to add `*.local.md` (never edit `.gitignore` yourself); rc 128 → not a repo, skip; (e) if a ledger already exists for another branch, refuse and point at `done`.
3. **`status`** (default when no argument) — Read and print the file, then one line: `In scope 未完成 N 項｜Deferred M 項｜review 第 R 輪`.
4. **Triage policy (applies whenever a review / scan / audit result is in front of you)** — the four-way table: 採納 (fix now) / Deferred / needs the user / noise, each with the ledger action; the four filter questions that fill `理由:` (pre-existing? already guarded? deliberate asymmetry? real attack surface?); the rule "until the goal's In scope is all ticked, adopt only findings that belong to this change and are must-fix"; and the Log line format `- <date> <tool> r<N>: <n> findings → <a> adopted / <d> deferred`.
5. **`defer <item> --why <reason> --to <destination>`** — Edit: remove the In scope line, append `- <item> ← 來源: … ｜ 理由: <reason> ｜ 去處: <destination>` under Deferred. Destination is mandatory; accepted forms: `issue #N`, `專案記憶`, `review-notes`, `won't-fix`.
6. **`done`** — preconditions: no unticked In scope; every Deferred has `去處:`. Then: write one project-memory entry (goal, date, Deferred summary with destinations), delete the ledger, print the summary. If preconditions fail, print what is missing and stop.
7. **What this skill does not do** — edit `.gitignore`; judge the triage; replace `tasks.md`.

- [ ] **Step 2: Measure the description length**

Run: `python3 -c "import re;print(len(re.search(r'^description: (.*)$',open('plugins/scope-ledger/skills/scope/SKILL.md').read(),re.M).group(1)))"`
Expected: ≤ 1536.

- [ ] **Step 3: Commit** — `feat(scope-ledger): /scope-ledger:scope skill (init/status/defer/done + triage policy)`

---

### Task 7: Packaging, registration, docs, CI, mutation check

**Files:**
- Create: `plugins/scope-ledger/.claude-plugin/plugin.json`, `plugins/scope-ledger/README.md`, `plugins/scope-ledger/CHANGELOG.md`
- Modify: `.claude-plugin/marketplace.json` (entry + `metadata.version` 1.10.13 → 1.11.0), `README.md` + `README.zh-TW.md` (table row + `# Scope Ledger Plugin` section: one paragraph + link), `CHANGELOG.md` + `CHANGELOG.zh-TW.md` (new `## [1.11.0] - 2026-09-23` section), `.github/workflows/validate.yml` (add `bash plugins/scope-ledger/tests/scope-hooks.test.sh` step).

- [ ] **Step 1: plugin.json** — name `scope-ledger`, version `1.0.0`, same author/license/repository/homepage as the other plugins, keywords `["scope", "scope-creep", "triage", "review-findings", "stop-hook", "session-continuity", "compaction"]`.
- [ ] **Step 2: plugin README** — what problem (three sentences, aggregate evidence only), the ledger template, the four hooks table, the skill's four verbs, "what it does not do", Testing (`bash plugins/scope-ledger/tests/scope-hooks.test.sh`), note on `*.local.md` gitignore.
- [ ] **Step 3: plugin CHANGELOG** — `## [1.0.0] - 2026-09-23` / Added: initial release, one bullet per hook + skill.
- [ ] **Step 4: marketplace + root READMEs + root CHANGELOGs + CI step** as listed above.
- [ ] **Step 5: Run every gate**

```bash
node scripts/validate-fixtures.cjs > "$TMPDIR/gates.log" 2>&1; RC=$?; tail -5 "$TMPDIR/gates.log"; echo "rc=$RC"
bash plugins/scope-ledger/tests/scope-hooks.test.sh > "$TMPDIR/suite.log" 2>&1; RC=$?; tail -3 "$TMPDIR/suite.log"; echo "rc=$RC"
```
Expected: both `rc=0` (the version, plugin-changelog, dir-completeness, registration and denyWrite gates all green).

- [ ] **Step 6: Mutation check (on a copy under `$TMPDIR`, never on the live tree)**
  1. Copy `plugins/scope-ledger` to `$TMPDIR/mut`; in the copy's `_ledger.sh` make `ledger_unchecked` print nothing → run the copied suite → S4/S4c/S5/T2 must FAIL.
  2. Fresh copy; in `scope-gate.sh` delete the `if [ -f "$ledger" ] …` block → G4/G5b must FAIL.
  3. Fresh copy; in `scope-review-triage.sh` set `WARN_ROUNDS=99` → R3/R3b must FAIL.
  Record the three results in the commit message.
- [ ] **Step 7: Commit** — `feat(scope-ledger): 1.0.0 — package, register, document; marketplace 1.11.0`

---

### Task 8: Wire the user side (`~/.claude`) and hand off

**Files:**
- Modify: `~/.claude/CLAUDE.md` (Code Review section: one rule line; PR wrap-up SOP: append `/scope-ledger:scope done`)
- Modify: `~/.claude/refs/INDEX.md` (one line for `scope-ledger-design.md`), `~/.claude/refs/scope-ledger-design.md` (status line: implemented in plugin `scope-ledger` 1.0.0; decisions taken for the three open points)

- [ ] **Step 1: Read `~/.claude/refs/claude-md-authoring.md` before touching CLAUDE.md** (required by CLAUDE.md itself).
- [ ] **Step 2: Add the rule line** under Code Review, rule-first: `review／scan 的 finding 一律先進 scope-ledger 帳本 triage（/scope-ledger:scope），未進帳本不得動手修；hook 於首次改程式碼、review 呼叫後、Stop、SessionStart 機器強制——理由與證據見 refs/scope-ledger-design.md`. Append `→ /scope-ledger:scope done` to the PR wrap-up SOP line.
- [ ] **Step 3: Commit `~/.claude`** by name (`CLAUDE.md`, `refs/INDEX.md`, `refs/scope-ledger-design.md`), `--no-gpg-sign`.
- [ ] **Step 4: Push both repos**; verify with SHA comparison (`git rev-parse HEAD` vs `git ls-remote origin <branch>`, stderr split off); watch CI on the plugin repo to green.
- [ ] **Step 5: Tell the user** the install commands they must run themselves (sandbox): `claude plugin marketplace update scl-claude-plugins` then `claude plugin install scope-ledger@scl-claude-plugins`, then verify with `claude plugin list`.

# session-reflect Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `session-reflect` plugin——Stop hook 廉價閘門 + 主 Claude 兩段 triage,session 收尾自動回顧並提出最多 5 個經驗證的改進建議,互動勾選執行,未選入 backlog。

**Architecture:** bash 閘門(機械檢查,fail-open)→ block reason 一句短指令 → skill 完整 playbook(triage → 四視角發想 → 兩道驗證 → AskUserQuestion → 執行/backlog)。薄 command `/reflect` 供手動觸發。規格見 `docs/session-reflect-design-2026-08-03.md`(已核准)。

**Tech Stack:** bash + jq(hook)、Claude Code plugin 元件(hooks/skills/commands)、GitHub Actions(gate 測試 CI)。

## Global Constraints

- 所有使用者可見文字用繁體中文;程式識別字與檔名用英文
- Stop hook 全面 fail-open:任何異常路徑輸出 `{"decision": "approve"}`,絕不卡住 session 結束
- flag file 路徑:`${TMPDIR:-/tmp}/claude-session-reflect-<session_id>`(一 session 一次)
- 實質性門檻:transcript < 10 行 → 放行(比照 save-session)
- hook 引用 script 一律用 `$CLAUDE_PLUGIN_ROOT`(repo 慣例)
- 版本:plugin `1.0.0`;marketplace metadata `1.9.1 → 1.10.0`;CHANGELOG 日期 `2026-08-03`
- git staging 一律具名 `git add <file>`,commit 訊息結尾附 Claude-Session 連結(見各 commit 步驟)
- 建議品質鐵律(寫入 skill):證據錨點強制、≤5 上限、Stage 2.5 兩道驗證、verifier 子代理不降級模型

---

### Task 1: gate script(TDD)+ CI wiring

**Files:**
- Create: `plugins/session-reflect/tests/gate.test.sh`
- Create: `plugins/session-reflect/hooks/reflect-gate.sh`
- Modify: `.github/workflows/validate.yml`(檔尾加一個 step)

**Interfaces:**
- Consumes: 無(首個 task)
- Produces: `reflect-gate.sh`——stdin 收 Stop hook JSON(`session_id`, `transcript_path`, `stop_hook_active`),stdout 輸出 `{"decision": "approve"}` 或 `{"decision": "block", "reason": "..."}`;block reason 內含「呼叫 session-reflect plugin 的 reflect skill」指令(Task 3 的 skill 依此命名)

- [ ] **Step 1: 寫失敗測試**

寫入 `plugins/session-reflect/tests/gate.test.sh`(記得 `chmod +x`):

```bash
#!/bin/bash
# session-reflect gate script fixture 測試
# 用法:bash plugins/session-reflect/tests/gate.test.sh
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../hooks/reflect-gate.sh"
PASS=0; FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---- helpers ----

# make_transcript <path> <填充行數> <最後一行 JSON(可為空字串)>
make_transcript() {
  local path="$1" lines="$2" last="$3" i=0
  : > "$path"
  while [ "$i" -lt "$lines" ]; do
    echo '{"type":"user","message":{"content":[{"type":"text","text":"work item '"$i"'"}]}}' >> "$path"
    i=$((i+1))
  done
  [ -n "$last" ] && echo "$last" >> "$path"
  return 0
}

# run_gate <input_json> <tmpdir>
run_gate() {
  printf '%s' "$1" | TMPDIR="$2" bash "$GATE"
}

# check <名稱> <實際輸出> <期望子字串>
check() {
  if echo "$2" | grep -q "$3"; then
    PASS=$((PASS+1)); echo "PASS: $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1 — got: $2"
  fi
}

# check_flag <名稱> <flag 路徑> <expect:exists|absent>
check_flag() {
  if [ "$3" = "exists" ] && [ -f "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  elif [ "$3" = "absent" ] && [ ! -f "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — flag state wrong: $2"; fi
}

ASSISTANT_NORMAL='{"type":"assistant","message":{"content":[{"type":"text","text":"完成了。"}]}}'
ASSISTANT_ASK='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{}}]}}'
ASSISTANT_QUESTION='{"type":"assistant","message":{"content":[{"type":"text","text":"要繼續嗎？"}]}}'

input_json() { # $1=session_id $2=transcript_path $3=stop_hook_active
  printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":%s}' "$1" "$2" "$3"
}

# ---- cases ----

# 1) stop_hook_active=true → approve
t=$WORK/c1; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 "$ASSISTANT_NORMAL"
out=$(run_gate "$(input_json c1 "$t/tr.jsonl" true)" "$t")
check "stop_hook_active → approve" "$out" '"approve"'

# 2) 無 transcript_path → approve
t=$WORK/c2; mkdir -p "$t"
out=$(run_gate '{"session_id":"c2","stop_hook_active":false}' "$t")
check "no transcript → approve" "$out" '"approve"'

# 3) transcript < 10 行 → approve
t=$WORK/c3; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 3 "$ASSISTANT_NORMAL"
out=$(run_gate "$(input_json c3 "$t/tr.jsonl" false)" "$t")
check "short transcript → approve" "$out" '"approve"'

# 4) flag 已存在 → approve
t=$WORK/c4; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 "$ASSISTANT_NORMAL"
touch "$t/claude-session-reflect-c4"
out=$(run_gate "$(input_json c4 "$t/tr.jsonl" false)" "$t")
check "flag exists → approve" "$out" '"approve"'

# 5) transcript 已含 session-reflect 紀錄 → approve
t=$WORK/c5; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 '{"type":"user","message":{"content":[{"type":"text","text":"呼叫 session-reflect plugin 的 reflect skill"}]}}'
out=$(run_gate "$(input_json c5 "$t/tr.jsonl" false)" "$t")
check "already reflected → approve" "$out" '"approve"'

# 6) 最後 assistant 為 AskUserQuestion → approve 且不標記 flag
t=$WORK/c6; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 "$ASSISTANT_ASK"
out=$(run_gate "$(input_json c6 "$t/tr.jsonl" false)" "$t")
check "pending AskUserQuestion → approve" "$out" '"approve"'
check_flag "pending AskUserQuestion → no flag" "$t/claude-session-reflect-c6" absent

# 7) 最後 assistant 文字以問句結尾 → approve 且不標記 flag
t=$WORK/c7; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 "$ASSISTANT_QUESTION"
out=$(run_gate "$(input_json c7 "$t/tr.jsonl" false)" "$t")
check "question tail → approve" "$out" '"approve"'
check_flag "question tail → no flag" "$t/claude-session-reflect-c7" absent

# 8) 實質 session → block 且標記 flag
t=$WORK/c8; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 "$ASSISTANT_NORMAL"
out=$(run_gate "$(input_json c8 "$t/tr.jsonl" false)" "$t")
check "substantive → block" "$out" '"block"'
check "block reason mentions reflect skill" "$out" 'reflect skill'
check_flag "substantive → flag created" "$t/claude-session-reflect-c8" exists

# 9) block 後再跑一次(同 session)→ approve
out=$(run_gate "$(input_json c8 "$t/tr.jsonl" false)" "$t")
check "second run after block → approve" "$out" '"approve"'

# 10) jq 不可用 → approve
t=$WORK/c10; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 "$ASSISTANT_NORMAL"
STUB=$WORK/stub; mkdir -p "$STUB"
for cmd in bash cat grep wc tail touch tr; do
  ln -s "$(command -v "$cmd")" "$STUB/$cmd"
done
out=$(printf '%s' "$(input_json c10 "$t/tr.jsonl" false)" | env PATH="$STUB" TMPDIR="$t" bash "$GATE")
check "jq missing → approve" "$out" '"approve"'

# ---- summary ----
echo "----------------------------------------"
echo "gate.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: 跑測試確認全部失敗**

Run: `bash plugins/session-reflect/tests/gate.test.sh`
Expected: 全部 FAIL 或直接錯誤(`reflect-gate.sh` 不存在)

- [ ] **Step 3: 寫 gate script**

寫入 `plugins/session-reflect/hooks/reflect-gate.sh`(記得 `chmod +x`):

```bash
#!/bin/bash
# session-reflect Stop hook 閘門:全面 fail-open——任何異常路徑都 approve,
# 絕不因本 hook 讓使用者無法結束 session(誤擋代價 > 漏觸發代價)。
set -uo pipefail

approve() { echo '{"decision": "approve"}'; exit 0; }
trap approve ERR

input=$(cat)

# jq 不可用 → 放行
command -v jq >/dev/null 2>&1 || approve

session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false')

# 防迴圈硬性第一關:因上一個 Stop hook block 而繼續 → 放行
if [ "$stop_hook_active" = "true" ]; then approve; fi

# 一 session 一次
flag_file="${TMPDIR:-/tmp}/claude-session-reflect-${session_id}"
if [ -f "$flag_file" ]; then approve; fi

# 無 transcript → 放行
if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then approve; fi

# 實質性:少於 10 行 → 放行
line_count=$(wc -l < "$transcript_path" 2>/dev/null | tr -d ' ')
if [ "${line_count:-0}" -lt 10 ]; then approve; fi

# 本 session 已執行過回顧(手動 /reflect 或先前觸發)→ 放行
if grep -q "session-reflect" "$transcript_path" 2>/dev/null; then approve; fi

# 互動中偵測:最後一則 assistant 訊息在等使用者 → 放行且「不標記 flag」
# (讓路但保留下次觸發權;只有真正 block 才消耗一 session 唯一一次機會)
last_assistant=$(grep -F '"type":"assistant"' "$transcript_path" 2>/dev/null | tail -1 || true)
if [ -n "$last_assistant" ]; then
  tool_names=$(echo "$last_assistant" | jq -r '[.message.content[]? | select(.type=="tool_use") | .name] | join(",")' 2>/dev/null || echo "")
  case "$tool_names" in
    *AskUserQuestion*|*ExitPlanMode*) approve ;;
  esac
  last_text=$(echo "$last_assistant" | jq -r '[.message.content[]? | select(.type=="text") | .text] | last // ""' 2>/dev/null || echo "")
  case "$last_text" in
    *"?"|*"？") approve ;;
  esac
fi

# 全部通過:標記 flag 並觸發回顧
touch "$flag_file"
echo '{"decision": "block", "reason": "🔍 Session 收尾回顧:請呼叫 session-reflect plugin 的 reflect skill 執行回顧。先快速 triage:routine 或無實質內容,直接回報「本次 session 無需回顧:<理由>」即可結束。"}'
```

- [ ] **Step 4: 跑測試確認全綠**

Run: `bash plugins/session-reflect/tests/gate.test.sh`
Expected: `14 passed, 0 failed`(10 案例:c6/c7 各 2 條斷言、c8 有 3 條,合計 14)

- [ ] **Step 5: 接 CI**

`.github/workflows/validate.yml` 的 steps 結尾(`Run fixture / mutation / consistency suite` step 之後)加:

```yaml
      - name: Run session-reflect gate tests
        run: bash plugins/session-reflect/tests/gate.test.sh
```

(ubuntu-latest 內建 jq,無需安裝步驟。)

- [ ] **Step 6: Commit**

```bash
git add plugins/session-reflect/tests/gate.test.sh plugins/session-reflect/hooks/reflect-gate.sh .github/workflows/validate.yml
git commit -m "feat(session-reflect): Stop hook 閘門 + fixture 測試 + CI wiring

Claude-Session: https://claude.ai/code/session_01FgQkhuqDGN4SFeut4va6Tp"
```

---

### Task 2: plugin 骨架(hooks.json + plugin.json)

**Files:**
- Create: `plugins/session-reflect/hooks/hooks.json`
- Create: `plugins/session-reflect/.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: Task 1 的 `hooks/reflect-gate.sh`
- Produces: plugin manifest(name `session-reflect`, version `1.0.0`)——Task 4 的 marketplace 條目引用同名同版本

- [ ] **Step 1: 寫 hooks.json**

寫入 `plugins/session-reflect/hooks/hooks.json`:

```json
{
  "description": "Session 收尾時經廉價閘門判斷後觸發回顧,提出經驗證的改進建議",
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PLUGIN_ROOT/hooks/reflect-gate.sh\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: 寫 plugin.json**

寫入 `plugins/session-reflect/.claude-plugin/plugin.json`:

```json
{
  "name": "session-reflect",
  "version": "1.0.0",
  "description": "Session 收尾回顧建議系統 - Stop hook 廉價閘門 + 兩段 triage,回顧本次任務與交談,經證據錨點與對抗式驗證後提出最多 5 個可執行建議,互動勾選執行,未選入 backlog",
  "author": {
    "name": "scl@hanchih.com"
  },
  "license": "MIT",
  "repository": "https://github.com/chinlung/claude-dev-workflow",
  "homepage": "https://github.com/chinlung/claude-dev-workflow#readme",
  "keywords": [
    "session",
    "reflection",
    "review",
    "suggestions",
    "adversarial-verification",
    "backlog",
    "stop-hook"
  ]
}
```

- [ ] **Step 3: 驗證 JSON 合法**

Run: `jq . plugins/session-reflect/hooks/hooks.json plugins/session-reflect/.claude-plugin/plugin.json`
Expected: 兩份 JSON 正常輸出,exit 0

- [ ] **Step 4: Commit**

```bash
git add plugins/session-reflect/hooks/hooks.json plugins/session-reflect/.claude-plugin/plugin.json
git commit -m "feat(session-reflect): plugin manifest 與 Stop hook 註冊

Claude-Session: https://claude.ai/code/session_01FgQkhuqDGN4SFeut4va6Tp"
```

---

### Task 3: reflect skill(playbook 核心)+ 薄 command

**Files:**
- Create: `plugins/session-reflect/skills/reflect/SKILL.md`
- Create: `plugins/session-reflect/commands/reflect.md`

**Interfaces:**
- Consumes: Task 1 block reason 中的指令句(「呼叫 session-reflect plugin 的 reflect skill」)
- Produces: skill `session-reflect:reflect`(hook 與 command 的共同入口);backlog 檔契約 `.claude/reflect-backlog.md`(`[pending]`/`[rejected]` 區塊格式,見 skill 內文)

- [ ] **Step 1: 寫 SKILL.md**

寫入 `plugins/session-reflect/skills/reflect/SKILL.md`:

```markdown
---
name: reflect
description: Use when the session-reflect Stop hook requests a session wrap-up review, or when the user runs /reflect — 回顧本次 session 的任務與交談,triage 後從四視角提出經驗證的最多 5 個改進建議,互動勾選執行,未選項寫入 backlog。routine 或無實質內容的 session 直接回報「無需回顧」。
---

# Session 收尾回顧(reflect)

回顧本次 session,判斷是否有值得提出的改進建議。**寧缺勿濫**:說不出證據錨點的建議一律丟棄,routine session 直接結束。

## Stage 1:快速 triage(必經,3 句話內判斷完)

依序自問,**任一命中即輸出一句「本次 session 無需回顧:<理由>」並結束**(不進 Stage 2、不發問卷):

1. **routine 工作**——純 git 操作、跑既有指令、格式化、依賴安裝、單純問答查詢,沒有產生新的程式碼或決策
2. **無實質產出**——只有討論沒有落地,或工作中途被放棄
3. **任務未完結**——尚有 in-progress 任務,或使用者上一句是新指示而非收尾語氣(此時也不要打擾,直接結束)
4. **已回顧過**——本 session 稍早已跑過回顧且之後無新工作

## Stage 2:四視角發想(候選建議)

從四個固定視角掃描 session:

| 視角 | 找什麼 |
|------|--------|
| **範圍外發現** | 任務過程中看到但刻意沒碰的 bug、壞味道、過期註解 |
| **既有問題** | 非本次引入、但被這次工作暴露的結構性問題(缺測試、缺 CI 閘門、脆弱耦合) |
| **延伸優化** | 與本次任務直接相關、再走一步就有價值的改進(效能、可讀性、防呆) |
| **知識缺口** | 值得進一步瞭解的主題(新工具、未查證的 API 行為、可寫成 ref 的踩坑) |

發想規則:

- **證據錨點強制**:每個候選必附 `file:line` 或對話中的具體事實;說不出錨點的直接丟棄,不編造「聽起來有用」的泛泛建議
- **先讀 backlog 去重**:讀 `.claude/reflect-backlog.md`(不存在則視為空),已存在(`[pending]` 或 `[rejected]`)的項目不重複提出

## Stage 2.5:驗證層(發想與呈現之間,防激情發想)

候選建議在發問卷之前必須通過兩道過濾:

**第一道:inline 自我反思**——每個候選過四個濾鏡,任一不過即丟棄:

1. **錨點實存**:親自 Read 該 `file:line`,確認引用的程式碼確實存在且如描述(grep 命中 ≠ live code,注意區塊註解)
2. **已有防護**:建議要修的問題是否已被現有機制處理?
3. **刻意設計**:「問題」是否其實是不對稱設計或既定取捨?
4. **價值實在**:執行後使用者可觀察到什麼具體改善?說不出來即丟棄

**第二道:對抗式子代理驗證**——對存活者派發**一個** verifier 子代理批次驗證(Agent tool,**省略 model 參數以繼承主迴圈模型——驗證器不可降級**)。派發 prompt 必須自包含:列出每項建議的主張與錨點,任務框架是**反駁而非確認**——「假設每項建議是誤報,親自 Read 錨點檔案,找證據推翻它;推不翻才標記 survive」。被駁倒的直接丟棄,不佔名額、不入 backlog。

- 「知識缺口」類無 code 錨點:驗證改查「該問題是否其實已在對話中解答過」
- **Fail-open**:子代理派發失敗 → 退回僅 inline 驗證,呈現時明說「本次無對抗式驗證 pass」,不靜默略過

## Stage 3:呈現與執行

- 通過驗證的建議依「價值 × 執行成本」排序,**最多取 5 個**;超額者直接寫入 backlog(`[pending]`)
- backlog 有既存 `[pending]` 項時,問卷前附一句「backlog 尚有 N 項 pending,可用 /reflect 回顧」(不佔名額)
- 一次 `AskUserQuestion`(multiSelect: true)列出建議,每項附一行證據錨點與預估規模
- 通過驗證的建議為 0 個 → 輸出「本次 session 回顧完成:無通過驗證的建議」並結束

使用者勾選後:

- **選中** → 依序在本 session 執行(遵守既有開發紀律:該 TDD 就 TDD、該自審就自審),完成後將該項自 backlog 移除(若曾寫入)
- **未選** → 寫入 backlog,狀態 `[pending]`
- **使用者以 Other 表達「都不要」** → 全部寫入 backlog;若明確說某項「不要再提」→ 記為 `[rejected]`(未來去重依據,永久保留)
- **使用者以 Other 給新指示** → 依新指示行動,候選全部入 backlog(`[pending]`)

## Backlog 檔(.claude/reflect-backlog.md)

- 專案根 `.claude/reflect-backlog.md`,不存在時首次寫入建立;是否版控由使用者決定,**永不自行 commit 此檔**
- 狀態:`[pending]`(待辦,去重時跳過)、`[rejected]`(使用者拒絕,永久保留作去重依據);完成的項目整塊刪除
- 區塊格式:

    ## [pending] 補上 parser 邊界測試
    - 來源:2026-08-03 session(修復 CSV 匯入時發現)
    - 證據:src/parser.ts:142 對空欄位無測試覆蓋
    - 分類:既有問題|預估:小(<30 行)

- 寫入失敗時:回報失敗原因,建議內容直接完整印在對話中(至少不丟失),不中斷流程
```

- [ ] **Step 2: 寫 command**

寫入 `plugins/session-reflect/commands/reflect.md`:

```markdown
---
description: 手動觸發 session 收尾回顧——triage 後提出經驗證的改進建議(呼叫 session-reflect:reflect skill)
---

用 Skill tool 呼叫 `session-reflect:reflect`,依其 playbook 執行完整回顧流程(Stage 1 triage → Stage 2 四視角發想 → Stage 2.5 驗證 → Stage 3 互動與執行)。

手動觸發與 hook 觸發流程完全相同:triage 判定 routine 時照樣回報「無需回顧」即可。
```

- [ ] **Step 3: 人工驗證 skill 可載入**

Run: `head -5 plugins/session-reflect/skills/reflect/SKILL.md`
Expected: frontmatter 以 `---` 開頭,含 `name: reflect` 與 `description:`(skill 為 prompt 內容,無法 unit-test;品質由 playbook 內機械規則約束,見設計文件「驗證」節)

- [ ] **Step 4: Commit**

```bash
git add plugins/session-reflect/skills/reflect/SKILL.md plugins/session-reflect/commands/reflect.md
git commit -m "feat(session-reflect): reflect skill playbook 與 /reflect command

Claude-Session: https://claude.ai/code/session_01FgQkhuqDGN4SFeut4va6Tp"
```

---

### Task 4: 發布 wiring(marketplace + CHANGELOG + README)+ 全套驗證

**Files:**
- Modify: `.claude-plugin/marketplace.json`(plugins 陣列加條目;metadata.version `1.9.1 → 1.10.0`)
- Modify: `CHANGELOG.md`、`CHANGELOG.zh-TW.md`(各加 `[1.10.0]` 節)
- Modify: `README.md`、`README.zh-TW.md`(表格列 + 安裝行 + plugin 章節)

**Interfaces:**
- Consumes: Task 2 的 plugin name/version(`session-reflect` / `1.0.0`)
- Produces: 無(終端 task)

- [ ] **Step 1: marketplace.json 加條目與版本**

`plugins` 陣列尾端(security-audit 之後)加:

```json
{
  "name": "session-reflect",
  "source": "./plugins/session-reflect",
  "description": "Session 收尾回顧建議系統 - Stop hook 廉價閘門 + 兩段 triage,回顧本次任務與交談,經證據錨點與對抗式驗證後提出最多 5 個可執行建議(範圍外 bug / 既有問題 / 延伸優化 / 知識缺口),互動勾選執行,未選入 backlog。與 session-learning 互補:session-learning 保存「經驗」,session-reflect 提出「行動」。",
  "version": "1.0.0",
  "keywords": [
    "session",
    "reflection",
    "review",
    "suggestions",
    "adversarial-verification",
    "backlog",
    "stop-hook"
  ]
}
```

並將 `metadata.version` 改為 `"1.10.0"`。

- [ ] **Step 2: CHANGELOG.md 加節**(檔頭說明之後、`[1.9.1]` 之前)

```markdown
## [1.10.0] - 2026-08-03

### Added

- **session-reflect 1.0.0** (new plugin) — session-end reflective review. A fail-open bash Stop-hook gate (loop guard via `stop_hook_active`, once-per-session flag file, <10-line substantiveness floor, mid-interaction detection that yields without consuming the session's single trigger) hands off to a two-stage skill: quick triage (routine sessions exit with a one-line "nothing to review"), then a four-lens sweep (out-of-scope findings / pre-existing issues / adjacent optimizations / knowledge gaps). Candidates must survive a verification layer before the user ever sees them: an inline four-filter self-review (anchor actually Read, existing safeguards, deliberate design, observable value) plus one adversarial verifier subagent (main-loop model, never downgraded) framed to refute, not confirm. Up to 5 survivors are offered via a multi-select prompt — chosen ones execute in-session, unchosen ones land in `.claude/reflect-backlog.md` (`[rejected]` entries are kept forever as dedup evidence; the plugin never commits the backlog). Gate covered by 14 fixture assertions wired into CI (`tests/gate.test.sh`). Design: `docs/session-reflect-design-2026-08-03.md`.

### Notes

- Marketplace minor bump 1.9.1 → 1.10.0 (new plugin).
```

- [ ] **Step 3: CHANGELOG.zh-TW.md 加對應節**

```markdown
## [1.10.0] - 2026-08-03

### 新增

- **session-reflect 1.0.0**(新 plugin)— session 收尾回顧建議系統。fail-open 的 bash Stop hook 閘門(`stop_hook_active` 防迴圈、一 session 一次 flag file、<10 行實質性門檻、互動中偵測——讓路且不消耗唯一一次觸發權)交棒給兩段式 skill:快速 triage(routine session 一句「無需回顧」退出),再以四視角掃描(範圍外發現/既有問題/延伸優化/知識缺口)。候選建議必須先通過驗證層才會呈現給使用者:inline 四濾鏡自我反思(錨點親自 Read、已有防護、刻意設計、價值實在)+ 一個對抗式 verifier 子代理(繼承主迴圈模型、不降級),任務框架是反駁而非確認。最多 5 個存活建議以 multi-select 問卷呈現——選中即於本 session 執行,未選寫入 `.claude/reflect-backlog.md`(`[rejected]` 項永久保留作去重依據;plugin 永不自行 commit backlog)。閘門由 14 條 fixture 斷言覆蓋並接入 CI(`tests/gate.test.sh`)。設計文件:`docs/session-reflect-design-2026-08-03.md`。

### 備註

- Marketplace minor bump 1.9.1 → 1.10.0(新增 plugin)。
```

- [ ] **Step 4: README.md 三處更新**

表格(Security Audit 列之後)加:

```markdown
| [Session Reflect](#session-reflect-plugin) | Session-end review that proposes up to 5 verified, actionable improvement suggestions | `/reflect` + Stop hook |
```

安裝清單(security-audit 行之後)加:

```bash
/plugin install session-reflect@scl-claude-plugins
```

Plugin 章節(依既有各 plugin 章節的位置慣例,在最後一個 plugin 章節之後)加:

```markdown
## Session Reflect Plugin

Session-end reflective review. A fail-open Stop-hook gate triages cheaply (routine or thin sessions pass through untouched), then the `reflect` skill sweeps the session from four lenses — out-of-scope findings, pre-existing issues, adjacent optimizations, knowledge gaps. Every candidate must carry a concrete evidence anchor and survive both an inline four-filter self-review and an adversarial verifier subagent before you see it. Up to 5 suggestions are offered as a multi-select choice: chosen ones execute immediately while context is hot; unchosen ones persist to `.claude/reflect-backlog.md` for later (`/reflect` re-opens the review anytime). Complements Session Learning: that plugin saves *lessons*, this one proposes *actions*.
```

- [ ] **Step 5: README.zh-TW.md 對應三處更新**

表格列:

```markdown
| [Session Reflect](#session-reflect-plugin) | Session 收尾回顧,提出最多 5 個經驗證的可執行改進建議 | `/reflect` + Stop hook |
```

安裝行同 README.md。章節:

```markdown
## Session Reflect Plugin

Session 收尾回顧系統。fail-open 的 Stop hook 閘門先廉價 triage(routine 或無實質內容的 session 直接放行),再由 `reflect` skill 從四視角掃描 session——範圍外發現、既有問題、延伸優化、知識缺口。每個候選建議必附具體證據錨點,並通過 inline 四濾鏡自我反思與對抗式 verifier 子代理雙重驗證後才會呈現。最多 5 個建議以多選問卷提供:選中的趁 context 還熱立即執行;未選的寫入 `.claude/reflect-backlog.md` 供日後處理(隨時可用 `/reflect` 重開回顧)。與 Session Learning 互補:該 plugin 保存「經驗」,本 plugin 提出「行動」。
```

(zh-TW README 章節錨點若與英文版不同,以該檔既有錨點格式為準。)

- [ ] **Step 6: 全套驗證**

```bash
jq . .claude-plugin/marketplace.json > /dev/null && echo marketplace-ok
node scripts/validate-fixtures.cjs
bash plugins/session-reflect/tests/gate.test.sh
```

Expected: `marketplace-ok`;fixture suite 全綠(125 passed 基準不退化);gate 測試 `14 passed, 0 failed`

- [ ] **Step 7: plugin 結構驗證**

派發 `plugin-dev:plugin-validator` agent 驗證 `plugins/session-reflect/` 結構(manifest 欄位、hooks.json schema、目錄慣例)。
Expected: 無 error 級問題(warning 逐項判斷後處置)

- [ ] **Step 8: Commit**

```bash
git add .claude-plugin/marketplace.json CHANGELOG.md CHANGELOG.zh-TW.md README.md README.zh-TW.md
git commit -m "feat(plugins): 發布 session-reflect 1.0.0,marketplace 1.9.1 → 1.10.0

Claude-Session: https://claude.ai/code/session_01FgQkhuqDGN4SFeut4va6Tp"
```

---

## 完成定義

- 4 個 commit 全部落地,`node scripts/validate-fixtures.cjs` 與 `bash plugins/session-reflect/tests/gate.test.sh` 全綠
- 版本一致性:`plugin.json` = marketplace 條目 = `1.0.0`;marketplace metadata = CHANGELOG 節 = `1.10.0`
- 收尾走 PR / merge 流程時依使用者的 PR 收尾 SOP(不自動觸發)

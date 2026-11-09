# openspec-superpowers-workflow 2.0（PR 2）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `openspec archive`（含範本的 `mv` 路徑）在沒有新鮮的機械核查結果時被擋下，並讓 skip-gate 以可解析的聲明檔取代「第一次編輯擋一次」。

**Architecture:** 一支零相依 Node CLI（`reconcile-check.cjs`：snapshot／check／verify）負責所有雜湊與規則；兩支 bash PreToolUse hook 只做命令解析與決策，判斷交給 CLI。狀態檔放專案 `.claude/`，以 `.local.*` 命名。

**Tech Stack:** bash、jq、Node 20（CI 版本）、`node:crypto` sha256、既有 fixture 式 bash 測試。

**Spec:** `docs/openspec-workflow-2-design-2026-11-09.md`（已核准）

## Global Constraints

- 全面 fail-open：缺 jq／node、JSON 壞掉、讀檔失敗、解析不到名稱，一律 `exit 0` 放行。
- deny 一律 `exit 0` 並在 stdout 印 `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":<文字>}}`，與現行 `skip-gate.sh` 同形。
- 不 bump 版本；不動 `CHANGELOG.md`、`plugin.json`、marketplace 的 `version`（2.0.0 在 PR 3）。
- 零相依：只用 Node 20 內建模組；不得用 Node 20 之後才有的 API。
- 狀態檔：`<專案>/.claude/openspec-reconcile.<change>.local.json`、`<專案>/.claude/openspec-skip.<session>.local.md`、`${TMPDIR:-/tmp}/claude-openspec-archived-<session>`。`<session>` 一律經 `${session_id//[^a-zA-Z0-9._-]/_}` 消毒。
- 繞過字樣：命令含 `OPENSPEC_ARCHIVE_OK=1` 時歸檔閘門放行。
- 聲明格式：一行以 `契約面：` 開頭（也接受半形 `:`），八個 key 依序為 `API 資料 schema migration 相容 權限 並行 跨模組`，值只能是 `是` 或 `否`；行尾 `｜ 理由：<一句>`。
- `final` 標記：最後一個 `## Round` 標題含 `final`（不分大小寫）；只有使用者明說 review 已收斂後，代理才可以加。
- 既有 `tests/fixtures/openspec-workflow/` 與 `scripts/validate-fixtures.cjs` 第 1636 行對 validator 的 CLI 呼叫必須照常通過。

## Review Focus

1. 引號或絕對路徑的 `mv`（`mv "/abs/openspec/changes/foo" "/abs/openspec/changes/archive/2026-11-09-foo"`）：應擋，名稱取 `foo`。
2. 旗標位置：`openspec archive -y foo`、`openspec archive foo --yes --skip-specs`：名稱都是 `foo`。
3. 聲明行用半形冒號或多空白（`契約面: API=否  資料=否 …`）：應視為合法。
4. CRLF 換行的 `review-notes.md`：R3、R4 判定與 LF 相同。
5. bulk：同一命令兩個 `mv`，一個已核查、一個沒有：整個命令 deny，訊息點名沒通過的那個。

以上各有對應測試：第 4 項在 Task 1，第 1、2、5 項在 Task 2，第 3 項在 Task 3。

---

### Task 1: `reconcile-check.cjs`（snapshot／check／verify）

**Files:**
- Modify: `plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/validators/validate-openspec-workflow.cjs`（結尾的 `main();` 改為 `if (require.main === module) main();`，並 `module.exports = { REQUIRED_FILES, findSpecFiles, checkRequirementBlocks, validate }`）
- Create: `plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/validators/reconcile-check.cjs`
- Test: `plugins/openspec-superpowers-workflow/tests/reconcile-check.test.sh`

**Interfaces:**
- Produces（CLI，Task 3 依賴 `verify`）：
  - `node reconcile-check.cjs snapshot <change-dir>` → exit 0，stdout 印狀態檔路徑。
  - `node reconcile-check.cjs check <change-dir> [--json]` → exit 0 無 fail／1 有 fail／2 用法或路徑錯誤。`--json` 輸出 `{change, result:"pass"|"fail", checks:[{id:"R1".."R9", status:"pass"|"fail"|"warn"|"manual", detail:[string]}]}`。result 為 pass 時把 `verdict:{result:"pass", at, hashes:{proposal,design,tasks,reviewNotes,specs}}` 合併寫進狀態檔。
  - `node reconcile-check.cjs verify <change-dir>` → exit 0 狀態檔有 pass verdict 且五個雜湊與現況相同；exit 3 並在 stdout 印一行原因（`no-verdict`／`stale:<artifact>`；用 node 自己不會產生的退出碼，hook 才能靠退出碼區分「change 未就緒」與「checker 崩潰」的 exit 1）；exit 2 用法錯誤。
- 路徑規則：`<change-dir>` 的上層名稱必須是 `changes`、再上層必須是 `openspec`，否則 exit 2；專案根 = `path.resolve(changeDir, '../../..')`；`<change>` = `path.basename(changeDir)`。
- `specs` 雜湊 = 依相對路徑排序後，對每個 `specs/**/spec.md` 串接 `relpath + "\0" + content + "\0"` 取 sha256 hex。其餘四個是檔案內容的 sha256 hex；檔案不存在時記 `"missing"`。

規則（status 與 design 4.1 表一致）：

| id | 判定 |
|---|---|
| R1 | `REQUIRED_FILES` 任一缺，或 `findSpecFiles` 為空 → fail |
| R2 | 任何 spec 的 `checkRequirementBlocks` 有錯 → fail |
| R3 | 只看 `## Round` 下 `^\s*-\s*\[` 的行。合法：`^\s*-\s*\[(REQUIREMENT\|DESIGN\|CODE\|CONSTITUTION)\]\s*([YN])\b` 且不是 `[CODE] Y`。最後一輪有違規 → fail；只有較早輪次違規 → warn；沒有 Round → pass |
| R4 | 沒有 Round → warn；最後一個 `## Round` 標題 `/final/i` → pass，否則 fail |
| R5 | 狀態檔有 `snapshot.tasks` → 與現況比對，不同 → fail；沒有 snapshot 且 `tasks.md` 被 git 追蹤 → `git diff --quiet HEAD -- tasks.md` 非 0 → fail、0 → pass；其餘 → warn |
| R6 | `^\s*-\s*\[ \]` 的行中不含 `skip:` 的數量 > 0 → warn（列數量），否則 pass |
| R7 | proposal、design、specs 命中 `/修訂[：:]/`、`/原本(是\|為)/`、`/\bRound \d+\b/i`、`/review-notes/`、`/\bpreviously\b/i` → warn（列檔名與行號） |
| R8 | 任何輪次有 `[CONSTITUTION] Y` → manual（列出條目，提示確認已進 `openspec/config.yaml`）；沒有 → pass |
| R9 | 永遠 manual：印出 C1（每條 Y 是否落到對應 artifact）與 C5（是否讀起來像一開始就知道）的判準 |

所有讀檔前先 `.replace(/\r\n/g, '\n')`。

- [ ] **Step 1: Write the failing test** — `tests/reconcile-check.test.sh`，仿 `skip-gate.test.sh` 的 helper 風格，在 `mktemp -d "${TMPDIR%/}/reconcile-test.XXXXXX"` 下用函式 `make_change <proj> <name>` 產生一份完整合法的 change（四個檔、一個 spec、一個 `## Round 1 - PR Review (2026-11-01, final)`），各案例再改一處。斷言（每項各一條 check）：
  - 合法 change：`check` exit 0，`--json` 的 `.result=="pass"`，且狀態檔存在、`.verdict.result=="pass"`。
  - R1：刪 `review-notes.md` → exit 1，R1 為 fail。
  - R2：spec 的 Requirement 第一段拿掉 SHALL → R2 fail。
  - R3：最後一輪有 `- [CODE] Y - x` → R3 fail；同一行只出現在 Round 1、最後一輪乾淨 → R3 warn 且 exit 0。
  - R3／R4 CRLF：同一份合法 change 轉成 CRLF → exit 0。
  - R4：最後一輪標題去掉 `final` → R4 fail；沒有任何 Round → R4 warn。
  - R5：`snapshot` 後改 `tasks.md` → R5 fail；`snapshot` 後不改 → R5 pass。
  - R6：一個 `- [ ] x` → R6 warn、exit 0；`- [ ] x skip: 不做` → R6 pass。
  - R7：design 含「原本是 A」→ R7 warn、exit 0。
  - R8：`[CONSTITUTION] Y` 條目 → R8 manual 且 detail 含該條目文字。
  - `verify`：pass 之後 → exit 0；之後改 `design.md` → exit 3 且 stdout 為 `stale:design`；沒有狀態檔 → exit 3 且 `no-verdict`。
  - 路徑：`check /tmp/x`（上層不是 `changes`）→ exit 2。
  - 既有 validator：`node validate-openspec-workflow.cjs tests/fixtures/openspec-workflow/valid-change` 仍 exit 0；`require()` 它不會印出 usage 也不 exit。
- [ ] **Step 2: Run test to verify it fails** — Run: `bash plugins/openspec-superpowers-workflow/tests/reconcile-check.test.sh`；Expected: FAIL（`reconcile-check.cjs` 不存在）。
- [ ] **Step 3: Implement** — 先改 validator 成可 `require`，再寫 `reconcile-check.cjs`，主函式 `main(argv: string[]): number`（回傳 exit code），規則各一個函式 `checkR1(ctx)` … `checkR9(ctx)`，`ctx = { changeDir, projRoot, name, read(rel) }`。
- [ ] **Step 4: Run test to verify it passes** — 同 Step 2 指令；Expected: 全部 PASS。另跑 `node scripts/validate-fixtures.cjs`，Expected: 與改動前相同的通過輸出。
- [ ] **Step 5: Mutation check** — 對 `reconcile-check.cjs` 的副本各做一次並以 `CHECK=<副本>` 跑測試（測試檔支援 `CHECK` 環境變數覆寫路徑），每個都必須轉紅：拿掉 verify 的雜湊比對；R3 改成所有輪次都判 fail；拿掉 R4；R5 永遠 pass。
- [ ] **Step 6: Commit** — `git add` 上述三個檔，訊息 `feat(openspec-workflow): reconcile-check snapshot/check/verify`。

### Task 2: 歸檔閘門 hook

**Files:**
- Create: `plugins/openspec-superpowers-workflow/hooks/archive-gate.sh`
- Modify: `plugins/openspec-superpowers-workflow/hooks/hooks.json`（PreToolUse 新增一組 `matcher: "Bash"`，兩個 handler 都是 `bash "$CLAUDE_PLUGIN_ROOT/hooks/archive-gate.sh"`、`timeout: 10`，`if` 分別為 `Bash(openspec archive *)` 與 `Bash(mv *)`；既有 Edit 那組不動）
- Test: `plugins/openspec-superpowers-workflow/tests/archive-gate.test.sh`

**Interfaces:**
- Consumes: Task 1 的 `reconcile-check.cjs verify <change-dir>`（路徑 `$here/../skills/openspec-superpowers-workflow/validators/reconcile-check.cjs`）。
- Produces: 放行時建立 `${TMPDIR:-/tmp}/claude-openspec-archived-<session>`（Task 3 讀它）。
- 名稱抽取：`openspec archive` 之後第一個不以 `-` 開頭的字；`mv` 的最後一個參數（去引號）含 `/changes/archive/` 或以 `changes/archive/` 開頭時，取來源參數（去引號、去尾端 `/`）的 basename。一個命令可抽出多個名稱。
- 專案根：`${CLAUDE_PROJECT_DIR:-$cwd}`；change 目錄 = `<專案根>/openspec/changes/<名稱>`，不存在就略過該名稱。
- deny 訊息必含：沒通過的名稱、`verify` 給的原因、要跑的兩個指令（`node <絕對路徑>/reconcile-check.cjs snapshot|check <change-dir>`）、`OPENSPEC_ARCHIVE_OK=1` 繞過說明。

- [ ] **Step 1: Write the failing test** — 仿 `skip-gate.test.sh`：`input_json <session> <cwd> <command>` 組 Bash 的 PreToolUse 輸入，`make_change` 建 change，以 Task 1 的 `check` 先產生 verdict 的案例名為 `verified`。斷言：
  - `openspec archive foo --yes`，foo 未核查 → 輸出含 `"permissionDecision":"deny"` 與 `no-verdict`。
  - 同上但 foo 已核查 → 輸出為空，且 `${TMPDIR}/claude-openspec-archived-<session>` 存在。
  - 已核查後改 `design.md` → deny 且含 `stale:design`。
  - `openspec archive -y foo`、`openspec archive foo --yes --skip-specs` → 名稱都是 foo（未核查時 deny）。
  - `mkdir -p openspec/changes/archive && mv openspec/changes/foo openspec/changes/archive/2026-11-09-foo` 未核查 → deny。
  - 引號與絕對路徑的 `mv` → deny（Review Focus 1）。
  - bulk：兩個 `mv`，bar 已核查、foo 沒有 → deny，且訊息點名 foo（Review Focus 5）。
  - 測試檔開頭寫成 `GATE=${GATE:-"$SCRIPT_DIR/../hooks/archive-gate.sh"}`，供 Step 5 的突變以副本覆寫。
  - `OPENSPEC_ARCHIVE_OK=1 openspec archive foo --yes` → 空輸出。
  - `mv a.txt b.txt`、`git status` → 空輸出。
  - change 目錄不存在、命令只有 `openspec archive`（沒有名稱）、輸入 JSON 壞掉、`PATH` 裡沒有 node → 空輸出（fail-open）。
  - `jq -e` 驗 `hooks.json`：PreToolUse 有兩個帶 `if` 的 archive-gate handler。
- [ ] **Step 2: Run test to verify it fails** — Run: `bash plugins/openspec-superpowers-workflow/tests/archive-gate.test.sh`；Expected: FAIL（hook 不存在）。
- [ ] **Step 3: Implement** — 結構照 `skip-gate.sh`（`set -uo pipefail`、`trap allow ERR`、`command -v jq`、`command -v node` 不在就放行）；名稱抽取用一段 `perl -ne`，先去掉 heredoc 本體與單引號字串，避免 commit 訊息裡的字樣被當成命令。
- [ ] **Step 4: Run test to verify it passes** — 同 Step 2；Expected: 全部 PASS。
- [ ] **Step 5: Mutation check** — 以 `GATE=<副本>` 各跑一次，都必須轉紅：拿掉 `mv` 解析；拿掉 verify 呼叫（永遠放行）；繞過字樣比對改成永遠成立；放行時不寫標記。
- [ ] **Step 6: Commit** — `git add` 三個檔，訊息 `feat(openspec-workflow): archive gate denies archiving without a fresh reconcile verdict`。

### Task 3: skip-gate v2

**Files:**
- Modify: `plugins/openspec-superpowers-workflow/hooks/skip-gate.sh`（刪除 flag、`BATCH_WINDOW_SECS`、`stat` 相關段落）
- Modify: `plugins/openspec-superpowers-workflow/hooks/hooks.json`（只改頂層 `description` 的文字）
- Test: `plugins/openspec-superpowers-workflow/tests/skip-gate.test.sh`（改寫）

**Interfaces:**
- Consumes: Task 2 的歸檔標記檔。
- 決策順序（每一步命中即結束）：缺 jq → allow；非 openspec 專案 → allow；路徑在 `openspec/`、`.claude/` 或專案外 → allow；副檔名 `.md .mdx .txt .rst .adoc` 或路徑在 `<專案>/docs/`、`<專案>/doc/` 下 → allow；有 active change → allow；聲明檔不存在 → deny（缺檔訊息，有歸檔標記時用歸檔後版本）；有歸檔標記且聲明檔不比標記新（`[ "$decl" -nt "$marker" ]` 不成立）→ deny（歸檔後訊息）；聲明行缺 key 或值不是是／否 → deny（點名缺的 key）；任何一面「是」→ deny（要求 Phase 1）；否則 allow。
- 缺檔訊息必含聲明檔的絕對路徑與可直接複製的一行 `契約面：API=否 資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 跨模組=否 ｜ 理由：<一句>`。

- [ ] **Step 1: Write the failing test** — 保留既有 helper，案例改為：
  - 沿用語意的 1、4、6、7、8、9、10、11（非 openspec、有 active change、openspec 內、.claude 內、專案外、無 file_path、無 changes 目錄 → deny、session_id 消毒後聲明檔路徑落在 `.claude/openspec-skip.s11_.._evil.local.md`）。
  - 5（只有 archive）→ deny。
  - 文件豁免：`README.md`、`docs/x.txt`、`doc/guide.adoc` → allow；`src/a.php` → deny。
  - 缺檔 → deny，訊息含聲明檔路徑與 `契約面：API=否`。
  - 聲明八面全否 → allow；半形冒號與多空白（Review Focus 3）→ allow。
  - 缺 `跨模組` → deny 且訊息含 `跨模組`；`API=可能` → deny。
  - `並行=是` → deny 且訊息含 `Phase 1`。
  - 同批並行：沒有聲明時連續兩次輸入都 deny（取代舊的 3a/3b 批次窗案例）。
  - 歸檔後：建標記後再建聲明 → allow；先建聲明、`sleep 1` 後才建標記 → deny 且訊息含歸檔後版本的字樣。
  - 舊 3d／3e 的 `stat` 案例刪除（機制已移除）。
  - 開頭的 `GATE=` 改成 `GATE=${GATE:-"$SCRIPT_DIR/../hooks/skip-gate.sh"}`，供 Step 5 的突變以副本覆寫（現行寫死、不吃環境變數）。
- [ ] **Step 2: Run test to verify it fails** — Run: `bash plugins/openspec-superpowers-workflow/tests/skip-gate.test.sh`；Expected: 新案例 FAIL。
- [ ] **Step 3: Implement** — 聲明解析用 bash 內建：`line=$(grep -m1 -E '^契約面[：:]' "$decl")`，對八個 key 逐一以 `[[ $line =~ $key=(是|否) ]]` 取值。
- [ ] **Step 4: Run test to verify it passes** — 同 Step 2；Expected: 全部 PASS。
- [ ] **Step 5: Mutation check** — 以 `GATE=<副本>` 各跑一次都必須轉紅：拿掉文件豁免；拿掉「任何一面是」判斷；拿掉聲明比標記新的比較；key 檢查只看前七個。
- [ ] **Step 6: Commit** — 訊息 `feat(openspec-workflow): skip-gate v2 reads a declaration file instead of denying the first edit`。

### Task 4: 文字層與實機驗證

**Files:**
- Modify: `plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/phases.md`（Phase 5 格式段加 `final` 規則；6a 前加「先跑 `snapshot`」；6b5 改為「跑 `check`、逐項處理 manual 與 warn、verdict 為 pass 才歸檔」；6c 註明閘門與繞過字樣，並說明 `/opsx:archive` 範本的 `mv` 一樣會被攔）
- Modify: `.../SKILL.md`（description 的 skip-gate 句改為聲明檔；規則加「歸檔前跑 `reconcile-check.cjs check`」與 `final` 規則。改完量 description 字數，必須 ≤ 1536）
- Modify: `.../PHASE-IDENTIFICATION.md`（Case 3：SKIP 判定寫成聲明檔與其格式）
- Modify: `.../RECONCILIATION-CRITERIA.md`（每個 C 項標出對應的 R 編號與是否機械化）
- Modify: `plugins/openspec-superpowers-workflow/README.md`（Skip-gate 章節改寫為 v2；新增 Archive gate 章節：行為、界線、繞過、測試指令）
- Modify: `.claude-plugin/marketplace.json`（只改此 plugin 的 `description` 文字，不動 version）

- [ ] **Step 1: 改文字**，每處都依 design 第 4 節的事實，不寫 design 沒有的保證。
- [ ] **Step 2: grep 同步** — Run: `command grep -rn -F -e '批次窗' -e 'BATCH_WINDOW' -e '一 session 只完整觸發一輪' -e '僅完整觸發一輪' plugins/openspec-superpowers-workflow README.md README.zh-TW.md`；Expected: 無輸出（舊機制的描述全部改掉）。
- [ ] **Step 3: 實機驗證** — 在 `$TMPDIR` 建一個 git repo 並 `openspec init .`、建一個 change；在本 session 以 `CLAUDE_PROJECT_DIR=<該目錄>` 把 hook 輸入手動 pipe 進兩支 hook，再用真的 `openspec archive <名稱> --yes` 走一次「未核查 deny → snapshot、check → 放行 → 歸檔成功」，以及範本的 `mkdir`＋`mv` 寫法。Expected: 輸出與測試一致，歸檔後目錄落在 `openspec/changes/archive/<date>-<名稱>/`。
- [ ] **Step 4: 全套** — Run: `for s in plugins/*/tests/*.test.sh; do bash "$s" || echo "RED $s"; done; node scripts/validate-fixtures.cjs`；Expected: 沒有 `RED`，validate-fixtures 通過。
- [ ] **Step 5: Commit** — 訊息 `docs(openspec-workflow): document the archive gate and skip-gate v2`。

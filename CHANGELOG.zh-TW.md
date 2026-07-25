# 變更日誌

本專案所有重要變更都將記錄在此檔案中。

格式基於 [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)，
並遵循 [語意化版本](https://semver.org/spec/v2.0.0.html)。

## [1.9.1] - 2026-07-26

### 變更

- **openspec-superpowers-workflow 1.2.2 → 1.3.0** — SKIP 條款自「small bug fixes with no spec impact」銳化為明確的契約風險 rubric（public API / data contract / schema / migration / 向後相容 / 安全權限邊界 / 並行一致性 / 跨模組行為；以契約風險判斷，LOC / 檔案數非判準）。放在 skill 描述是因為 auto-trigger 的跳過判斷就發生在那裡——對所有安裝者自包含。`PHASE-IDENTIFICATION.md` 與根 README 同步為相同語言。

## [1.9.0] - 2026-07-26

### 變更

- **code-audit-rigor 1.5.0 → 2.0.0**（BREAKING）— `/audit-review-fix` 及其整組實作（workflow script、command、schema、validator、14 個 fixture）退役移除。理由是與 `claude-security` plugin 的 *suggest-patches* 功能重疊，而後者風險模型嚴格更優：產出 patch 檔由使用者自行審閱套用（不套用等於沒發生），而非一次 ~86 sub-agents（~400k tokens）直接改寫原始碼（回退需 `git revert`）。`/review-branch`、`/review-pr` 與 rigor skill 保留——它們以「正確性」為判準（邏輯錯誤、可維護性、測試覆蓋），這一層是以「可利用性」為判準的安全工具不涵蓋的。`scripts/validate-fixtures.cjs` 同步更新，套件全綠（125 passed, 0 failed）。遷移路徑見該 plugin 的 CHANGELOG [2.0.0]。

## [1.8.11] - 2026-07-02

### 變更

- **security-audit 1.0.0 → 1.0.1** — 為 vendored validator 加上本地 drift 防護：新增 `valid-basic.json` fixture（confirmed + rejected 兩種 finding）與單欄位 mutation，接進 `scripts/validate-fixtures.cjs`，使 repo 根 suite + CI + PostToolUse hook 現在都守護 `validate-findings.cjs`（含其兩條語意約束：trace 首步須 `entrypoint`、末步須 `sink`）。記錄 re-vendor drift 檢查：pin 的 `4de1ac8` 對 upstream HEAD `f75f9a0` 為純目錄搬移、內容零漂移。未修改任何 vendored 檔。
- **openspec-superpowers-workflow 1.2.1 → 1.2.2** — Phase 1 pre-check 路徑統一為 `${CLAUDE_PLUGIN_ROOT}`（原為 repo 相對路徑 + 「從安裝根解析」的 prose 說明），對齊其他 plugin skills/commands 的慣例。

### 備註
- 另（非 plugin）：在個人 `~/.claude/CLAUDE.md` 的 plugin 決策樹加入 `security-audit` 入口（主動獵漏 → `/security-audit`；diff/PR 治理 → `code-audit-rigor`），並將 `docs/loop-design-review-2026-07-01.md` 兩個懸空的 Tier-3 judgment call 以明確 won't-do 處置 + re-open 觸發條件收尾。Marketplace patch bump 1.8.10 → 1.8.11。

## [1.8.10] - 2026-07-01

### 變更

- **high-precision-dev 1.4.0 → 1.5.0** — 跨家族 model 指派，打破共用 base-model 的相關性地板：`implementer-a`/`adversary`/`verifier` 用 `opus`，`implementer-b`/`critic`/`disproof-agent` 用 `sonnet`，讓 builder 與 checker 橫跨兩個 model 家族。`model` frontmatter 是家族層級（配 Opus 4.8 × Sonnet 5；選不到特定舊版、同家族配對幾乎不去相關）；per-agent effort 不可 frontmatter 設定，跟隨 session `/effort`。

### 備註
- Marketplace patch bump 1.8.9 → 1.8.10。

## [1.8.9] - 2026-07-01

### 變更

- **high-precision-dev 1.3.0 → 1.4.0** — `p→p⁴` 誠實化 reframe + implementer 去相關。乘法式 `p⁴` 宣稱在所有出現處（`plugin.json` / `marketplace.json` / `README` / `start.md` / `ANTI-PATTERNS.md`）從頭條保證降級為「理想化模型 + 明確的共用 model 相關性地板 caveat」（同一 base model 的兩個 identical-prompt 實例，對系統性誤讀會同向出錯）。`implementer-a` 與 `implementer-b` 原本逐字元相同，現改為真正不同路徑（A 規格優先/由上而下、B 測試優先/行為驅動；同完整度、不同路徑），讓最弱的獨立性那條腿真正去相關。

### 備註
- Marketplace patch bump 1.8.8 → 1.8.9。

## [1.8.8] - 2026-07-01

### 新增

- **high-precision-dev 1.2.1 → 1.3.0** — Phase 4 完成前的 controller 親跑環境測試閘門。verifier 合併後，controller 自己跑 SPEC 測試套件並捕捉 exit code（`WF_TEST_EXIT=$?`），把「測試通過」從 agent prose 宣稱升級為環境事實，接進既有 capped fix-loop 的退出條件。刻意不重新引入結構化輸出合約——它是唯一通過元規則的機器閘門：*閘門有資格存在 iff (a) 讀環境事實而非 agent 斷言，且 (b) 有下游消費者據其結果行動。*

### 備註
- Marketplace patch bump 1.8.7 → 1.8.8。

## [1.8.7] - 2026-07-01

### 變更

- **code-audit-rigor 1.4.0 → 1.5.0** — `/review-branch` 新增 `--focus <pathspec>` 與 Phase 2 confidence 欄位（0-100，<67% 標記 borderline）；`/review-pr` Phase 3 回歸檢查硬化為 `/audit-review-fix` 已審過的 baseline + exit-code sentinel 紀律（捕捉修前 baseline、只數 new-vs-preexisting failure、信任 `WF_TEST_EXIT=0`、build 新壞算回歸、無法解析則 fail closed）。
- **openspec-superpowers-workflow 1.2.0 → 1.2.1** — Phase 1 新增選用的寬鬆本地 pre-check，在權威的 `openspec validate --strict` 前先跑自帶 `.cjs`（讓 plugin 自己原本只在 CI 的 validator 出現在 live workflow）。
- **high-precision-dev 1.2.0 → 1.2.1** — 移除 `start.md` 從未實作的 `--phase N` arg hint；查清 `disproof-agent` 未註冊非缺陷（frontmatter 與會註冊的 sibling 相同，是 under-versioned PR #4 的 reload 殘留，1.2.0 bump + reload 即解）。

### 備註
- loop-design review 的 follow-on 項目。Marketplace patch bump 1.8.6 → 1.8.7。

## [1.8.6] - 2026-07-01

### 變更

- **選擇性 L2 收斂**（源自 `docs/loop-design-review-2026-07-01.md`）——把 PR #4「四個 plugin 一律加 schema + validator」縮減到只保留「真的有機器消費者讀取合約」之處，而非全盤 revert（全 revert 會連帶砍掉 code-audit-rigor 真正在運作的 live validator、CI、hook 與 STEEL_MANNING）。
  - **multi-agent-debate 1.1.0 → 1.2.0** — 完成 L2：`/debate` Phase 6 現在 emit `debate-output.json` 並跑 `validate-debate-output.cjs` 當 live 結構閘門；新增跨欄位參照完整性（`selectedProposal`/`agreedProposals` 必須指向真實 `proposals[].id`）與必填、機器可檢的 `coverage` 欄位；對齊 Phase 4 收斂判準（分數差 ≥8）與 `orchestrator.md`。
  - **high-precision-dev 1.1.0 → 1.2.0** — 移除死碼 L2：六個 agent 全產 prose 報告，schema 驗的是沒 agent 會產出的 JSON 形狀。刪除 `schema/`、validators、fixtures + runner wiring；清 `README`/`start.md` 的 dangling ref。
- 移除誤留的 `t.json`（PR #4 誤入 repo 根目錄的 prior-debate 測試殘檔）。

### 備註
- 套件 148 → 133 checks（−21 移除的 high-precision checks、+6 新增 debate mutation）。Marketplace patch bump 1.8.5 → 1.8.6。

## [1.8.5] - 2026-07-01

### 修正

- **回補 PR #4 的版本 bump + changelog**（commit `893821c`）——該 PR 在四個 plugin 一律加上「結構化輸出 + zero-dependency validator + fixtures + CI + PostToolUse hook」的 L2 層，卻**沒有任何版本 bump**，使每個 `plugin.json` 在功能變更前後都停在同一個 pre-merge 版號，且兩個 plugin 根本沒有 `CHANGELOG.md`。這種歧義正是 registry 版本快取失效（新 agent/能力靜默不載入）的病灶。
  - **code-audit-rigor 1.3.4 → 1.4.0**、**openspec-superpowers-workflow 1.1.0 → 1.2.0** — 為 L2 變更回補版本 + changelog。
  - **multi-agent-debate 1.0.0 → 1.1.0**、**high-precision-dev 1.0.0 → 1.1.0** — 建立 `CHANGELOG.md`（回補 1.0.0 initial-release + 1.1.0 L2 變更）。

### 備註
- 本次無功能性程式碼變更——僅版本/changelog 衛生。Marketplace 1.8.4 → 1.8.5。

## [1.8.4] - 2026-06-29

### 修正

- **code-audit-rigor 1.3.3 → 1.3.4** — `/audit-review-fix` Verify-Fix 不再把「baseline 與 verify 兩端都壞掉」的 build 回報為 `testsPass`/`READY_FOR_COMMIT`（run-2 review 的「2b」殘留）。新增正交的 `currentlyBroken` 判斷（`errored` + 明確非零 exit），不論 baseline 如何一律 fail-closed——commit 一棵無法 build 的樹永遠不該被放行。要求明確非零 exit，故「通過但輸出含 error 字樣」不會被誤殺；純 assertion 失敗的 dirty baseline 不受影響。單元 harness 現 76 條斷言。

### 備註
- Marketplace patch bump 1.8.3 → 1.8.4。

## [1.8.3] - 2026-06-29

### 修正

- **code-audit-rigor 1.3.2 → 1.3.3** — run-2 自我稽核中 `/audit-review-fix` workflow 剩餘的 LOW/NOTE 健壯性項目（單元 harness 現 71 條斷言）：
  - `status` 不再把單獨的 `DEFER_OUT_OF_SCOPE` finding 誤報為 `CLEAN`——新增 `REQUIRES_FOLLOW_UP` status（文件已更新）。
  - fix agent 改了檔卻回 `applied=false` 時，浮出留在 tree 的未測檔案（不再被靜默標為「declined」）。
  - 組報告路徑前消毒 `today`（不可 `../` 穿越）。
  - Scope-abort 強化：「no changes」判斷加上 real-diff 守衛；bad `--focus` pathspec 現會明確中止，而非靜默審查空 diff。
  - Fix-agent prompt 強化抗 indirect prompt injection（把 diff/finding 文字當資料）。
  - EV 67% 損益平衡點經審查後刻意保留不變（忠實實作 skill 文件化的 Framework 2）。

### 備註
- Marketplace patch bump 1.8.2 → 1.8.3。

## [1.8.2] - 2026-06-29

### 修正

- **code-audit-rigor 1.3.1 → 1.3.2** — `/audit-review-fix` workflow 三個安全閘修復（fail-open → fail-closed），由自我 `security-audit` 稽核（run-2）發現並經對抗式 review，以 56 條斷言的單元測試 harness 覆蓋：
  - （HIGH）Verify-Fix 對「build 壞掉」的 compile/collection/fatal 狀態（無 `failed`/`FAIL ` token）誤報 `testsPass=true` → 無法編譯的程式樹被回報 `READY_FOR_COMMIT`。現偵測 error/no-run 狀態 + exit-code 哨符，並 fail-closed。
  - （MEDIUM）clean baseline 使 count 回歸後備失效（`baselineFailCount=null`）；現歸零為 `0`。
  - （MEDIUM）非數值／非物件 args 被 coerce 成 NaN 或讓 flag 退回 → 靜默丟棄 finding／不跑 review／移除 LOC 上限／假 `CLEAN`；現以 finiteness／object-shape 守衛驗證。

### 備註
- Marketplace patch bump 1.8.1 → 1.8.2（一個 plugin patch release）。

## [1.8.1] - 2026-06-29

### 安全性

- **codegraph 1.0.0 → 1.0.1** — 修正前置 npm 套件名：從無人擁有的 unscoped `codegraph`（第三方的 469-byte 空殼、無 `bin`）改為真正的 scoped `@colbymchenry/codegraph`。消除 dependency-confusion 風險與功能性損壞（照舊文件安裝的人，bundled MCP server 從未啟動）。由 `security-audit` 稽核發現，並以維護者實際安裝環境實證確認。
- **code-audit-rigor 1.3.0 → 1.3.1** — `/review-pr` 現在將抓取的 PR 評論（公開 PR 上任何人皆可張貼）標示為不可信資料，僅供分析、不可當指令執行，且 Phase 4 推送前要求檢視實際 diff。Defense-in-depth（`security-audit` Finding 2，LOW）。

### 修正

- 對齊 `repository`/`homepage`：`multi-agent-debate`（原指向不存在的 `chinlung/multi-agent-debate`）與 `session-learning`（原缺漏）皆改為 `chinlung/claude-dev-workflow`。純 metadata，未變動 plugin 版本。
- 新增根目錄 `.gitignore`（`node_modules/`、`.env*`、`*.pem`/`*.key`、`*.local.md`、`*.log`、OS 垃圾檔），避免貢獻者／fork 者誤提交本地設定或機密。

### 備註
- Marketplace patch bump 1.8.0 → 1.8.1（兩個 plugin patch release + repo 衛生）。

## [1.8.0] - 2026-06-29

### 新增
- **新 plugin：security-audit 1.0.0**。Vendored `security-audit` skill，源自 [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill)（MIT，© Cloudflare, Inc.），upstream commit `4de1ac8`。六階段多代理流程（recon → hunt → validate → report → structured output → independent verification），主動獵捕可被利用、有實際影響的漏洞，與 `code-audit-rigor` 的審查紀律框架互補。Vendored 檔案逐字複製；wrapper 僅加 `plugin.json` + `README.md`，記錄 Claude Code 平台對應（research → `Explore`、general → `general-purpose`）與上游同步程序（見 CONTRIBUTING §7）。

### 備註
- Marketplace minor bump 1.7.5 → 1.8.0（新增 plugin）。

## [1.7.5] - 2026-06-24

### 新增
- **code-audit-rigor 1.2.1 → 1.3.0**：新增 `/audit-review-fix`——自動化對抗式批次審查自動修 Workflow，作為 plugin 第三層併入（從使用者層 `~/.claude/` 遷入，與 1.2.0 command 遷移同一可攜性模式）。command 透過 `${CLAUDE_PLUGIN_ROOT}/workflow/audit-review-fix-workflow.js` 讀取腳本（無硬編碼 home 路徑）：9-angle review + EV triage + 安全閘門自動修 + 測試驗證 + 報告。「排除 auto-fix」的定位現在僅限量化框架 skill 本身——auto-fix 由獨立的 `/audit-review-fix` 在安全閘門 + 對抗式驗證下提供。

### 備註
- Marketplace patch bump 1.7.4 → 1.7.5。

## [1.7.4] - 2026-06-17

### 變更
- **openspec-superpowers-workflow 1.0.1 → 1.1.0**：Phase 4 對齊 superpowers v6.0.0。superpowers 6.0.0 重寫了 subagent-driven-development 的 per-task review：雙階段 review（spec / quality 兩個 reviewer）→ 單一 `task-reviewer` 一次回兩個 verdict + 結尾一次 whole-branch review（用最強 model）。新增 worktree 落點說明：v6 移除全域 `~/.config/superpowers/worktrees/`，改落專案內 `.worktrees/` root（需 git-ignore）。新增 reviewer-integrity 紀律（禁止壓制 finding、禁止預設 severity），並標註相依 superpowers >= 6.0.0。

### 備註
- Marketplace patch bump 1.7.3 → 1.7.4。

## [1.7.3] - 2026-06-08

### 變更
- **code-audit-rigor 1.2.0 → 1.2.1**：調用鏈追蹤改為 codegraph-aware。Review 子代理只看派發 prompt，而 prompt 原本硬寫「使用 Grep」——即使專案有 codegraph 索引也不會用，漏掉 dynamic-dispatch 呼叫點（callback、DI、event handler）。`/review-branch` Phase 2 與 `SKILL.md` Principle 3 現在在 `.codegraph/` 存在時優先用 `codegraph_callers`/`codegraph_impact`，無索引 fallback Grep。quotedCode 錨定刻意維持 Grep（逐字文字比對，非結構查詢）。無硬依賴——沒裝 codegraph 行為不變。

### 備註
- Marketplace patch bump 1.7.2 → 1.7.3。

## [1.7.2] - 2026-06-08

### 變更
- **code-audit-rigor 1.1.0 → 1.2.0**：把 `/review-branch` 與 `/review-pr` 從使用者層 `~/.claude/commands/` 遷入 plugin。動機：`/review-branch` 的內建規則層原本 fallback 到只在單一機器有效的硬編碼絕對路徑；進 plugin 後改用 `${CLAUDE_PLUGIN_ROOT}/rules/manifest.json`——機器無關、隨安裝出貨。Plugin 定位擴為「審查工具箱」（routine 指令 + rigor skill 共用同一套規則包）。

### 備註
- Marketplace patch bump 1.7.1 → 1.7.2。

## [1.7.1] - 2026-06-07

### 變更
- **code-audit-rigor 1.0.1 → 1.1.0**：新增三項決定性工程化保證，改編自 [alibaba/open-code-review](https://github.com/alibaba/open-code-review) 的「決定性工程 + LLM」混合設計（Apache-2.0）。差距分析：本 skill 強在深度嚴謹（EV 數學、steel-manning、STRIDE+CWE），但覆蓋率、規則特化、引用準確性原本依賴 LLM 自律——正是 OCR 用工程邏輯解決的三件事。
  - **Phase 1b 路徑匹配規則包**：新增 `rules/manifest.json`（glob → doc、first-match）+ 8 份 `rule_docs/*.md`（TS/JS/React、PHP/Laravel、Python、Go、SQL/mapper、YAML/IaC/Dockerfile、package.json、default），每份含 Review-focus 獵取清單 + 檔案類型限定的「不要報」suppression list。分層覆寫：專案 `.reviewrules/` → 使用者 `~/.claude/review-rules/` → plugin 內建。
  - **機械化 scope + coverage 核銷**：Phase 1 scope 必須來自 `git diff --name-only` / `git show` / Glob 輸出；Phase 5 將每個 scope 檔案核銷進 Read 或 Skipped，新增強制 `Unaccounted` 欄——非空即審查無效。
  - **引用程式碼 grep 錨定**：Framework 4 crossReferences 新增必填逐字 `quotedCode` 欄位；Phase 4 Step 1 在 steel-manning 前先機械 grep（宣稱行號 ±10 內找到 → 錨定；別處找到 → re-locate；整檔不存在 → 標 `UNVERIFIED_REFERENCE`、confidence −30）。
  - 文件化刻意排除：不採三區記憶體壓縮（harness 原生 compact）；suppression list 為檔案類型限定，非本 skill 拒絕的全域 hard-exclusion 清單。

### 備註
- Marketplace patch bump 1.7.0 → 1.7.1，反映既有 plugin 內容變更。

## [1.7.0] - 2026-05-30

### 新增
- **CodeGraph Plugin**（1.0.0）：單一 skill plugin，教 Claude 在有 `.codegraph/` 索引的專案裡，結構性查詢「先 codegraph 再 grep」。
  - **夾帶 MCP server**（`.mcp.json` → `codegraph serve --mcp`）：裝一次，MCP 工具在所有專案都可用——新專案只需 `codegraph init -i`，不必逐專案 `codegraph install` 或寫 `.mcp.json`。plugin 提供的工具前綴為 `mcp__plugin_codegraph_codegraph__<tool>`；需 `codegraph` CLI 在全域 PATH。
  - **兩條入口邊界**：記錄一個不直觀的事實——`codegraph serve --mcp` 只把 `trace`/`node`/`explore`/`search`/`context` 導出成 `codegraph_*` MCP 工具，而 `impact`/`callers`/`callees`/`affected`/`status`/`files` 只在 Bash CLI（實測 codegraph 0.9.7）。誰都不是超集——把 `codegraph_impact` 當 MCP 工具呼叫會失敗。
  - **動作觸發**：綁定到動作（edit/rename/remove → `impact`；改 method → `callers`/`node`；接手不熟程式碼 → `context`；追流程 → `trace`），而非只在被問問句時才用。
  - **可靠性 fallback**：某能力不是 MCP 工具時改用 CLI，絕不默默退回會漏掉動態 dispatch 呼叫點的半套 grep。
  - 漸進揭露的 `reference.md`：新專案 4 步啟用、唯讀 `settings.json` allowlist、已知坑（工具管理的 `CODEGRAPH_START/END` 區塊重新同步會覆寫、該區塊表格把 CLI 命令誤列為 MCP 工具、`daemon.pid` 不在預設 gitignore）。

### 備註
- Marketplace minor bump 1.6.1 → 1.7.0，反映新增 plugin。

## [1.6.1] - 2026-05-09

### 變更
- **code-audit-rigor 1.0.0 → 1.0.1**：`SKILL.md` 新增 Phase 5b「零確認 finding」處理指引。在 `bin/tg-fallback-send.sh` 首次實戰測試（8 個 candidate → 0 confirmed）時暴露此空缺——原 workflow 沒有明確指示「乾淨 audit 該怎麼產出 report」。新 Phase 5b 強制：(1) 即便 0 confirmed 仍須產出完整 report；(2) executive summary 必須明確說明 negative result 是 valuable 而非 absence of work；(3) dismissed findings 區塊必須含「原始 vs 重新評估 confidence」+「steel-manning 論述」+「未來條件下何時 re-escalate」的 future note；(4) 「Total dismissed prior score」健全性檢查（如果每個 dismissal 都錯了，整體成本會是多少）；(5) 鼓勵附 skill 自評段落，回饋 friction points。Phase 5 明確要求 audit report 必須存檔到磁碟（不可只在 chat 顯示）。新增一條 anti-pattern。

### 備註
- Marketplace patch bump 1.6.0 → 1.6.1 反映 `SKILL.md` 內容變更。1.6.0 的使用者仍有四個量化框架，但缺最常見結果（0 confirmed findings）的處理指引——建議更新。

## [1.6.0] - 2026-05-09

### 新增
- **Code Audit Rigor 插件**：單一 skill 插件，為「直覺不足以判斷」的高風險程式碼審查提供量化紀律（安全、密碼學、金流、IaC、不可信輸入解析器）。
  - **五項核心審查紀律原則**：(1) 先讀完再評分；(2)「我真的讀了嗎，還是用猜的？」自我提問；(3) 驗證原始碼而非依賴 diff；(4) 多 agent 共識 ≠ 驗證；(5) 漏抓真 bug 比誤判昂貴 2 倍
  - **四個量化框架**：
    1. 評分校準（+10 / +5 / +3 / +1 vs −3 false-positive 懲罰）
    2. 期望值（EV）決策閾值：`EV = confidence% × points − (100 − confidence%) × 2 × points`，≥67% confidence 才動手
    3. STRIDE + CWE 分類，內附 16 個常用 CWE 速查表
    4. 強制 crossReferences 契約（每個 finding 必含 `file:line` 證據，空陣列直接拒絕）
  - **端到端審查流程**：5 個 phase（scope / 完整閱讀 / findings 草稿 / 對抗式掃描 / 彙整報告），其中 Phase 4 對抗式掃描刻意 steel-man 反方位置，防止多 agent 共識變成 false-confidence 放大器
  - **自包含設計**：所有規則與 reference 表都在 `SKILL.md` 內，在任何電腦 install 都完整運作，不依賴 host 專案的 CLAUDE.md
  - **靈感來源** 是 `codexstar69/bug-hunter` 的對抗式 Hunter / Skeptic / Referee 流程，但**刻意排除** auto-fix with canary rollout（對 production code 太激進）、hard-exclusion lists for "settled false-positive classes"（會造成盲點）、以及 `SKILL.md` 之外的 LLM-readable 指令檔（最小化 prompt-injection 攻擊面）
- 更新 marketplace 版本至 1.6.0

## [1.5.1] - 2026-04-10

### 變更
- **openspec-superpowers-workflow 1.0.0 → 1.0.1**：強化自動觸發機制。重寫 `SKILL.md` frontmatter `description`，改用 imperative「MUST use」語氣、擴充 trigger 清單（現在也比對 `openspec` CLI 指令與 `openspec/changes/<name>/` 資料夾的存在），並明列四條禁止行為。在 `SKILL.md` 本體頂部新增「Activation reminder」段落，在 Claude 採取任何行動前錨定不可妥協的規則。這樣使用者就不需要在自己的 `~/.claude/CLAUDE.md` 維護獨立的「必須呼叫此 skill」提醒 — 同樣的 meta 指令現在隨 plugin 一併發佈。`phases.md` 不變。

### 修正
- **dev-workflow 1.0.1 → 1.0.2**：修正 `plugin.json` description 從「6 specialized agents」改為「7 specialized agents: ..., quality assurance, and documentation」。這個不一致是 2026-03-12 `35c0a9c` refactor commit 的遺漏 — 當時把版本號 revert 成對應 `CHANGELOG [1.0.1]`，卻也把 description 一併降回 1.0.0 時代的寫法，儘管 `documentation-specialist` agent 檔案從未被移除。僅 metadata 修正，無程式碼變更。

### 文件
- `README.md` / `README.zh-TW.md`：新增 `Session 經驗學習插件` 表格列、安裝指令、完整章節（自 1.4.0 起就應該要有但先前遺漏）
- `CHANGELOG.zh-TW.md`：翻譯英文版的 `[1.5.0]` 和 `[1.4.0]` entry（中文 changelog 先前停在 `[1.3.0]`）
- `marketplace.json`：將 `dev-workflow` entry 的版本從 `1.0.0` → `1.0.1` → `1.0.2` 對齊到 `plugins/dev-workflow/plugin.json`（先前版本對齊 refactor 的漂移修正）

### 備註
- Marketplace 版本從 1.5.0 → 1.5.1 反映 `HEAD` 相對於初始 1.5.0 commit 多了數個 plugin 內容變更。停留在 1.5.0 的使用者若不更新，會錯過較強的自動觸發機制和 dev-workflow description 修正。

## [1.5.0] - 2026-04-10

### 新增
- **OpenSpec + Superpowers 工作流程插件**：六階段功能開發工作流程，強制執行 OpenSpec（規格生命週期，WHAT）與 Superpowers（開發紀律，HOW）嚴格角色分離
  - 單一 skill，採用 progressive disclosure：`SKILL.md`（58 行，常駐載入）+ `phases.md`（290+ 行，需要時才載入）
  - **Phase 1 — 規格定義**（OpenSpec 主導）：proposal + specs 為使用者審核產物；design / tasks 為草稿佔位
  - **Phase 2 — 設計精煉**（Superpowers `brainstorming` → 原位覆寫 `design.md`）
  - **Phase 3 — 任務規劃**（Superpowers `writing-plans` → 原位覆寫 `tasks.md`）
  - **Phase 4 — 實作**（Superpowers `subagent-driven-development` + 強制 TDD）
  - **Phase 5 — 審查與回饋**：`[REQUIREMENT|DESIGN|CODE|CONSTITUTION]` tag 分類 + Y/N 標記，記錄到 `review-notes.md`；審查期間絕不修改 spec 檔
  - **Phase 6 — 調和與歸檔**（OpenSpec）：Clean rewrite 紀律（非增量 patch）、`tasks.md` 凍結為執行歷史、`[CONSTITUTION]` 項目改寫入 `openspec/config.yaml` 而非 feature spec
  - 前置需求段落記錄 OpenSpec CLI vs `/opsx:*` slash command 的替代選項，以及 `openspec init .`（無 `--here` flag）的 gotcha
  - Validator 嚴格性 gotcha：每個 `### Requirement:` 區塊必須在第一段出現 `SHALL` / `MUST`
  - Archive 資料夾日期前綴行為：`openspec/changes/archive/<YYYY-MM-DD>-<name>/`
  - 決策速查表（13 種情境）和 8 條反模式清單
- 更新 marketplace 版本至 1.5.0

## [1.4.0] - 2026-03-12

### 新增
- **Session 經驗學習插件**：漸進式保存對話中的有價值模式為 memory 或 skill
  - `/save-session` 命令：分析對話並保存有價值的模式為 memory 或 skill
    - 5 Phase 分析流程：掃描 → 層級判斷 → 去重合併 → 執行 → 報告
    - 自動區分全域 vs 專案層級保存位置
    - 更新優先於新建，避免記憶膨脹
    - 每次最多 1-2 項變更，精簡克制
  - Stop hook：在實質工作階段結束時輕量提醒執行 `/save-session`
    - Command 類型（非 prompt），不觸發額外 LLM 呼叫
    - Flag file 機制防止同一 session 重複提醒
    - 自動跳過短工作階段（< 10 行 transcript）
- 更新 marketplace 版本至 1.4.0

## [1.3.0] - 2026-03-06

### 新增
- **高精確度開發插件**：針對安全關鍵程式碼的多 Agent 開發模式
  - `/high-precision-dev:init` 指令用於建立 SPEC.md 和 CONSENSUS.md 模板
  - `/high-precision-dev:start` 指令用於執行 4 Phase 驗證工作流程
  - 5 個專門代理人：
    - 實作者 A/B：在隔離 worktree 中獨立進行防禦性實作
    - 批評者：使用 severity 1-5 分級系統性找出問題
    - 攻擊者：三輪紅隊攻擊（邊界、語意、假設）
    - 驗證者：最終整合，100% SPEC.md 需求覆蓋驗證
  - 透過認識論分工將錯誤率從 p 壓縮至 p^4
  - Phase 3 修復循環上限（最多 3 次），含 adversary 重新攻擊
  - 驗證者步驟零：整合前檢查 CRITIQUE.md/ATTACKS.md
  - 三級強度光譜文件（單一 Agent → /debate → /start）
- 更新 marketplace 版本至 1.1.0
- 更新 README 加入高精確度開發插件文件（中英文）

## [1.2.0] - 2025-12-19

### 新增
- **多代理辯證系統插件**：用於多角度決策的辯證系統
  - `/debate` 指令用於啟動辯論
  - 5 個專門代理人：
    - 協調者 (Orchestrator)：分析需求並配置角度
    - 角度 A/B/C (Perspective A/B/C)：從不同角度提出解決方案
    - 批判者 (Critic)：審查方案並提供量化評分
  - 根據需求類型智能配置角度
  - 量化評分系統（30分制）
  - 共識驅動決策（需≥2個代理人同意）
  - 透過多輪辯論迭代優化
  - 在關鍵決策點納入使用者參與
- 更新 README 以記錄插件集合中的兩個插件
- 新增多代理辯證系統的繁體中文文件

## [1.1.0] - 2025-12-11

### 新增
- **文件專家**代理人（步驟 7）：負責文件更新、CHANGELOG 維護和 PR 描述生成
- **handoff.md 機制**：中央狀態管理文件，用於代理人之間的無縫上下文傳遞
- 語言無關設計：適用於任何程式語言
- 繁體中文文件（README.zh-TW.md、CHANGELOG.zh-TW.md）

### 變更
- 泛化所有代理人，使其與語言/框架無關
- 改進實作專家的程式碼模式識別能力
- 強化品質保證的檢查項目
- 更新解決方案架構師的技術考量範圍
- 優化測試工程師對多語言測試框架的支援

### 修復
- package.json 中 repository 欄位格式（應為字串而非物件）
- 修正 GitHub 儲存庫 URL

### 文件
- 新增 Pahud Hsieh 的教學影片連結
- 新增貢獻者名單
- 重新編號開發流程文件以維持序列一致性

## [1.0.0] - 2024-12-11

### 新增
- dev-workflow 插件首次發布
- 6 個專門代理人：
  - 議題分析師：需求分析與使用者故事
  - 程式碼考古學家：程式碼庫探索與模式識別
  - 解決方案架構師：架構設計與方案比較
  - 實作專家：依循最佳實踐的程式碼實作
  - 測試工程師：測試規劃與執行
  - 品質保證：程式碼品質驗證與建置驗證
- 主要指令 `/dev-workflow` 支援：
  - 完整工作流程執行
  - 單一步驟執行（`--step`）
  - 從檢查點繼續（`--resume`）
- 使用 TodoWrite 進行進度追蹤
- 架構設計後的暫停點，等待使用者確認
- 完整的文件輸出至 `docs/task-{timestamp}/` 目錄

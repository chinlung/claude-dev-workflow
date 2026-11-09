# CLAUDE.md 瘦身（W4）設計：最小方案

> **狀態：** 已核准（2026-11-10）：D12 維持 20,000、D13 採方案 A；無損項目不單獨執行，改成候選清單。第一版的三層方案經獨立審查後縮小為本方案，見「審查紀錄」。實作計畫：`docs/claude-md-slimming-plan-2026-11-10.md`。
> **範圍：** 路線圖 `docs/optimization-roadmap-2026-11-09.md` 的 W4-1、W4-3（W1-2 併入）；W4-2（注入器）與第 3 層不做；W4-4 已由 W0-2 查證判為不可行；W4-5、W4-6 另案。
> **落點：** 個人設定 repo（`~/.claude`）。本文只寫主題與數字，不抄規則原文。

## 結論

- **無損項目不單獨執行，寫成候選清單。** 一條規則能拿掉或縮短，前提是有別的東西在對的時間點承接同一件事：hook 機器強制、skill 清單或 skill 本文已寫、或 ref 已有全文。lint 在超標期間已經強制「一進一出」，所以預先瘦身與「被 lint 擋住時從清單挑」效果相同，後者省下一次變更。清單寫進 `refs/claude-md-authoring.md`。壓縮規則本文（會丟判別力）的部分不做。
- **全部套用時字數約 23,420 → 約 21,200。** 不追 16,000。
- **lint 上限維持 20,000**（D12）。它其實一直在工作：檔案超標時，任何讓它比 HEAD 更長的存檔都會被擋，所以這份檔案只能持平或變短，12 次 commit 從 24,419 降到 23,420 就是這個機制的結果。第一版說「上限形同虛設」是錯的。
- **CLAUDE.md 第 116 行（plugin 具名 workflow 的子代理省略 model 時繼承 session 設定）保留**，並另做一個不依賴 mod 的第二承接者（D13）。

## 為什麼縮小範圍

### 沒有「太長所以規則被忽略」的證據

- 所有材料（字數歷史、ref 讀取、稽核腳本的違規紀錄、撰寫規範）裡，找不到任何一筆資料顯示檔案長度造成規則被忽略。
- 唯一的機器違規數據（`git -c commit.gpgsign=false commit` 20 次）全部來自單一專案、與規則新增同一天：長時 session 載入的是新增前的 CLAUDE.md。這與檔案長度無關。
- 撰寫規範（`refs/claude-md-authoring.md` §5）只有官方的質性語句與「訊號稀釋是實質成本」一句斷言。

### 20,000 是自訂預算，不是平台門檻

- 20,000 是 2026-10-19 訂的（`refs/claude-md-authoring.md` §3），理由只有成長趨勢：2026-06 至 10 月，行數 ×1.8、字數 ×4.1。
- Claude Code 自己的警告門檻（2.1.319 binary 讀碼）：每檔 `max(40000, context window × 0.05 × 每 token 字元數)` 字元，總量 `max(120000, 前者)`。在 200k 視窗下是 40,000；目前的檔案遠低於它。
- 這次 W4 開始前，`/claude-md-management:claude-md-improver` 與 `/doctor prompt-audit` 都已檢查過這份檔案。

所以 20,000 的作用是防膨脹的預算，不是品質門檻。為了它冒判別力的風險，不划算。

### ref 讀取率不能當證據

第一版用了一張「觸發情境 vs 讀了 ref」的表。重查一次性腳本後，發現三處系統性偏差：

| 偏差 | 方向 | 實測 |
|---|---|---|
| 只認 `Read` 工具；經 Bash（`cat`、`sed`、`grep`）讀的不算 | 低估 | 同一語料：`Read` 30 個 session-ref 組合、Bash 讀 42、grep 8、經 Agent／Skill 帶入 15 |
| 分母是「工具出現」，不是「規則條件出現」 | 失真 | 例：sandbox ref 的讀取條件是「取捨憑證儲存方式」，每次 push 都不讀才是正確行為 |
| 子代理不算；同 session 內不論先後都算讀過 | 雙向 | — |

修正後，「編輯 CLAUDE.md 前先讀撰寫規範」是 6/6，不是 4/6。第一版寫「0」的 ref 有五個其實有被讀。

更重要的反例：push 輸出憑證回寫錯誤共 70 次，sandbox ref 幾乎沒被讀，模型仍正確判讀為「push 已成功」。**規則被遵守、ref 沒被讀，兩者同時成立。** 讀取率量的是 ref，CLAUDE.md 每行本來就每個 session 載入，「沒被讀」不能當刪除 CLAUDE.md 條目的理由。

`scripts/audit/knowledge-usage.cjs` 的 refs 表有同樣的「只認 `Read`」偏差，列為後續項目。

## 無損候選清單（不單獨執行）

每條都指名承接者，並附重跑的查證方式。行號以個人設定 repo 1675f24 的 CLAUDE.md 為準。取用時重新確認承接者仍在。

### 整行刪除（6 行，約 510 字）

| 行 | 主題 | 承接者 | 查證 |
|---|---|---|---|
| 152 | save-session 指令 | 每個 session 載入的 skill 清單與 description | session 開頭的 skill 清單有該項 |
| 154 | claude-md-improver 指令 | 同上 | 同上 |
| 157–159 | 三個 commit-commands 指令（連同變空的段標題） | 同上 | 同上 |
| 115 | 「不可降級條優先於 skill 內建的模型選擇」 | PreToolUse hook `subagent-model-floor.sh`，依 description 擋 | 該 hook 的測試套件 ALL GREEN |

### 縮短（6 行，約 1,170 字）

| 行 | 主題 | 目標 | 承接者 |
|---|---|---:|---|
| 10 | PR 收尾 | 60 | pr-closeout skill 本文（含「各層 review 會漏什麼要說出來」）＋ merge 閘門 hook |
| 42 | refs 索引與 lint | 60 | lint hook ＋ pre-commit |
| 107 | 每次派發明示 model／effort | 100 | `subagent-model-floor.sh` |
| 141 | push 前跑 `/security-review` | 100 | push nudge hook ＋ 安全工具鏈 ref §2.6；保留「沒有 finding 不等於乾淨」一句 |
| 148 | `/claude-security` 只掃已 commit 的變更 | 40 | agent description（不得以子代理派發）＋ 錯誤訊息本身會報錯 |
| 164 | `tree` workflow | 150 | `refs/tree-workflow-experiment.md`；保留「點名時才用、fix 只吃帳本採納的 finding」 |

### 去重與搬層（約 500 字）

- **Knowledge Architecture 第 38–41、43 行（約 270 字）：** 三問與三層的定義各只留一處。執行時逐字比對兩處；不是真重複的句子不動。
- **W1-2（232 字）：** Pest／Laravel 測試條目改成 `~/.claude/rules/` 底下的 `paths:` 規則。`paths:` 規則讀寫符合的檔案時才載入，2026-10-19 已實測生效。

### 明確不動

- **第 116 行保留。** 理由與後續做法見下一節。
- 其餘條目，包括第一版第 1 層的其他縮短，都不動。

## 第 116 行：第二承接者

### 現況

這一行處理的情況是：plugin 具名 workflow（例如 claude-security 的 scan）派出的子代理省略 model 時，繼承的是 **session 設定**，不是畫面上 model-router 改寫後的主迴圈模型。2026-10-31 一次掃描的 12 個 verifier 與 4 個 researcher 因此全部跑在 haiku 上。

Workflow 的 `agent()` 不經過 Agent tool，PreToolUse 的 `subagent-model-floor.sh` 看不到它。目前唯一的機器承接者，是行程內 mod `subagent-tiers` 的判定類下限：在 `agent.spawn` 與 `turn.step` 把低於 opus 的判定類子代理改成 opus。

### mod 會在哪些情況停擺

| 情況 | 會不會出聲 | 現有防護 |
|---|---|---|
| hooks modules 的 rollout 開關為 false，所有 mod 不載入 | 會 | SessionStart hook `mods-switch-check.sh`；鍵不存在或為 null 時不出聲 |
| mod 本身沒載入（被停用、載入失敗、validator 拒載） | 不會 | 無 |
| handler 拋例外：`agent.spawn` 掛 `.catch` 直接放行 | 不會 | 無 |
| 熱重載落在派發的那一刻（model-router 已觀察到同類現象） | 不會 | 無 |
| 實際 session 中 Workflow agent 的 spawn 改寫是否生效 | — | **未實測**（`refs/subagent-model-tiers.md` §7 自列） |

停擺時，第 116 行要求「以 session 設定 ≥ opus 為準」，這只靠模型自己記得。

### 候選方案

| 方案 | 做法 | 判斷 |
|---|---|---|
| **A. SubagentStop 稽核 hook（建議）** | 子代理結束時，讀 hook 輸入的 `agent_transcript_path`，取第一則 assistant 訊息實際送出的模型與 `agent_type`。判定類（沿用 mod 的 `JUDGE_NAME_RE`）而模型低於 opus 時，告訴使用者與主迴圈：「這個判定跑在 X 上，結論不可當作驗證，請以 opus 重跑」 | 讀的是環境事實（transcript），有下游消費者（是否重跑），且與 mod 不同的執行機制（settings.json 的 classic hook），mod 停擺時仍在。代價：它是**偵測**不是**預防**，錯的模型已經跑完一次 |
| B. 擴充 `mods-switch-check.sh` | SessionStart 時確認 `subagent-tiers` 在已啟用清單 | 只抓得到「被停用或移除」，抓不到載入失敗、例外、熱重載。可作為 A 的補充，不能單獨承接 |
| C. Workflow／Skill 呼叫前的閘門 | 審查類 workflow 開跑前，若 session 設定低於 opus 就擋 | shell hook 讀不到 session 設定。transcript 顯示的是 router 改寫後的模型，2026-11-07 已證實這是錯的訊號。不採用 |
| D. 預設 session 模型設成 ≥ opus | 寫進共享 settings | 與刻意用較低 session 模型加 router 的用法衝突，屬使用者偏好，不在本方案範圍 |

`agent_id`、`agent_type`、`agent_transcript_path` 三個欄位，是從 2.1.319 binary 的 SubagentStop 輸入結構確認的。

### 方案 A 的先決查證

1. Workflow 的 `agent()` 子代理結束時是否觸發 SubagentStop，以及它的 `agent_type` 是不是具名型別（例如 `claude-security:scan-verifier`）。
2. SubagentStop hook 的輸出怎麼送到使用者與主迴圈。binary 的說明是：`additionalContext` 送給**子代理**，子代理會繼續一輪；`systemMessage` 顯示給使用者。所以要通知主迴圈，只能請子代理在最後回報的開頭加一行警告，由回報帶回主迴圈。要實測這一輪是否發生、警告是否真的到了主迴圈，以及第二次結束時 `stop_hook_active` 為 true（hook 據此不再出聲）。
3. `agent_transcript_path` 為空字串的條件（binary 中有一個分支會給空字串）。為空時靜默放行，與 `subagent-model-floor.sh` 的「只在工具錯誤時放行」一致。

已確認的事實（本機 transcript）：每個子代理的 transcript 旁有一份 `agent-<id>.meta.json`，含 `agentType` 與 `description`。Workflow 派出的子代理放在 `subagents/workflows/wf_*/` 底下，`agentType` 是具名型別（例如 `claude-security:scan-verifier`），`description` 是 workflow 的標籤。第一則 assistant 的 `message.model` 是實際送出的模型。
4. 順便補上 mod 的未實測項：在 session 設定低於 opus 時跑一次 claude-security changes scan，看 verifier transcript 第一則的 `requestedModel`。這驗的是主要承接者本身。

任一項不成立時，照實記錄，並退回 B 加第 116 行的現狀。

### 方案 A 的測試

仿照 `subagent-model-floor.sh` 的套件做法，用 fixture transcript 測試：
- 判定類 haiku → 出聲。
- 判定類 opus → 靜默。
- 實作類 haiku → 靜默。
- transcript 路徑為空或檔案損壞 → 放行。
- 同一子代理不重複出聲。

突變至少三個，每個都必須被測試殺掉：
- 拿掉模型比對。
- 拿掉判定類分類。
- 把 opus 也當成低於下限。

### 之後

A 上線並完成先決查證第 1 項之後，第 116 行可以縮成一行指標，這是另一次變更。本方案只保留它。

## lint 上限（D12）

`claude-md-lint.sh` 的判定（第 109–110、125 行）：`size_new = 整檔超過上限 && 比基線（HEAD）長`；enforce 模式下為 exit 2。也就是說，只要檔案超標，**任何讓它比 HEAD 更長的存檔都會被擋**。

| 上限 | 效果 |
|---|---|
| **維持 20,000（建議）** | 現況：檔案超標期間只能持平或變短，新增規則必須在同一次變更裡騰出等量字數（一進一出）。瘦身到 21,200 後仍是如此，直到低於 20,000 |
| 22,000 | 放寬：瘦身後到 22,000 之間約 800 字的成長不會被擋 |
| 24,000 | 更寬：現在的 23,420 就在上限內，到 24,000 之間的成長都不會被擋 |

**建議維持 20,000，不改。** 調高上限不會讓機制「開始工作」，只會放寬它。

這也改變了瘦身的效益：在這個機制下，分開提交的瘦身不會換來新增規則的空間，因為下一次的基線就是瘦身後的 HEAD。瘦身的收益只有兩項：每個 session 少載入約 2,200 字，以及少了重複的內容。

## 不做的項目與理由

### 壓縮規則本文（第一版第 1 層的其餘部分）

會丟掉判別句。審查點名的例子：
- Code Review 的「判準分野」151 → 40：會丟掉「誰攻擊、做什麼、拿到什麼」三問，而另一處引用三問的條目也同時被縮。
- sonnet、opus 兩條：會丟掉「派發 prompt 須自包含」「別降到 low/medium」「拿不定時選 opus」。hook 不擋這三個判斷。

### 第 2 層：依命令或症狀觸發的注入器

審查指出四個沒有處理的失效模式：

1. **子代理共用 session_id。** 子代理與母 session 共用 session_id、hook 會在子代理內觸發、子代理也載入 CLAUDE.md，三者同時成立。以 session_id 記「已注入」，主迴圈注入過一次，子代理就永遠收不到。
2. **compaction 後注入消失。** 注入的文字被壓縮掉了，「已注入」的標記卻還在。
3. **觸發點與失效點錯位。**
   - 「加檔不 bump 版號」的坑出在編輯 plugin 檔案時，不在 `claude plugin` 命令上。
   - 「權限拒絕被混報成別的失敗」依定義就沒有可比對的字串。
   - BSD／GNU 差異其實會無聲出錯。實測 BSD sed 的 `\+`、`\s` 不匹配而 rc=0，依第一版自己的準則不該注入。
4. **fail-open 無人察覺。**

前兩項容易修。第三項逐條分析後，10 條裡預計只剩 5–6 條可注入，收益約 1,000 多字，不值得 1–2 個 session 加兩週觀察。

Environment 段描述環境症狀的幾條（憑證回寫、codex 沙箱、兩邊的 `$TMPDIR`），比較好的做法是修環境本身，而不是注入描述。這列為後續項目，不在 W4。

### 第 3 層：審查盲點清單搬進審查 skill

不做。理由是 skill 本文只在被呼叫時載入，無法驗證有沒有被用到。第一版的理由「ref 讀取率低」不成立，見上文。

## 量測與驗收

| 指標 | 目標 | 怎麼量 |
|---|---|---|
| 候選清單每條都有承接者與查證命令 | 100% | `refs/claude-md-authoring.md` 的清單 |
| 稽核 hook 的測試（含突變） | 全綠，每個突變都被殺掉 | `scripts/hooks/tests/subagent-judgment-audit.test.sh` |
| hook 與 mod 套件 | ALL GREEN | `scripts/hooks/tests/run-all.sh` |
| CLAUDE.md 字數 | 不增加 | `claude-md-lint.sh`（第 116 行改寫不得變長） |

## PR 切分

| PR | 內容 | 依賴 |
|---|---|---|
| A | **不做**：改為候選清單，隨 B 寫進 `refs/claude-md-authoring.md` | — |
| B | 第 116 行的第二承接者（D13）：先決查證 → hook 與測試 → settings 註冊；附候選清單 | 無 |
| 後續（不在 W4） | `knowledge-usage.cjs` 的 refs 表加計 Bash 與子代理讀取；Environment 症狀規則改為修環境 | — |

## 裁決（2026-11-10 使用者核准）

| # | 問題 | 裁決 |
|---|---|---|
| D12 | lint 上限要不要改 | 維持 20,000。它在超標期間已經擋住一切成長；調高只是放寬 |
| D13 | 第 116 行的第二承接者 | 方案 A（SubagentStop 稽核 hook），B 作補充；先決查證不成立就退回 B 加現狀 |
| — | 無損項目（原 PR A）要不要做 | 不單獨做，改成候選清單 |

第一版的 D7–D11 由本版取代：
- D7：只做無損項目。
- D8：第 3 層不做。
- D9：注入器不做，因此不需決定放哪個 repo。
- D10：W1-2 併入 PR A。
- D11：不追 16,000。

## 審查紀錄

- **第一版（三層方案）的獨立審查**：最高階模型，只給原始材料，不給作者結論。結論：
  - 效益是「讓上限開始工作」，「提升遵守率」是沒有證據的假設。
  - 讀取率表有三處系統性偏差。
  - 第 1 層有兩組條目會丟判別力。
  - 第 2 層有四個未處理的失效模式。
  - 建議改走「去重＋去已機器強制的描述」，並調整自訂上限。
  
  本版逐項採納；其中 BSD sed 無聲不匹配與讀取率低估兩項，已由作者另行重現。
- **字數估計更正**：作者先前口頭估計的「約 20,500」是錯的；逐條加總為約 21,200。
- **lint 機制更正**：第一版與作者的口頭建議都說「上限形同虛設，調到 24,000 才會開始擋」。讀 `claude-md-lint.sh` 第 109–110 行後確認相反：超標期間任何成長都被擋，調高上限是放寬。審查者所說「瘦到 16.5k 後到 20k 之間的回彈不會有提示」是正確的，指的是低於上限之後的情況。

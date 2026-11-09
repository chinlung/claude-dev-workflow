# 該不該建 agent／subagent：本 repo、自建 plugin／skill 與日常流程的盤點（2026-11-01，r2）

> **範圍**：本 repo 的 11 個 plugin、`~/.claude` 底下的 skills／commands／workflows／hooks／mods，以及目前留存的全部 transcript。
> **證據**：
> - `~/.claude/projects/**/*.jsonl`：521 份主 transcript、275 份子代理 transcript 加上各自的 `.meta.json`。
> - 各 plugin 的 agent frontmatter。
> - Claude Code 2.1.316 binary 的 agent schema 與 plugin agent 載入邏輯（`strings` 抽取）。
> - `~/.claude/skills/model-router`、`subagent-tiers` 兩個 mod 的原始碼。
>
> **版本**：r1 是同日前半段在 Haiku session 寫的初稿。r2 逐條重新查證，並把歷史分析擴大到派發來源、子代理實際跑的模型、寫檔行為與 hook 擋下的紀錄。r1 有五個結論被推翻，見 §1。
> 本文件只做分析與建議，沒有改任何程式碼或設定。

---

## 0. 結論摘要（r2）

| 順序 | 建議 | 性質 | 一句話理由 |
|---|---|---|---|
| **先做（11-02 已做，見 §10）** | **處理「`inherit`／省略 model 的子代理繼承 session 設定，不是 model-router 改寫後的模型」** | 機制修正，不是 agent | 10-31 的 claude-security 掃描中，16 個判定類 agent（4 researcher、12 verifier）實際跑在 **haiku**，當時畫面上的主迴圈是 opus。floor hook 從 transcript 讀到的同樣是改寫後的模型，所以看不出來 |
| **P1（11-02 已做，見 §11）** | 建 `finding-verifier` | plugin agent（code-audit-rigor） | review-branch Phase 2 的五個步驟在 37 份驗證 prompt 裡帶到的比例不一：錨定 30/37，呼叫鏈追蹤只有 6/37，反駁框架 12/37。另外 agent 定義是 Workflow `agent()` 路徑上唯一能守住模型下限的地方 |
| **P2** | review-branch 補上「大 diff 怎麼切」的規則；`diff-reviewer` agent 是選配 | 先改 command 本文 | 19 次切塊審查都是主迴圈自己臨場決定的（command 沒寫）。quotedCode 契約帶到 18/19，帶得不錯；缺的是切法與輸出合併規則 |
| **P3（僅 high-precision-dev 一列 11-02 已做，見 §11）** | 既有 plugin agent 補 `model`／`effort` | frontmatter | 你自己的歷史裡 0 次使用（10-03 以來）。受益的是 marketplace 使用者，以及「session 預設模型很低」的情境 |
| 撤回 | ~~`diff-security-reviewer`~~ | — | 51 次安全審查派發中有 43 次緊接在內建 `/security-review` 之後，屬於內建流程，不是手寫 |
| 撤回 | ~~eval runner／grader agent~~ | — | 21 次 eval 派發全部來自工作專案 A 的 `skill-creator`；pr plugin 本來就在用 `claude plugin eval` |
| 維持 | `dev-workflow` 評估退役 | 你決定 | 0 次使用，又是線性鏈的角色 agent |

**不建議**做成 agent 的項目：scope-ledger、save-session、reflect 主流程、pr、codegraph、security-audit、openspec-superpowers-workflow、codex review、tree。這部分 r1 的判斷不變，見 §5。

你在本 session 中途執行了 `/model` Fable 並存成預設。從下一個 session 起，`inherit` 會解析成 fable：判定類不會再落到 haiku，但每個 `inherit` 子代理都改付 fable 的價錢（opus 的 2.5 倍）。「先做」那一項因此從安全問題變成成本與可預測性問題，但 floor hook 讀錯模型來源的問題仍然存在（§3.4）。

---

## 1. r2 修正了 r1 的什麼

| # | r1 的說法 | 查證結果 | r2 的處置 |
|---|---|---|---|
| 1 | 「約 30 次手寫的安全審查，多半是內建工具涵蓋不到的範圍」→ P1 建 `diff-security-reviewer` | 51 次安全類派發中，**43 次**前一個 Skill 呼叫就是 `security-review`。「two unpushed commits」「trim-fix commit」這些描述也都在內建流程裡。其餘 8 次接在 pr、scope、review-branch 之後 | **撤回**。剩下 8 次的量撐不起一個 agent |
| 2 | eval 派發「看起來像手動 ablation」，建議改用 `claude plugin eval` | 21 次全部在工作專案 A、緊接 `skill-creator`，是 skill-creator 自己的 eval 迴圈（另有 `iter3-runs`／`iter3-grade` 兩個 Workflow）。pr plugin 的記憶顯示它已經用 `claude plugin eval … --ablation with-without` | **撤回**。流程由第三方 skill 決定 |
| 3 | finding-verifier frontmatter 寫 `disallowedTools: Edit, Write`，理由是「驗證者會順手修掉」 | 200 個判定類子代理共呼叫 Edit／Write 179 次：**169 次寫進 `$TMPDIR`**（重現用的實驗檔，prompt 本來就要求「實驗檔放 $TMPDIR」），10 次是照指示寫的交付檔，**改到受審程式碼 0 次** | **移除這條限制**。它防的事從沒發生過，卻會讓最有力的證據（實際跑出來的輸出）做不出來 |
| 4 | 「claude-security 的 verifier 固定 model，防止降級」 | `scan-verifier`、`scan-researcher`、`patch-verifier` 都是 **`model: inherit`**，固定的是 `effort: xhigh` 和 `tools`。10-31 跑在 haiku 上的正是它們 | 改寫成反例：inherit 加上低 session 設定，就是判定落到 haiku 的途徑 |
| 5 | high-precision-dev 選項 A 引用 commit「same-family pairings barely decorrelate」來說明 Opus 與 Sonnet 同代、去相關有限 | 那句話在 commit 裡指的是**同一家族的不同版本**（例如 Opus 4.6 對 4.8）。commit 把 Opus 對 Sonnet 當成**跨**家族 | 改寫選項 A 的理由，不再借用那句話（§4.3） |
| 6 | finding-verifier 回傳 `PASS／FAIL／BORDERLINE` | `review-branch-results.schema.json` 的 `verdict` enum 只有 `PASS`／`FAIL`／`SKIP` | verdict 跟 schema 走，邊界情況寫進 `confidence` 和 `notes` |
| 7 | `maxTurns: 30` | 判定類子代理的工具呼叫次數 p50 13、p90 42、最多 90 | 不設，或只設 100 當失控保險。被截斷的驗證看起來會跟「有結論」一樣 |
| 8 | 「37 份 prompt 長度落差將近 10 倍，同一個角色每次重寫」 | 最長的 7,725 字元是一次驗多條的批次驗證；中位數 1,351。核心要素帶得相當穩（verdict 37/37、信心值 35/37、只讀 34/37、錨定 30/37），弱的是呼叫鏈、反駁框架、邊界處理（§3.5） | 理由改成「弱項不穩，加上 Workflow 路徑沒有模型防線」 |
| 9 | 「review-branch Phase 1 會把大 diff 切成數個區域」 | command 本文**沒有**這段。19 次切塊都是主迴圈臨場決定的 | P2 改成先補 command 規則 |
| 10 | 「floor hook 擋了 73 次」（r1 終端輸出，未寫進文件） | 73 次裡包含讀 hook 原始碼時印出的字樣。**實際擋下 19 次**：13 次缺 effort、6 次模型下限 | §3.7 用 19 |
| 11 | 「近 30 天」 | 舊 transcript 已被清掉，現存的最早一筆是 10-03。248 次是**全部留存紀錄**，而且只算主迴圈的 Agent 呼叫；Workflow 內的 32 個 agent 另計 | §3.1 標明範圍 |
| 12 | §1.2 內建 agent 清單 | 漏了 `web-fetch`：它只有 WebFetch 一個工具，正好是「工具範圍不同才獨立成 agent」的例子 | 補上 |

---

## 2. 判準：什麼時候值得把一段工作做成 agent

### 2.1 四種載體

| 載體 | 跑在哪 | 看得到什麼 | 適合 |
|---|---|---|---|
| **skill／command** | 主迴圈，同模型同 context | 整段對話、使用者、所有工具 | 需要對話脈絡、要問使用者、單一相依鏈 |
| **subagent** | 全新 context，可換模型、工具、effort | 只有派發 prompt 加上自己的 system prompt | 需要**獨立性**（驗證）、**大量讀取但只要結論**、**工具或模型跟主迴圈不同**、可並行 |
| **Workflow** | 腳本編排多個 subagent | 同上，由程式碼控制流程 | 超過 5 個獨立項目、要決定性的流程與計票 |
| **hook／mod** | harness，不經模型 | 工具輸入輸出、環境事實 | 必須零例外的規則 |

「general-purpose 加手寫 prompt」和「自訂 agent」都是 subagent。差別只在 **system prompt、工具範圍、模型與 effort 寫在哪裡**：一個每次寫在派發 prompt 裡，一個寫在有版本控管的檔案裡。所以「建不建 agent」問的其實是：**這些設定交給每次派發時的記憶，還是交給一個檔案？**

### 2.2 Claude Code 自己怎麼做

- **內建 agent 很少**，只有 general-purpose、Explore、Plan、statusline-setup、claude-code-guide、web-fetch。每個專門 agent 存在，都是因為工具範圍或模型跟 general-purpose 有實質差異：
  - Explore、Plan 唯讀，Explore 還有模型封頂。
  - statusline-setup 只有 Read、Edit，固定 sonnet。
  - web-fetch 只有 WebFetch。

  沒有一個是為了替角色取名字而建。
- **claude-security** 是 Anthropic 官方 plugin，可以拿來當範本，也可以當反例：
  - 範本的部分：description 寫「Restricted read-only … not for direct invocation」、`tools` 明列（`Agent(claude-security:explore)` 這種寫法連可以派發哪些子代理都限制住）、每個 agent 都寫 `effort`。
  - 反例的部分：判定類的 verifier 和 researcher 是 `model: inherit`，見 §3.3。
- 官方 model-migration 文件說「Separate fresh-context verifier sub-agents tend to outperform self-critique」（`subagent-model-tiers.md` §1 有引用）。**驗證是 subagent 最站得住腳的用途。**
- 每次派發的固定開銷約 61K token（同上 §2）。所以先問「派不派」，派了之後才問「做不做成 agent」。

### 2.3 2.1.316 的 agent frontmatter（從 binary 驗證）

可設定的欄位：`name`、`description`、`prompt`、`tools`、`disallowedTools`、`model`、`effort`、`permissionMode`、`mcpServers`、`hooks`、`maxTurns`、`autoCompactWindow`、`skills`（預載）、`initialPrompt`、`memory`（`user`／`project`／`local`）、`background`、`omitClaudeMd`、`isolation`、`observer`。

- **plugin agent 會忽略** `permissionMode`、`hooks`、`mcpServers`、`initialPrompt`、`observer`、`observerMessage`、`observeSubagents`，載入時印 warn：「…which is ignored for plugin agents. Use .claude/agents/ for this level of control.」
- **plugin agent 可以設 `effort`**：載入時有解析（不合法會報錯），claude-security 的 9 個 agent 全都寫了。所以 high-precision-dev README 第 55 行與 CHANGELOG 1.5.0 那句「Per-agent effort is not configurable via agent frontmatter」**已經過時**。
- 還沒驗證到的：frontmatter 的 effort 在派發時是否原樣生效。10-31 那批 claude-security agent 的 frontmatter 寫 xhigh，transcript 卻是 medium；這個差異是 `subagent-tiers` mod 把 haiku 封頂在 medium 造成的，所以無法藉此區分。

---

## 3. 歷史紀錄分析（r2 擴充）

### 3.1 範圍

- 現存資料：521 份主 transcript、275 份子代理 transcript，主迴圈 Agent 呼叫 248 次，時間是 **2026-10-03 ～ 10-31**。更早的已被清掉，`subagent-model-tiers.md` 裡 9 月的 895 次稽核無法重跑。
- 每週分布：10-04 週 47、10-11 週 20、**10-18 週 149**、10-25 週 29。集中在一週，所以單週的作業型態會左右比例。
- 專案分布：`~/.claude` 98、工作專案 A 83、本 repo 51、contract-assay 9、其他 7。
- Workflow 只呼叫過 3 次（claude-security:scan、skill-creator 的 iter3-runs／iter3-grade），裡面的 32 個 agent 不在 248 次之內。
- 子代理 `.meta.json` 的 agentType：general-purpose 234、workflow-subagent 15、claude-security:scan-verifier 12、scan-researcher 4、fork 2、claude-code-guide 2、web-fetch／code-simplifier／scan-redactor 各 1。

### 3.2 派發是誰發起的（看派發前最後一次 Skill 呼叫）

| 類別 | 次數 | 發起者 | 你能不能改 |
|---|---|---|---|
| 安全審查 | 51 | 內建 `/security-review` 43、pr 3、review-branch 3、scope 2 | 內建流程不歸你管；其餘 8 次太少 |
| finding 驗證 | 37 | **review-branch 32**、TDD 3、reflect 2 | ✓ review-branch 是你的 plugin |
| review-branch 切塊審查 | 19 | review-branch（主迴圈臨場切） | ✓ |
| simplify 各角度 | 約 84 | 內建 `/simplify` | ✗ |
| eval 執行與評分 | 21 | skill-creator（工作專案 A） | ✗ |
| 合約 audit、slippage | 約 12 | scope 之後的專案特有工作 | 專案層 agent 可以考慮，量小 |
| Builder check on design | 6 | brainstorming 之後 | 量小 |

Skill 使用次數（模型呼叫）：review-branch 37、security-review 36、scope 25（另有使用者手打 21）、simplify 13、reflect 11、code-review 8。

### 3.3 判定類子代理實際跑在哪個模型

用 description 與 agentType 篩出判定類子代理共 217 個：opus 167、fable 29、**haiku 16**、不明 5。

**16 個 haiku 全部出自 10-31 工作專案 A session 的那一次 claude-security 掃描**（scan-researcher 4 個、scan-verifier 12 個，4 個 candidate 各 3 票）。它們的 frontmatter 是 `model: inherit`，Workflow 的 `agent()` 呼叫沒有帶 model。發起掃描時，主迴圈的 assistant 訊息顯示 `claude-opus-5-5`。

這是歷史紀錄裡**唯一一次**違反「不可降級」，而且出現在**安全審查的投票面板**上。

### 3.4 為什麼畫面上是 opus、子代理卻是 haiku：model-router 只改寫主迴圈

`~/.claude/skills/model-router/hooks/register.ts` 的 `turn.step` 第一行是 `if (e.agentId !== undefined) return yield* next(e)`：它只改寫**主迴圈每一輪送出的模型**，不改 session 設定。子代理的 `inherit` 繼承的是 session 設定。

10-20 那天的對照證據：13 次省略 model 的 general-purpose 派發，主迴圈 transcript 顯示 `claude-opus-5-5`，子代理實際全是 `claude-fable-5-1`（當時的 session 設定）。10-31 的 session 設定推測是 haiku：13:08 有一輪主迴圈停在 haiku，與 router 的 `sessionPick`（把簡單 prompt 留在低於所有 tier 的 session 模型上）相符；而且當天 `inherit` 的 agent 實際跑 haiku。這是從行為反推，沒有直接讀到當時的設定值。

這會帶來三個後果：

1. **floor hook gate 1 讀錯模型來源。** 省略 model 的 general-purpose 派發，hook 從 transcript 尾端讀 `.message.model` 判斷主迴圈模型，讀到的是 router 改寫後的值。session 設定是 haiku、router 把主迴圈拉到 opus 時，hook 會放行，子代理卻跑 haiku。hook 的 stdin 欄位只有 `hook_event_name, session_id, transcript_path, cwd, scratchpad_dir, prompt_id, permission_mode, agent_id, agent_type, served_call, caller_session_id, effort`（binary 驗證），**沒有 model**，所以 hook 本身無法得知 session 設定。
2. **CLAUDE.md 這條要改寫：**「plugin 具名 workflow…唯一槓桿是呼叫時的主迴圈模型，跑前確認 ≥ opus」。在 model-router 之下，要確認的是 **session 設定的模型**，不是畫面上這一輪的模型。
3. **判定類 agent 的 frontmatter 不能寫 `inherit`。** 這是 §4 各項「改成 agent 之後」最實在的收益。

修正方向（11-02 採 (a)，見 §10）：

- **(a)** 在 `subagent-tiers` mod 的 `agent.spawn` 做下限檢查。這個事件帶 `parentModel`（型別註解：「what `inherit` resolves to」，即 session 設定）和已解析的 `subagentType`，而且可以改寫 `model`；Workflow 的 agent 也會經過它。
- **(b)** 讓 model-router 在主迴圈改寫時同步記錄 session 設定，供 hook 讀取。沒做：hook 的 stdin 沒有 model 欄位，而 (a) 已在行程內把關。
- **(c)** 把 session 預設模型維持在 opus 以上。你已經改成 Fable，代價是 inherit 都付 fable 價。

### 3.5 驗證 prompt 實際帶了哪些規則（n=37）

| 要素（review-branch Phase 2 或 CLAUDE.md 的要求） | 帶到 |
|---|---|
| verdict（PASS／FAIL、已驗證／誤報） | 37/37 |
| 信心值 | 35/37 |
| 只讀、不修改 | 34/37 |
| 引用錨定（逐字） | 30/37 |
| 67／33 信心區間 | 19/37 |
| 檢查相關測試（Phase 2 第 4 步） | 17/37 |
| codegraph 提示（只在有索引的 repo 才相關） | 13/37 |
| **反駁框架（假設是誤報再推翻）** | **12/37** |
| ugrep／`grep -F` 提醒 | 11/37 |
| 邊界處理 | 9/37 |
| **呼叫鏈追蹤（Phase 2 第 3 步）** | **6/37** |

prompt 長度中位數 1,351 字元。開頭的角色宣告至少有 5 種寫法（「你是程式碼審查的獨立驗證者」「…（判定類）」「你是獨立的程式碼審查驗證者」「你是程式碼審查建議的獨立驗證者」等），每種只出現 3–4 次。

**解讀**：主迴圈每次都靠記憶重新寫出 Phase 2，**機械性的部分帶得穩，需要多走一步的部分常被省略**。呼叫鏈追蹤和反駁框架正是決定驗證品質的兩項：前者抓 dynamic dispatch 的呼叫者，後者對抗確認偏誤。

（判定是用正則對 prompt 文字比對；中文正則已確認以 UTF-8 正確比對，r1 終端輸出的第一版沒有，數字偏低。）

### 3.6 判定類子代理有沒有改過檔（n=200）

- 46 個用過 Edit／Write，共 179 次：`$TMPDIR` 169 次、交付檔 10 次（contract-assay 的 `harness/findings/*.json`，prompt 要求寫的），**受審程式碼 0 次**。
- 寫入型 Bash 的計數因為正則會把 `2>/dev/null` 也算進去，不採用。
- 巢狀派發：子代理 transcript 中 **0 次**。

### 3.7 floor hook 實際擋下的 19 次

| 類型 | 次數 | 例子 |
|---|---|---|
| 缺 effort（gate 2） | 13 | 「Simplify r1: reuse」等 10 次、「Builder check on design」2 次、「Slippage pass」1 次 |
| 模型下限（gate 1） | 6 | 「Simplify review: reuse angle」等 4 次帶 sonnet、「安全審查：本 PR 的 commit diff」省略 model 時 session 在 sonnet |

**同一件工作被分到兩邊**：「Simplify **review**: reuse angle」被當成審查（要求 opus、effort 省略），「Simplify r1: reuse」被當成產物（要求明示 effort）。差別只在模型寫 description 時有沒有寫出 review 這個字。「Builder check」「Slippage pass」本質上是判定，卻被當成產物類。

這就是「用正則猜 description」的極限：**分類綁在措辭上，不是綁在任務型別上**。agent type 是結構性的型別，不受措辭影響。

### 3.8 自建 plugin agent 的使用量

10-03 以來，dev-workflow、multi-agent-debate、high-precision-dev 的 agent **都是 0 次派發**，對應的 command 也沒有呼叫紀錄。

---

## 4. P1～P3 改成 agent 前後的詳細差異

每項分成四段：現況流程、改了之後的流程、逐面比較、用歷史數字估實際差多少。

### 4.1 P1 — `finding-verifier`

#### 現況（以 review-branch 為例）

1. 主迴圈跑完 Phase 1，手上有 N 條建議。
2. 主迴圈**憑記憶**把 Phase 2 的五個步驟、信心區間、輸出格式改寫成 N 份 prompt。每份 1–2K 字元，寫法每次不同。
3. 用 general-purpose 派發，`model: "opus"` 要記得寫（floor hook 會擋漏寫的，前提是 description 含審查字眼）。
4. 子代理拿到完整工具和 24K 字元的 CLAUDE.md，照它收到的那份 prompt 做。prompt 漏了呼叫鏈追蹤，它就不追。
5. 回來的格式不一定對得上 `verifications[]`，主迴圈要再整理一次才能交給 `annotate`。

#### 改了之後

1. 同上。
2. 主迴圈只傳 finding 本身（主張、檔案、逐字引用、行號、suggestion 索引），約 300–600 字元。
3. `subagent_type: "code-audit-rigor:finding-verifier"`，加上 `model: "opus"`（floor hook 修好之前仍要寫，見 §6.1）。
4. 子代理的 system prompt 是固定的 agent 本文：五個步驟、反駁框架、67／33 區間、ugrep 提醒、輸出 schema 每次都在。
5. 輸出直接符合 `verifications[]`。

frontmatter 草稿：

```yaml
---
name: finding-verifier
description: Refute-first verifier for one code-review or scan finding. The caller passes the claim, file, verbatim quoted code, line and suggestion index; returns a verdict (PASS/FAIL/SKIP per review-branch-results schema), confidence 0-100 and file:line evidence. Dispatched by /review-branch Phase 2 and similar per-finding checks — not for open-ended review.
model: opus
disallowedTools: Agent
---
```

- **保留** Write／Edit：要在 `$TMPDIR` 做重現實驗（§3.6）。
- **不設** `effort`：照你的規則，判定類繼承 session 高檔。
- **不設** `maxTurns`：p90 是 42，截斷比失控更危險。
- **不設** `memory`：見 §6.3。
- `disallowedTools: Agent` 沒有成本，因為巢狀派發從來沒發生過。

#### 逐面比較

| 面向 | 現況 | 改了之後 | 差異的實際大小 |
|---|---|---|---|
| **主迴圈路徑的模型** | 呼叫端寫 `opus`，加上 floor hook | 呼叫端寫 `opus`，加上 hook，再加上 frontmatter `opus` | 小：現況在這條路徑上沒出過事（opus 167、fable 29） |
| **Workflow／tree 路徑的模型** | `agent()` 不經 floor hook；腳本漏寫 model 就繼承 session 設定 | `agentType: 'code-audit-rigor:finding-verifier'` 會用 frontmatter 的 `opus` | **大**：這是 10-31 claude-security 出事的同一條路徑；目前 frontmatter 是唯一不靠呼叫端記性的防線 |
| **Phase 2 步驟完整度** | 呼叫鏈 6/37、反駁 12/37、邊界 9/37、測試 17/37 | 每次都在 | **大**：品質差異集中在這裡 |
| **輸出接回 annotate** | 格式靠 prompt 描述，主迴圈要整理 | 固定 schema | 中 |
| **floor hook 分類** | 靠 description 措辭（§3.7） | type 可以結構性判定（hook 要配合改，§6.1） | 中 |
| **scope-ledger triage** | general-purpose 有明示 type，不觸發 `AGENT_RE` | `finding-verifier` 含 `verifier`，**會觸發**：只注入政策、不計輪 | 小：這符合 hook 的原始設計意圖（`AGENT_RE` 本來就列了 verifier），但每輪會多看到一行提示 |
| **改檔風險** | prompt 要求只讀，實際改到受審程式碼 0 次 | 一樣 | 無：r1 宣稱的「結構性不改檔」對 Bash 也擋不住，而且沒有要解決的問題 |
| **token** | 每次 prompt 約 1.35K 字元 | 約 0.5K 字元，加上一份固定 agent 本文 | 可忽略：61K 固定開銷才是大頭 |
| **可測性** | prompt 每次不同，無從測起 | 可以做突變測試：假 finding 要回 FAIL，真 finding 要回 PASS | 中 |
| **維護成本** | 無 | 改 Phase 2 規則時，command 和 agent 要一起改；plugin 要 bump 版號 | 有，但可以接受：同一個 plugin 內的兩個檔案 |
| **失敗模式** | 漏步驟無聲 | agent 本文寫錯會**一致地錯** | 要靠突變測試守住 |

**結論**：值得建。收益來自兩個地方：**弱項步驟被固定下來**，以及**Workflow 路徑有了模型防線**。r1 列的「token 成本」「不改檔」兩項，實際收益都趨近 0。

### 4.2 P2 — review-branch 大 diff 切塊

比較三種狀態：

| 面向 | 現況（主迴圈臨場切） | 只改 command（補切塊規則與 reviewer 模板） | command 加上 `diff-reviewer` agent |
|---|---|---|---|
| 何時切、怎麼切 | 每次臨場決定：「Review A／B／C」「r4: git hooks／test suites／docs, CI, rest」 | 寫明門檻（例如變更檔數或行數）與切法（依 `resolve-rules` 的 risk tier 或路徑分組） | 同中間欄 |
| Phase 1 規則帶到率 | quotedCode 18/19、規則包 13/19、只列有可觀察後果的建議 8/19、`dismissed` 5/19、JSON 輸出 9/19 | 模板固定帶上 | 固定在 agent 本文 |
| 結果合併 | 主迴圈自己把各塊 JSON 拼成 `review-branch-results.json`，格式不一 | 規定各塊輸出 `suggestions[]` 片段、主迴圈只做串接 | 同中間欄 |
| 模型防線 | 呼叫端加 hook | 同左 | 再加 frontmatter；只有在用 Workflow 跑切塊時才有差 |
| 成本 | — | 改一個檔 | 再多維護一個 agent，且要跟 command 同步 |

**結論**：先做中間欄。quotedCode 契約本來就帶得好，真正缺的是「切的規則」和「合併的規則」，而這兩件事屬於 command 的流程，不屬於 reviewer 的角色。等改用 Workflow 平行跑切塊時，再補 agent。

### 4.3 P3 — 既有 plugin agent 的 frontmatter

#### 現況

- multi-agent-debate、dev-workflow 都沒寫 model，等於 `inherit`，解析成 session 設定。
- high-precision-dev 的 critic 和 disproof 是 sonnet。

#### 改了之後

| agent | 改成 | 改之前在不同 session 設定下的實際模型 | 改之後 |
|---|---|---|---|
| debate critic、validator、orchestrator | `model: opus` | session 是 haiku 就跑 haiku；是 fable 就付 fable 價 | 一律 opus |
| debate perspective-a/b/c | `model: opus` | 同上，而且 description 不含審查字眼，floor hook 擋不到 | 一律 opus |
| dev-workflow quality-assurance、solution-architect | `opus`（如果保留這個 plugin） | 同上 | opus |
| dev-workflow implementation、test | `model: sonnet`、`effort: high` | 同上 | sonnet high |
| high-precision-dev critic、disproof | 見下 | sonnet；派發若被 floor hook 擋，模型會改帶 opus 重派 | 看你的決定 |

**差異的實際大小**：

- 對你：目前是 0，因為這三個 plugin 在現存紀錄裡沒有使用。
- 對 marketplace 使用者：session 設定低於 opus 的人，判定類從「跟著 session 走」變成「保證 opus」。
- 成本方向兩邊都有：session 是 fable 的人反而變便宜（opus 是 fable 的 0.4 倍）。

**high-precision-dev 的取捨**（需要你決定）：

- **選項 A**：critic、disproof 改 opus，把跨廠商的去相關交給 codex。
  - 理由一：你的 CLAUDE.md 寫明判定類 ≥ opus，而且優先於 plugin 內建的選擇。
  - 理由二：在你的環境裡，sonnet 那一半本來就很容易被 floor hook 擋下、改派 opus，README 承諾的跨家族配對實際上不會發生。
  - 理由三：真正異質的檢查者（不同廠商、不同訓練資料）是 codex。
- **選項 B**：保留 sonnet，在 floor hook 加例外，並在 CLAUDE.md 不可降級條註明。代價是「判定類用 sonnet」會成為一個被引用的先例。

不論選哪一個，README 第 55 行與 CHANGELOG 1.5.0 的 effort 說法都要更正（§2.3）。

### 4.4 撤回的兩項：為什麼前後差異趨近 0

- **diff-security-reviewer**：43/51 的派發由內建 `/security-review` 的流程產生，派發 prompt 的結構由內建 skill 決定。建了自訂 agent，也不會被那條流程使用，除非另外在 CLAUDE.md 要求主迴圈改派它，那等於改寫內建流程。剩下 8 次一個月的量，不值得多維護一個檔案。
- **eval agent**：skill-creator 的迴圈與 `claude plugin eval` 都已經定義好執行者和評分者。r1 提到的 `omitClaudeMd` 基準組汙染問題，在 skill-creator 的流程裡確實可能存在（基準組子代理照樣帶著你的 CLAUDE.md），但那要改的是 skill-creator 的用法，不是建 agent。

---

## 5. 不建議做成 agent 的項目

| 項目 | 為什麼留在 skill／hook |
|---|---|
| scope-ledger | 要改主迴圈的帳本狀態；六個 hook 要讀主迴圈的工具呼叫 |
| session-learning `/save-session` | 要讀整段對話；subagent 只拿得到派發 prompt |
| session-reflect 主流程 | 同上，還要跟使用者互動勾選；它內部的驗證步驟可以改用 §4.1 的 agent（沒裝 code-audit-rigor 時退回 general-purpose 加 `model: opus`） |
| pr skill | 需要本次工作的脈絡，屬於單一相依鏈 |
| codegraph | 是工具使用知識，不是一項任務 |
| security-audit | vendored，re-vendor 流程不改本文 |
| openspec-superpowers-workflow | lifecycle owner；實作階段已經交給 superpowers SDD |
| codex review | 已經是 mod 工具；獨立性來自另一個廠商 |
| tree workflow | 腳本已經寫死每個 `agent()` 的分層；但如果要讓它的 Check 階段共用 §4.1 的驗證規則，可以改用 `agentType: 'code-audit-rigor:finding-verifier'`（`workflow-gotchas.md`：agentType 與 `subagent_type` 同源） |
| 搜尋與盤點 | 內建 Explore 加 `model: "haiku"` |

---

## 6. 配套與陷阱

### 6.1 floor hook 要改兩處

1. **自訂 agent 省略 model 會被擋**（第 104–107 行：type 不是 general-purpose 一律 deny）。可以讀 `~/.claude/agents/<type>.md`、`<repo>/.claude/agents/<type>.md`，或 plugin cache 的 frontmatter，`model` 是 opus 或 fable 就放行；gate 2 同理讀 `effort`。在這之前，呼叫端照樣明示 `model: "opus"`。
2. **主迴圈模型的來源錯了**（§3.4）：省略 model 時繼承的是 session 設定，transcript 裡的是 router 改寫後的值。修正選項見 §3.4 的 (a)(b)(c)。

依你的 Test/Gate 紀律：每個新分支至少兩個觸發輸入，並對「讀 frontmatter」與「讀 session 模型」兩條路徑各做突變測試。

### 6.2 放在哪一層

| 層 | 適合 | 限制 |
|---|---|---|
| plugin（本 repo） | 綁在某個 plugin 流程上的角色（finding-verifier 對應 review-branch） | 會忽略 `permissionMode`／`hooks`／`mcpServers` 等欄位；改內容要 bump 版號，已安裝的副本才拿得到 |
| 使用者層 `~/.claude/agents/` | 你個人跨 repo 的流程 | 在 sandbox 的 denyWrite 清單上；跟個人設定 repo 一起同步 |
| 專案層 `.claude/agents/` | 只對某個 repo 成立（例如 contract-assay 的合約 audit） | 會跟著 repo 給協作者 |

### 6.3 `memory`：判定類不要用

累積下來的「上次這類 finding 是誤報」會變成錨定偏誤，抵消 fresh context 的獨立性。precision 統計已經由 scope-ledger 的 `stats` 在做。

### 6.4 `omitClaudeMd`：審查類不要用

CLAUDE.md 裡的「專案 MUST 守則命中即採納」「grep 命中 ≠ live code」正是審查要用的；而且專案層 CLAUDE.md／AGENTS.md 也會一起被省略。

### 6.5 description 會被主迴圈拿來自動委派

驗證類的 description 要寫明輸入是「一條具體 finding」，並寫上「not for open-ended review」。

### 6.6 `inherit` 的成本面

session 預設改成 Fable 之後，所有 `inherit` 的子代理都跑 fable，包括 claude-security 的 verifier 面板。這是安全的，但比 opus 貴 2.5 倍。判定類 pin 在 `opus` 同時解決了「太低」和「太貴」兩種偏差。

---

## 7. 落地順序與驗證方法

1. **先處理 §3.4**：決定採用 (a)、(b)、(c) 哪一種；把 CLAUDE.md 那條「跑前確認 ≥ opus」改寫成看 session 設定（改之前照你的規則先讀 `claude-md-authoring.md`）。
2. **建 `finding-verifier`，並讓 review-branch Phase 2 引用它**，同時改 floor hook 第 1 處（§6.1）。驗證三件事：
   - **模型**：從主迴圈和從 Workflow `agent({agentType})` 各派一次，看 `subagents/agent-*.jsonl` 的 `"model"`。session 設成 haiku 時也要是 opus，這一步才算證明 frontmatter 有效，而不是跟呼叫端參數重疊。
   - **保護力（突變）**：quoted code 不存在的假 finding 要回 FAIL；已知為真的 finding 要回 PASS。
   - **步驟完整度**：抽 10 次派發，確認呼叫鏈追蹤與反駁框架出現在子代理的實際工具呼叫裡（不只是 prompt 寫了）。
3. **補 review-branch 的切塊規則**（§4.2 中間欄）。
4. **P3 frontmatter**：等你對 high-precision-dev 的選項 A／B 與 dev-workflow 的去留做了決定，再一起改並 bump 版號。
5. 一個月後用 §3 的方法重抽一次：判定類子代理的實際模型分布、驗證 prompt 弱項的覆蓋率、floor hook 擋下次數。

---

## 8. 尚未驗證／不確定

- frontmatter `effort` 派發時是否原樣生效：claude-security 有寫、binary 也有解析，但手上的實例都被 `subagent-tiers` 的 haiku 封頂蓋過。
- `subagent-tiers` 的 `agent.spawn` 事件裡，`parentModel` 拿到的是 session 設定還是 router 改寫後的模型：§3.4 (a) 的前提，未實測。
- 判定類、驗證類的篩選靠 description 與 agentType 的正則，有 5 個子代理讀不出模型。§3.5、§3.6 的要素比對是文字層級，不代表子代理實際有做那個步驟。
- 現存紀錄只有 4 週，而且 10-18 那一週佔六成，比例會受單週作業型態影響。

---

## 9. 2026-11-02 補充：side agent 提示的核對

side agent 提示的內容：「某次 claude-security 掃描的 12 個 scan-verifier 與 4 個 scan-researcher 實際跑在 Haiku、effort medium；原因是 frontmatter `model: inherit` 跟著當時主對話的模型（Haiku），`effort: xhigh` 又被 subagent-tiers 封頂成 medium。」

### 9.1 與 §3.3／§3.4 對照

| 提示的說法 | 核對結果 |
|---|---|
| 16 個判定 agent 跑在 haiku、effort medium | **正確**，§3.3 已列 |
| 原因是 frontmatter `inherit` | **正確**，§3.3 已列 |
| 「跟著當時主對話的模型（Haiku）」 | **不精確**。當時主對話是 **opus**（model-router 改寫後）；子代理跟的是 **session 設定**的 haiku（§3.4）。證據見 9.2 |
| xhigh 被 subagent-tiers 封頂成 medium | **正確**。§2.3 只把它當成判斷 effort 是否生效的干擾因素，沒有單獨列為傷害：模型降級之外，推理強度又被降了一次 |
| 沒查到是哪個 repo | 已查到，見 9.3 |

### 9.2 根因的證據鏈（已排除其他可能）

- **是 Claude Code 自己請求了 haiku，不是服務端替換**：verifier transcript 每一筆 assistant 紀錄的 `requestedModel` 都是 `global.anthropic.claude-haiku-5-5`（binary：`requestedModel: Z.model`，即送出的請求模型）。同一時段明示 `model: "opus"` 的 scan-redactor，`requestedModel` 是 `global.anthropic.claude-opus-5-5`。
- **session 預設確實是 haiku**：本 session 開場的模型就是 Haiku 5.5（使用者 2026-11-02 才用 `/model` 改成 Fable 並存為預設）；那個 session 17:13 的主迴圈 model identity 也宣告為 haiku。
- **沒有環境變數強制子代理模型**：`CLAUDE_CODE_SUBAGENT_MODEL`、`CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL` 都沒設，settings 的 `env` 也沒有。
- **15:11 主迴圈為什麼是 opus**：`/claude-security` 被 harness 展開後送進 `turn.start`（送進去的是 skill 全文還是標記列未實測，見 §10.4；確定的是不是指令名），model-router 的分類器判定涉及安全（risky），拉到 RISK_FLOOR 的 opus。Workflow 的 agent 繼承的是 `parentModel`，型別註解寫明「what `inherit` resolves to」，也就是 session 設定，不是改寫後的主迴圈模型。

### 9.3 提示沒看到的第二個受害點：主迴圈自己的判定工作

同一個 session 13:08，使用者打 `/code-audit-rigor:code-audit-rigor`。這個 slash 指令**沒有被展開**（是模型接著呼叫 Skill tool 載入的），router 看到的是原始指令名稱，不在 `COMMAND_RE` 內，所以不路由，結果**整段嚴謹審查在 haiku 主迴圈上執行**。router 上線（10-09）之後，主迴圈在低於 opus 的模型上執行審查類 Skill 的紀錄：`/security-review` 在 sonnet 上 3 次（10-19 兩次、10-20 一次），`code-audit-rigor` 在 haiku 上 1 次。

### 9.4 那次掃描與結果的可信度

- **掃描範圍**：`<工作專案 B>`，分支 `<功能分支>`，範圍 `5937fc0b..7ef3b6fa`，57 個檔、約 6,197 行，medium effort，工作樹是 dirty 狀態。
- **掃描結果**：4 項（HIGH 1、MEDIUM 1、LOW 2）。F1（v2.8／v2.9 萊爾富回呼可替全家訂單入帳）由 3/3 個 haiku verifier 確認。
- **後續處理**：主迴圈（opus）逐項核對後，判 F1、F2「前提不成立」，依帳本規則分類。結果在 `CLAUDE-SECURITY-20261031-151433/`；**沒有寫進 `security-scans.log`**，工作專案 B 與工作專案 A 兩個 repo 都沒有這個檔。
- **判讀**：haiku verifier 的「確認」有兩項被 opus 推翻，顯示驗證面板偏向誤確認。更大的風險在 researcher：**那次掃描「沒找到其他問題」的部分不可信**。建議在 session 模型 ≥ opus 下，用同一個範圍重跑 changes scan，並補上 `security-scans.log` 的紀錄。

### 9.5 新查到的機制事實（binary 2.1.316）

- **`CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL`**：設定後覆寫**所有** Workflow agent 的模型，連 `agent()` 明示的也會被忽略（log：「Workflow agent model X ignored」）。不採用，因為會蓋掉 tree.js 刻意設定的分層。
- **plugin agent 的 `effort` frontmatter 會被解析**，不合法時報錯；`permissionMode`、`hooks`、`mcpServers` 會被忽略並印 warn（§2.3 已列）。
- **hook stdin 沒有 model 欄位**，floor hook 無法得知 session 設定（§3.4）。

---

## 10. 2026-11-02 補充：兩個 mod 的修正

兩個 mod 都在 `~/.claude/skills/`（隨個人設定 repo 版控），版本 0.1.0 → 0.2.0。改法照 TDD：先寫紅測試，再實作，最後對每個新分支做突變測試。

### 10.1 `subagent-tiers`：判定類模型下限

| 掛點 | 行為 |
|---|---|
| `agent.spawn` | 判定類、沒明示 model、不是 fork，且 `parentModel` 低於 opus → 直接把 model 改寫成 `opus`。Workflow 卡住後的重試不會再經過 spawn hook（d.ts：「a stalled agent's retry is not raised again」），所以模型要在這裡定下來 |
| `turn.step` | 進來的模型仍低於 opus（agent 自己的 frontmatter 寫 sonnet／haiku）→ 改送 `opus`；effort 封頂改看送出的模型。迴圈中途引擎解析出不同的模型（host fallback）就停止拉高 |
| 判定類的認法 | 具名 agent 看 `:` 之後的名稱（`pr-review-toolkit:code-simplifier` 不算）；generic 型別（general-purpose、workflow-subagent、claude）看 description，用 `subagent-model-floor.sh` 的同一對正則 |
| 刻意不管 | 明示的 model（tree.js 每階段刻意指定；主迴圈那條由 shell hook 把關）、fork、不認得的模型家族 |
| 顯示 | band 與 `/subagent-tiers` 多一欄 `judgment→opus N`；舊 session 存的 tally 沒有這個欄位時讀成 0 |

### 10.2 `model-router`：審查類 skill 的主迴圈下限

主迴圈執行審查、稽核、安全類 skill 時，該 turn 其餘請求至少用 risk floor（預設 opus:high），只升不降。三個掛點對應三種進入方式：

| 進入方式 | 掛點 | 10-31 的對應案例 |
|---|---|---|
| 正常打出的 slash 指令（引擎展開） | `prompt.submit`：`command.name` 是引擎設的指令名；`turn.start` 看到的不是指令名（實際是 skill 全文還是 `<command-message>` 標記列，未實測，見 §10.4） | 15:11 `/claude-security` 被分類器當成 risky 才上 opus，純屬運氣 |
| 沒被展開的變體 | `turn.start` 的 slash 分支 | 13:08 ` /code-audit-rigor:code-audit-rigor`（開頭多一個空格） |
| 模型自己載入 | `tool.call{Skill}` | 13:08 接著呼叫的 Skill tool |

附帶發現並修正：`prompt.submit` 也把非審查的 workflow 指令名（commit／push／merge…）接到 command floor。原本只看 `turn.start` 文字的設計，對展開型指令從來沒有生效過。另外子代理的 `turn.start` 不再問分類器：原本每個子代理啟動都打一次 ollama，`turns` Map 也不會清。

### 10.3 審查與驗證

- 獨立審查（opus 子代理）7 條：6 修、1 判定為刻意（升階只看模型家族、不看 effort，沿用 router 既有的 ratchet 語意）。詳細在本 repo 的 scope-ledger Log。
- 測試：subagent-tiers 4 → 12 支，model-router 52 → 62 支。
- 突變：36 個（subagent-tiers 16、model-router 20），全部被測試抓到。突變腳本在 `$TMPDIR/mutate.mjs`（session 暫存，未入版控）。
- `claude plugin validate` 兩個都過；`tsc` 對兩個 register 檔都是 0 錯誤（model-router 的測試檔有 54 個既有的 implicit-any，與本次無關）。

### 10.4 仍未實測

- 真實 session 裡 Workflow agent 的 `agent.spawn` model 改寫是否生效、重試是否沿用。驗法：在 session 設定低於 opus 時跑一次 claude-security changes scan，看 `subagents/workflows/*/agent-*.jsonl` 的 `requestedModel`。
- 展開型 slash 指令的 `prompt.submit` → `turn.start` 順序與一對一關係。驗法：在 haiku session 打 `/code-audit-rigor:code-audit-rigor`，第一個 assistant 紀錄的 `requestedModel` 應為 opus。
- 兩者都要在 mod 載入的 session 做；sandbox 內跑過 `claude plugin test` 後要確認 `tengu_plugin_hooks_modules` 沒被存成 off。

## 11. 2026-11-02 補充：P1 與 P3 的 high-precision-dev 落地

- **P1 已做（code-audit-rigor 2.2.0）**：`agents/finding-verifier.md`，frontmatter `model: opus`、`disallowedTools: Agent`，不設 `effort`／`memory`／`maxTurns`。`/review-branch` Phase 2 改派它，並明示 `model: "opus"`（frontmatter 也是 opus；明示是為了相容會擋「具名 agent 沒帶 model」的 floor hook）。agent type 不存在時退回 `general-purpose`、帶 opus，請它先 Read agent 檔。
- **與 §1 第 6 列不同之處**：邊界情況最後**不是**「寫進 `confidence` 和 `notes`、verdict 照給」，而是帶 `suggestion` 索引的 `SKIP`、`notes` 以「邊界：」開頭。原因是 `review-branch-rounds.cjs` 的 `annotate` 會把每個 `FAIL` 記成 dismissed，`plan` 會把檔案未變的 `PASS` 帶成 carried，兩者都不讀 notes；硬給的 verdict 會被跨輪當成定論（自審時 review-branch 與 codex 各自抓到）。殘餘缺口：檔案下一輪沒變時邊界項不會再出現，已列入 follow-ups。
- **P3 只做了 high-precision-dev 一列（1.6.0）**：選項 A，critic 與 disproof-agent 改 `opus`，`/start` 每個判定類派發明示 `model="opus"`，README 與 CHANGELOG 更正「agent 的 effort 不能寫在 frontmatter」。multi-agent-debate、dev-workflow 等其他列**仍未做**。
- 守門測試：`plugins/code-audit-rigor/tests/finding-verifier.test.sh`（15 項）、`plugins/high-precision-dev/tests/agent-models.test.sh`（13 項），派發的 model 都比對 frontmatter 而非寫死；突變 22 個全部被抓到。
- 仍待做（follow-ups）：floor hook 解析具名 plugin agent 的 frontmatter（修好後可拿掉呼叫點的 `model=`）、Phase 2 依檔案併批派發的評估、跨 plugin 的判定類模型閘門。

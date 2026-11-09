# Lifecycle owner 體檢與知識落點審查（2026-11-09）

> 兩個問題：
> Q1. openspec-superpowers-workflow（唯一的 lifecycle owner）有沒有被深入分析過，能否依歷史紀錄與業界做法優化？
> Q2. 目前寫在 CLAUDE.md 或 `refs/*.md` 的東西，落點對嗎，該不該抽成 skill、hook、mod？
>
> 原始材料：
> - transcript：1,445 個 jsonl（859 個 main session、586 個 subagent），2026-09-12 至 11-08，共 314,533 行。腳本是 `scratchpad/mine/mine.cjs`，可重跑。
> - 歸檔：16 個專案共 279 個 archived change（2026-04 至 11），腳本是 `scratchpad/arch/arch.cjs`。
> - 其他：plugin 原始碼與 19 筆 commit、本機 OpenSpec 1.16.1 的 CLI help、本機已安裝的 `/opsx:*` 指令全文、`~/.claude` 的 git log、settings.json 的 hooks。
>
> 所有自產統計都先抽樣分類過，誤命中的類別已剔除，標在各段。

---

## Q1. Lifecycle owner 體檢

### 1.1 實際用量（transcript 視窗約兩個月）

| 指標 | 數值 |
|---|---|
| 載入 workflow skill 的 session | 10 個（13 次載入；分布在 6 個專案） |
| 同一 session 寫齊 proposal、spec、design、tasks、review-notes 五個產物 | 8／10 |
| 在 session 內跑了 `openspec archive` | 9／10 |
| CLI 呼叫（只計命令位置的已知子命令） | validate 242、archive 32、new 30、instructions 12 |
| 使用者打 `/opsx:*` | **0**（使用者用自然語言，由 agent 呼叫 CLI） |
| superpowers skill（10 個 session 中有幾個用過） | brainstorming 5、executing-plans 5、writing-plans 4、TDD 4、**subagent-driven-development 0**、**requesting-code-review 0** |
| plugin 檔案被 Read 的次數 | phases.md 5、SUPERPOWERS-HANDOFF 2、OUTPUT-CONTRACTS 2、**RECONCILIATION-CRITERIA 0**、**PHASE-IDENTIFICATION 0** |

歸檔面（279 個 change，跨越 transcript 視窗之前）：

| 指標 | 數值 |
|---|---|
| 有 review-notes 的 change | 218（其中 171 個有 `## Round`） |
| Phase 5 條目 | 2,843 條：DESIGN:Y 585、REQUIREMENT:Y 301、CODE:N 1,584、CODE:Y 83、沒標 Y/N 的 113 |
| 有 Y 項的 change | 143 個，每個中位數 5 條，最多 34 條 |
| `[CODE] Y` 誤標，按月 | 8 月 48 → 9 月 25 → **10 月 1** |
| 帶著未完成 task 歸檔 | **102／279（37%）**，其中 56 個一格都沒勾（例：某個 change 的 task 為 0/98） |

### 1.2 已被證明有效的部分（保留）

- **1.5.0 的 review-notes 語意標頭有效。** `[CODE] Y` 誤標從 48 降到 1，是 eval 紅轉綠之後在真實專案也看得到的效果，也是這個 plugin 迄今唯一有實證的改版。
- **Phase 5 不准改 spec、Phase 6 整份重寫。** 抽樣 10 條 DESIGN:Y 都是真實的設計修訂（例如例外語意、授權組與載入組必須相同、風險段補已知殘餘），不是誤標。「改到哪個檔就標哪個 tag」的規則在運作。
- **角色分離。** 10 個 session 都沒出現 sidecar 的 design 或 plan 檔。

### 1.3 問題（依證據強度排序）

**P-A Phase 6 的核查關卡只存在於文字。**
- `phases.md` 6b5 寫「此 gate 不可跳過」，要求先讀 `RECONCILIATION-CRITERIA.md` 再執行 C1–C5。
- 9 個跑過 archive 的 session，對這份檔的 Read 次數是 0。
- 限制：只計 Read 工具，經 Bash `cat` 讀的沒有算進去；但子代理也沒看到相關的 Bash 讀取。
- 對照 CLAUDE.md 自己的判準：沒有機器檢查、沒有消費者的關卡，就等於沒有。

**P-B `tasks.md` 不是執行紀錄。**
- 37% 的 change 帶著未完成 task 歸檔，一半以上一格都沒勾。
- 原因（已抽查原檔）：`writing-plans` 產出 `- [ ] **Step N**` 格式；SDD 與 executing-plans 用 TodoWrite 追蹤進度，從不回寫 `tasks.md`；plugin 又在 6c 教人「用 `--yes` 略過未完成警告」。
- plugin 規則 4 說 tasks.md「是執行歷史」，但實際內容是「計畫」，不是「執行」。
- 上游的 `/opsx:apply` 每完成一個 task 就勾選，`/opsx:verify` 把未勾的 task 列為 CRITICAL。我們的流程與上游在這裡正面衝突。

**P-C skip-gate 沒有達成設計目的，而且有雜訊。** 12 次 deny 分布在 9 個 session，逐一還原 deny 前的情境：

| 情境 | session 數 | 例 |
|---|---|---|
| 同一 session 先歸檔，之後繼續編輯（歸檔後 changes/ 變空，gate 判定沒有 active change） | 4 | 某 session：歸檔後 37 秒被擋；另一個 session：歸檔後才寫 review finding 的紅測試 |
| 只編文件（README、調查文件、升級手冊） | 3 | 某專案的 README |
| 真正的程式碼修正，沒有 change | 2 | 某專案的 controller、另一專案的 `src/extension` |

- 12 次 deny 的下一則回覆**沒有一次**逐項列出八個面向。模型直接重試，第二次就放行了（「補上被擋的四個編輯」）。
- 只有 2 個 session 在約 60 行之後自己改判：「我原本判定可跳過，判錯了」，然後開了 change。
- 結論：gate 能逼出「暫停一下」，逼不出「做判斷」。第一列還揭露了另一個問題，見 P-D。

**P-D 歸檔早於 review 收斂。**
- P-C 第一列的 4 個 session，都是先 archive，之後才處理 review finding 或安全審查。例如某 session 在 16:41 歸檔，17:03 安全審查抓到一條 HIGH。
- Phase 6 的觸發條件「All reviews passed, all code fixes merged」寫在文字裡，沒有任何檢查。
- 後果是 review 後的修正落在已歸檔的 change 之外，`openspec/specs/` 少了這些修訂。

**P-E Phase 2 的提問量超過使用者的耐受度。**
- 使用者在 2 個 session 裡 3 次明說「跳過提問，直接開始設計」或「直接照預設方向寫 design.md」。
- plugin 的 Phase 2 寫死「Conduct Socratic questioning」，brainstorming 預設也是一次問一題。

**P-F 與上游脫節。**
- 本機 OpenSpec 1.16.1，profile 已啟用 explore、new、continue、ff、apply、sync、verify、bulk-archive、onboard。
- plugin 只提到 propose、apply、archive，而且寫錯一個事實：「`/opsx:apply` 沒有對應的 CLI」。1.16.1 已有 `openspec instructions apply --json`，會回傳進度與 task 狀態。
- 上游已改成「actions on a change, not phase-locked」，plugin 沒有說明這兩種模型怎麼共存。例如 `/opsx:sync` 會在實作中途改 main spec，直接違反規則 1。
- 上游有 `openspec schema fork`，可以把 review-notes 變成 schema 的正式產物，讓 CLI 原生檢查。這比 plugin 文字規則更硬。

**P-G Phase 4 主推的工具沒人用。** plugin 把 SDD 列為首選，實測 0 次；executing-plans 5 次。要嘛文件改成符合實際，要嘛查出 SDD 沒被選的原因（brief 寫不出來？成本？）。

**P-H eval 只蓋到最穩的地方。**
- 現有 suite 只測 Phase 5，也是唯一已證明有效的部分。
- backlog 中的 D（Phase 6）與 C（觸發／SKIP）正好是 P-A、P-C 的失效點，優先序應該往前調。

### 1.4 業界對照（二手資料，僅供參照）

- SDD 共識：spec 是 source of truth、有持久的 constitution 檔、只對正式工作做完整 SDD；公認的主要風險是「waterfall 2.0」，也就是前期過度規格化（Sources：dev.to、alexcloudstar、danielvaughan 2026）。
- 我們的 plugin 在前三點上一致，風險集中在第四點：階段鎖、蘇格拉底式提問、人工關卡都偏 waterfall。P-E 是使用者端的實證。
- OpenSpec 上游自己已從「階段」轉向「動作」。
- pstack 的立場是「用 prototype 回答開放問題、plan through code」。三方都指向同一件事：**保留產物的角色分離，放鬆流程的時序鎖。**

### 1.5 優化建議

每一項都附「怎麼量是否變好」，量測直接重跑上面兩支腳本。

| # | 建議 | 解哪個問題 | 機制 | 量測 |
|---|---|---|---|---|
| O1 | Phase 6 核查改成腳本：`reconcile-check.cjs` 驗 C1 路由（每條 Y 都對應到目標產物的 diff）、tasks.md 重寫前後 hash 不變、spec 不含 CONSTITUTION 項；archive 前必跑，結果落檔 | P-A | validator，再加 PreToolUse Bash hook：`openspec archive` 前要求存在本次核查結果檔 | 「沒有核查紀錄的 archive」比例降到 0 |
| O2 | tasks.md 回到執行紀錄：Phase 4 每完成一個 task 就勾（與 `/opsx:apply` 一致）；archive 前每個未勾項都要有 `skip: <理由>`（借 pstack 的 skip-with-reason） | P-B | 規則 4 改寫，validator 檢查未勾且沒寫理由的項 | 帶未完成 task 歸檔的比例，從 37% 往下降 |
| O3 | skip-gate v2：(a) `docs/**`、`*.md`（openspec 外）豁免或只提醒；(b) 同 session 已有 archive 時，訊息改問「這是 Phase 5 的修正嗎？」；(c) 重試時讀 hook 輸入的 `transcript_path`，最後一則 assistant 回覆含八面關鍵字才放行，否則再擋一次（上限 2 次，仍 fail-open） | P-C | hook，擴充 `skip-gate.test.sh` | deny 後有逐項列出的比例（現在 0/12）；誤攔比例（現在 7/9） |
| O4 | 歸檔前置條件改成可查的事實：PR 已 merge（`gh pr view` 的 `mergedAt`），或 review-notes 最後一輪標 `final` | P-D | 併入 O1 的腳本 | 「歸檔後同 session 又改程式」的 session 數，現在 4 |
| O5 | Phase 2 改成「先列假設、直接產出設計，只問改變方向的問題（上限 N 題）」；未決的開放問題優先用 prototype 回答 | P-E | 改 phases.md 的 Phase 2，eval 加一題「使用者要求跳過提問」 | 「跳過提問」類糾正次數，現在 3 |
| O6 | 對齊 OpenSpec 1.16：修正 apply 的錯誤事實、改用 `status --json`／`instructions apply --json` 取得進度；明訂 explore 在 Phase 0–2 可用、`sync` 只准在 Phase 6、`verify` 當 Phase 5 入口檢查；評估 `schema fork` 把 review-notes 納入 schema | P-F | 文件加 schema（後者需要 spike） | `openspec validate` 能否原生擋下缺 review-notes 的 change |
| O7 | 先量再改：把 886 條 Y 依來源（PR review、安全審查、自審）與輪次分類，判斷要不要在 Phase 2 加對抗式設計審查（pstack design red flags） | Y 量大 | 分析，不改 plugin | — |
| O8 | eval 優先序改為 C（觸發／SKIP，用 `scaffold_script` 放 `openspec/`）→ D（Phase 6） | P-H | eval | 先產生紅燈題，再改 plugin |

建議順序：**O1＋O4（同一支腳本）→ O3 → O2 → O5 → O6**。O1、O4 堵的是會把錯誤寫進 `openspec/specs/` 永久真相的洞，代價最大。

---

## Q2. 知識落點審查

### 2.1 證據

| 量測 | 數值 | 意義 |
|---|---|---|
| refs 兩個月內被 Read 的情況 | 23 份中 **15 份 0 次**；被讀最多的是 pr-closeout 10 次（9 個 session）、claude-md-authoring 7、security-review-toolchain 6 | 「做 X 前讀 Y」的 trigger 大多沒有被觸發，或觸發了也沒被照做 |
| 子代理讀 refs | 0 次 | refs 對子代理不存在；子代理需要的規則只能放在 agent 定義或派發 prompt 裡 |
| CLAUDE.md 條目總長 | 19,634 字（上限 20,000），107 條 | 已到預算邊緣 |
| 最大的段落 | Environment 24 條 4,957 字；兩個 Code Review 段合計 22 條 4,448 字；子代理分層 12 條 2,188 字 | |
| **規則遵循對照** | GPG 規則 9/21 寫入後，違規從 64 次歸零（之後只剩 scratch repo 中的 1 次）。**裸 `cd` 規則 10/17 寫入後**，main session 違規 1,723 次、subagent 1,229 次（10 月下半 1,653 次），本 session 也違反 2 次 | 文字規則在「替代做法一樣順手」時有效，在「對抗強習慣」時無效 |

抽樣註記：`git add -A`／`commit -a` 的 56 次命中，抽樣後幾乎都在 `mkdtemp` 或測試案例文字裡，屬合理用法，不算違規。

### 2.2 判準

依 `claude-md-authoring.md` 的三問，加上本次實測得到的第四問：

1. 換 repo 還成立嗎？
2. 每個 session 都需要嗎？
3. 能機器強制嗎？
4. **文字版已經被違反了嗎？** 違反次數就是升級到機制層的證據。

另一個觀察：Read trigger 依賴模型在對的時刻想起來，而 15 份 0 讀證明這很不可靠。可靠的 trigger 是「事件」：檔案路徑（rules 的 `paths:`）、命令樣式（PreToolUse hook）、skill 的 description 比對。

### 2.3 逐項判定

| # | 項目（目前位置） | 判定 | 理由與證據 |
|---|---|---|---|
| 1 | 「Bash 不用裸 `cd`」（CLAUDE.md） | **升級為 hook** | 寫入後違規 2,900+ 次。PreToolUse Bash：命令以 `cd <abs> &&` 開頭時，deny 並給出改寫（`git -C`、子殼），或用 `updatedInput` 自動包成 `( … )`（需先查證支援） |
| 2 | 「做 `claude plugin eval` 前讀 plugin-eval.md」等「做某指令前讀某 ref」型 trigger（CLAUDE.md 多條） | **改為命令樣式觸發的 context 注入** | plugin-eval、sandbox-write-restrictions 等 0 讀。PreToolUse Bash 比對 `claude plugin eval`、`git push`、`codex` 等樣式，把該 ref 的重點以 `additionalContext` 注入。**需先查證** PreToolUse 是否支援 `additionalContext`（依 CLAUDE.md，查 binary 字串）；不支援就改用 mod 的 `tool.call` |
| 3 | PR 收尾 SOP（refs/pr-closeout.md） | **升級為 skill** | 讀 10 次、9 個 session，trigger 有效。但 P1 候選 watch-pr 需要隨附腳本，refs 不能附可執行檔，skill 可以（`scripts/`）。description 寫「使用者說 merge／收尾時」 |
| 4 | Pest／Laravel 測試（CLAUDE.md 一行＋ref） | **改為 `~/.claude/rules/` 的路徑規則**（`paths: tests/**/*.php, **/*Test.php`） | ref 只被讀 1 次；改成碰到測試檔才自動載入，CLAUDE.md 省下一行。前例是 frontend.md |
| 5 | Code Review 兩段（22 條，4,448 字） | **大部分移進 skill body**，CLAUDE.md 只留 2–3 條 | 屬「只在 review／push／scan 才用的流程」（authoring §1 第二列）。已有 hook 強制的部分（push-nudge、scope-ledger）依 §5 縮成一行指標。落點可以是 code-audit-rigor 內新增「何時用哪一層 review」的 skill |
| 6 | 子代理模型分層（12 條） | **縮為 3–4 條** | model-floor hook 與 subagent-tiers mod 已強制下限；選階判斷保留兩問，細節回 `subagent-model-tiers.md` |
| 7 | Environment 中的工具機制（codex sandbox 兩個失敗點、keychain `100001`、plugin 版號快取、chrome deviceId、Monitor 沒有 sandbox 參數） | **移 refs，搭配 #2 的事件注入** | authoring §3 明列「會隨版本變的工具機制」屬參考層；這些都有明確的命令樣式可以觸發 |
| 8 | ugrep／BSD-GNU／awk locale | **維持決策層** | 作用在 Bash 命令上、不對應某類檔案，無法用 paths 限定；違規難以機器偵測 |
| 9 | Knowledge Architecture 段 | **候選：path-scoped rule**（只在編輯 CLAUDE.md 或 refs 時載入） | 只在寫知識時才需要。**需先實測**使用者層 rules 的 `paths:` 能否比對到 `~/.claude/` 底下的檔 |
| 10 | 已結案的決策紀錄（codex-review-bg-mod-research、graft-codegraph、scope-ledger-design、tree-workflow-experiment） | **維持 refs（只列在 INDEX）** | 0 讀是預期中的，它們本來就是存檔，不是操作手冊 |
| 11 | Plugin 使用決策樹（功能開發、Workflow 工具段） | **維持，但壓縮成每條一行路由** | 它就是我們的 router（相當於 poteto-mode），每個任務開始時都會用到，屬決策層；細節回各 skill body |
| 12 | 子代理需要的規則（ugrep、`git -C`、sandbox） | **寫進 agent 定義** | 子代理讀 refs 0 次。`finding-verifier.md` 已內嵌 ugrep 規則，這是正確範式；該盤點其他 agent 與 workflow 腳本是否漏掉 |

### 2.4 讓落點可以持續驗證

- authoring §5 寫著「遵循度目前只能手動觀察……尚未做」。本次的 `mine.cjs` 證明 transcript 本身就是現成的紀錄，不必另外讓 hook 寫 log。
- 建議把它收成 `~/.claude/scripts/audit/knowledge-usage.cjs`，每季修剪時跑一次，輸出三張表：refs 讀取、規則違規、gate 結果。
- 規則升級的條件改成可量測：「寫入後違規仍 >N 次 → 升級機制層」；「縮成一行後違規沒有回升 → 維持」。

---

## 3. 待使用者裁決

1. Q1 從哪裡開始。建議 O1＋O4，並依 SKIP 條款判斷是否要走 openspec workflow：這屬 plugin 行為變更，會影響八個契約面中的「跨模組行為」。
2. O5 的提問上限要設多少，以及要不要讓「先列假設」成為預設。
3. Q2 的 #1（裸 `cd` hook）是 deny 還是自動改寫：改寫較順手但不透明；deny 透明但會多一輪。
4. Q2 的 #5（Code Review 段搬進 skill）要放 code-audit-rigor plugin，還是個人層 skill。

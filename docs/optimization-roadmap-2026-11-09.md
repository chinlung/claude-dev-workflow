# 開發流程優化路線圖（2026-11-09）

> 依據：
> - `docs/lifecycle-and-placement-review-2026-11-09.md`（下稱「體檢」，Q1 的 O1–O8、Q2 的 #1–#12）
> - `docs/pstack-porting-candidates-2026-11-09.md`（下稱「pstack」，P1 2.1–2.3、P2 3.1–3.6、P3 表）
>
> 排序原則：
> 1. 先建量尺與紅燈題，再修。
> 2. 先修本地已量到失效的地方，再做 pstack 純移植。
> 3. pstack 某項若正好修補本地缺陷，併入同一工作包一次做完（標 ⇐pstack）。
> 4. 改到同一個檔的項目放同一包，避免重工。
>
> 兩個 repo：**R** = 本 repo（claude-dev-workflow，marketplace plugins）；**C** = `~/.claude`（個人設定 repo）。分屬不同 PR。
>
> 契約風險：本 repo 沒有 `openspec/`，沿用前例（scope-ledger、session-reflect）走 `docs/<name>-design` 加 `-plan`，再接 superpowers TDD 與 `/review-branch`。改 plugin 對外行為、schema 或 hook 行為的包，在下表標「設計文件」。

---

## 進度（2026-11-12 回填）

依兩個 repo 的 git 歷史與各計畫文件的狀態行整理。下面各 Wave 的表格保留原案，實際結果以本節為準。

| 項目 | 狀態 | 落點 |
|---|---|---|
| W0-1 稽核腳本與「規則 → 執行者」表 | 完成 | 個人設定 repo（knowledge-usage）；本 repo openspec plugin（archive-stats） |
| W0-2 能力查證 | 完成 | 個人設定 repo 的 `refs/claude-code-capability-checks.md` |
| W0-3 紅燈 eval 與盲測紀律 | 完成 | 盲測規則與禁用字掃描在個人設定 repo；eval suite 依計畫留本機 |
| W1-1 裸 `cd` | 完成，換了做法 | 先做 hook，後改用內建的「每次呼叫後重設 cwd」，hook 退役 |
| W1-2 Pest 規則改 `paths:` rule | 未做 | 併入 W4 後轉為候選清單 |
| W2-1 至 W2-5 | 完成 | PR #41、#42（2.0.0） |
| W2-6 schema fork | 放棄 | W0-2④：fork 加得進去，但 `validate` 不檢查它 |
| （路線圖外）gates 依事實停下 | 完成 | PR #52（3.0.0）、#54（3.1.0） |
| W3-1、W3-2 PR 收尾 skill | 完成 | PR #43（pr-closeout 1.0.0，落在本 repo） |
| W4 瘦身 | 範圍縮小後完成 | PR #46；判定類子代理稽核 hook 在個人設定 repo。W4-1 改為候選清單，W4-2、W4-3 不做，W4-4 經 W0-2 判定不可行 |
| W4-5 子代理規則盤點、W4-6 reflect 增補 | 未開始 | 另案 |
| W5-7 tokenizer differential 試點 | 完成 | PR #57（見 Wave 5） |
| W5-8 單一 lexer | 結案：第一步完成（lexer 當第三種讀法，PR #59）；第二步（退役舊讀法）試做、量測後不做 | openspec-superpowers-workflow 3.2.0／3.2.1、pr-closeout 1.1.0／1.1.1；量測與理由見 `docs/gate-lexer-design-2026-11-13.md` §10、§11，剩 gap 0 |
| W5 其餘 | 未開始 | W5-1、W5-5 已依 `docs/pstack-verification-skills-2026-11-11.md` 修訂（見 Wave 5） |

待驗收：W1-1 的「兩週後重跑 W0-1」約在 2026-11-23 之後才到期。

---

## 基準值（驗收時重跑同兩支腳本比對）

| 指標 | 基準 | 來源 |
|---|---|---|
| skip-gate deny 後有逐項列出八面的比例 | 0/12 | `mine.cjs` part_a.denials |
| skip-gate 誤攔（歸檔後繼續編輯或只改文件）比例 | 7/9 session | 體檢 P-C |
| 跑 archive 的 session 有讀或執行 Phase 6 核查 | 0/9 | `mine.cjs` |
| 歸檔後同 session 又改程式 | 4 session | 體檢 P-D |
| 帶未完成 task 歸檔 | 102/279（37%），0% 勾選者 56 | `arch.cjs` |
| 「跳過提問」類糾正 | 3 次 | `mine.cjs` friction |
| 裸 `cd`（規則 10/17 寫入後） | main 1,723、sub 1,229 | 體檢 2.1 |
| refs 兩個月零讀 | 15/23；子代理 0 | `mine.cjs` part_b |
| CLAUDE.md 條目總長 | 19,634／20,000 字 | 體檢 2.1 |

**第一步：** 把 `scratchpad/mine/mine.cjs` 與 `scratchpad/arch/arch.cjs` 收進 repo，讓基準可以重現（見 W0-1）。scratchpad 在 session 結束後不保證存在。

---

## Wave 0：量尺與查證（先做，全部 S）

| ID | 工作 | Repo | 交付與驗收 |
|---|---|---|---|
| W0-1 | 稽核腳本落地：`mine.cjs` 收成 `scripts/audit/knowledge-usage.cjs`，`arch.cjs` 收成 `openspec-archive-stats.cjs`；輸出 JSON 加摘要。**⇐pstack `correct`**：輸出加第三張表「規則 → 執行者（hook 名／validator／無）→ 寫入日期 → 寫入後違規數」，就是 pstack 的 rule table，但由 transcript 自動算，不靠人工維護 | C（knowledge-usage）、R（archive-stats，放 openspec plugin 的 `scripts/`） | 重跑能得到上表基準；附測試，fixture 是小 jsonl 加突變（matcher 失效時測試要紅） |
| W0-2 | 能力查證（依 CLAUDE.md，查 binary 字串並實測）：① PreToolUse 是否支援 `additionalContext`；② 是否支援 `updatedInput`；③ 使用者層 `rules` 的 `paths:` 能否比對 `~/.claude/` 底下的檔；④ `openspec schema fork` 能否加 review-notes 產物並讓 `validate` 檢查 | — | 每項一行結論，寫進 `refs/` 對應檔。①② 決定 W1-1 與 W4-3 的做法；③ 決定 W4-4；④ 決定 W2-6 |
| W0-3 | 紅燈 eval 先行。⇐pstack `playbooks/eval.md` 盲測紀律：建 flow C（觸發／SKIP，用 `scaffold_script` 放 `openspec/`）與 flow D（Phase 6）的 suite；prompt 不出現 eval、score 等字。同時把盲測規則補進 `refs/plugin-eval.md`，並寫禁用字掃描腳本 | R（evals 本機、gitignored） | 每個要修的缺陷至少一題在現行 1.5.0 上紅：P-A、P-B、P-C、P-D、P-E 各一 |

---

## Wave 1：立即止血（C repo，S）

| ID | 工作 | 解哪個問題 | 驗收 |
|---|---|---|---|
| W1-1 | 裸 `cd` hook（PreToolUse Bash）：命令以 `cd <path> &&`／`;` 開頭且不在子殼內時處理。裁決點 D3：deny 並附改寫建議，或依 W0-2② 用 `updatedInput` 自動包成 `( … )`。**建議 deny**，透明且可量；改寫會讓 transcript 與實際執行的命令不一致 | 規則寫入後違規 2,900+ 次 | `run-all.sh` 新增測試（含突變）；兩週後重跑 W0-1，主 session 違規降到接近 0 |
| W1-2 | Pest／Laravel 規則改成 `~/.claude/rules/php-testing.md`，加 `paths:`；CLAUDE.md 刪一行 | ref 只讀 1 次 | 依前例在 transcript 看 `nested_memory` 注入時序 |

---

## Wave 2：openspec-superpowers-workflow 2.0（R repo，設計文件）

一個設計文件、多個 commit，依下列順序實作。每項先有 W0-3 的紅燈題。

| ID | 工作 | 解 | 一併納入的 pstack | 驗收 |
|---|---|---|---|---|
| W2-1 | **歸檔閘門腳本** `reconcile-check.cjs`：C1 路由（每條 Y 都對應到目標產物的 diff）、tasks.md 重寫前後 hash 不變、spec 不含 CONSTITUTION 項、**歸檔前置事實**（PR 已 merge，或 review-notes 最後一輪標 `final`）；結果落檔；PreToolUse Bash hook 在 `openspec archive` 前要求有本次核查結果檔 | P-A、P-D | ⇐pstack `check-plan.mjs` 的作法：用 linter 驗產物結構、exit code 分級。⇐pstack `shipping.md` 的「verdict 只涵蓋一個 patch」：核查結果記下 `git patch-id`，之後若有新 commit 就判定過期、要求重跑 | 沒有核查紀錄的 archive：0/9 → 0；歸檔後同 session 改程式：4 → 0 |
| W2-2 | **skip-gate v2**：(a) 只改 `docs/**` 或 openspec 外的 `*.md` 時改成提醒、不擋；(b) 同 session 已 archive 時，訊息改問「這是 Phase 5 修正嗎？請開 follow-up change 或註記」；(c) 重試時讀 `transcript_path` 的最後一則 assistant 回覆，必須含**固定格式的單行聲明**才放行，否則再擋（上限 2 次，仍 fail-open） | P-C | ⇐pstack `investigation.md` 的 `throughput checkpoint: n/a, <reason>` 單行格式：八面聲明定為 `契約面：API=否 資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 跨模組=否`，讓 hook 可以用 regex 機械驗證，不必判斷文意 | deny 後有列出的比例：0/12 → ≥90%；誤攔：7/9 → ≤1/9；`skip-gate.test.sh` 新增案例含突變 |
| W2-3 | **tasks.md 回到執行紀錄**：Phase 3 產出的 tasks.md 用 OpenSpec 的 task 勾選格式；Phase 4 每完成一個 task 就勾（與 `/opsx:apply` 一致）；刪掉「用 `--yes` 略過」；未勾項必須寫 `skip: <理由>`，W2-1 腳本檢查 | P-B | ⇐pstack poteto-mode「不做的步驟留在清單並寫 `skip: <reason>`」 | 帶未完成 task 歸檔：37% → 下降，且沒寫理由的未勾項 = 0 |
| W2-4 | **Phase 2 提問預算**：預設「先列假設、直接寫 design.md，只問會改變方向的問題（上限 N）」；能用實驗回答的問題改做 prototype；design.md 產出前對照設計紅旗清單自檢 | P-E；部分回應 Y 量大（O7） | ⇐pstack poteto-mode「問之前先分類：可觀察的事實不是人的問題」、`playbooks/prototype.md`、`architect/references/design-red-flags.md`（假設下一個貢獻者是只看自己打開的檔的 agent） | 「跳過提問」糾正：3 → 0；eval 新增「使用者要求跳過提問」題 |
| W2-5 | **對齊 OpenSpec 1.16**：修正 apply 的錯誤事實；進度改用 `status --json`／`instructions apply --json`；明訂 explore 在 Phase 0–2 可用、`sync` 只准在 Phase 6、`verify` 當 Phase 5 入口與 Phase 6 核查的輸入；Phase 4 主推改成實測有在用的 `executing-plans`，SDD 列為「task 獨立時」 | P-F、P-G | — | `phases.md` 中 CLI 敘述與 `openspec --help` 全文逐條比對無誤 |
| W2-6 | （依 W0-2④）把 review-notes 納入 fork 出來的 schema，讓 `openspec validate` 原生檢查 | 結構化 P-A／P-B | ⇐pstack `encode-lessons-in-structure`（能做成結構就不寫文字） | spike 結論；可行才排入，否則記入 Deferred |

**刻意不改：** Phase 5 不准改 spec、Phase 6 整份重寫、tag 依修改落點。1.5.0 的數據證明這些有效（`[CODE] Y` 48→1）。上游「fluid」模型只借時序上的彈性，不借「隨時改 spec」。

---

## Wave 3：PR 收尾 skill（C repo，設計文件）

| ID | 工作 | 解 | 一併納入的 pstack | 驗收 |
|---|---|---|---|---|
| W3-1 | `refs/pr-closeout.md` 升級成 skill（description：使用者說 merge／收尾時），隨附腳本 `pr-ready.mjs`：輸出 JSON verdict 加 exit code（0 ready、2 衝突、3 未解決 thread、4 check 失敗、6 merge gate、7 查詢失敗）；fail-closed；sandbox 內走 REST 加 `gh auth token` header 的退路 | 收尾第 1 步靠人工查三個 endpoint；`gh run watch` 看不到 merge state | ⇐pstack **P1 2.3** `watch-pr`：single-PR 模式、`assessGitHubMerge`（BLOCKED 加 head rollup 失敗 = 拒絕）、CI 分類規則（flake 只重跑一次；失敗在沒動到的程式碼 = base 過舊）、回覆用 `--input` 不插值。⇐pstack **P2 3.1** patch-id：被審的 patch 與合併的 patch 要一致 | 測試含 fake reader 與突變；用一個歷史 PR 實跑；CLAUDE.md 對應條目縮成一行 |
| W3-2 | 收尾時也檢查 W2-1 的歸檔核查（對有 openspec 的專案） | P-D 的另一端 | — | — |

---

## Wave 4：CLAUDE.md 瘦身與觸發機制（C repo）

| ID | 工作 | 解 | 一併納入的 pstack | 驗收 |
|---|---|---|---|---|
| W4-1 | Code Review 兩段（22 條，4,448 字）移進 skill body。裁決點 D4：放 code-audit-rigor 的新 skill「何時用哪一層 review」，或個人層 skill。**建議 code-audit-rigor**，跟審查工具同版控、同測試。CLAUDE.md 只留 2–3 條加 trigger | 決策層 19.6k／20k；流程型條目放錯層 | ⇐pstack P3「review 噪音模式分級」（candidate／recurring／strong 加永不自動略過清單）併入 skill 的 triage 段 | CLAUDE.md ≤ 16k；W0-1 的「規則 → 執行者」表無遺漏 |
| W4-2 | 子代理分層縮為 3–4 條；Environment 中的工具機制（codex sandbox、keychain `100001`、plugin 版號快取、chrome deviceId、Monitor）移到 refs | 版本會變的機制佔常駐預算 | — | lint 綠；W0-1 違規數不回升 |
| W4-3 | **命令觸發注入**（依 W0-2①）：PreToolUse Bash 比對 `claude plugin eval`、`git push`、`codex`、sandbox 內 `gh api` 等，把對應 ref 的重點以 `additionalContext` 注入；不支援就改用 mod `tool.call` | 15/23 refs 零讀；「做 X 前讀 Y」不可靠 | — | 兩週後對應 refs 的讀取或注入次數 > 0，對應失誤不再出現 |
| W4-4 | （依 W0-2③）Knowledge Architecture 段改成只在編輯 CLAUDE.md 或 refs 時載入的路徑規則 | 只在寫知識時需要 | — | 同 W1-2 驗法 |
| W4-5 | 子代理規則盤點：子代理需要的規則（ugrep、`git -C`、sandbox）寫進各 agent 定義與 workflow 腳本 | 子代理讀 refs 0 次 | — | 抽查各 agent .md 與 `tree.js` |
| W4-6 | session-reflect 增補：環境摩擦若已有對應規則，處方只能是機制層；並借三視角裡的「自足性」視角 | 規則被違反卻只會再加文字 | ⇐pstack **P2 3.2** `correct`（再次被糾正 = 沒東西在執行它）、P3 `reflect` tooling-reviewer | reflect 的 eval 或 fixture |

---

## Wave 5：pstack 純移植（本地無對應缺陷，獨立價值）

| ID | 工作 | Repo | 規模 | 備註 |
|---|---|---|---|---|
| W5-1 | **證據階梯**（pstack P1 2.1）：finding-verifier 加 `evidence_rung`，schema 與 validator 擋下「2 階以下卻 PASS」；`/review-branch --prove`。**2026-11-11 修訂，同一次 schema 變更加兩項**：① 結果檔加 `safety_pivot`（「這個 diff 安全，是因為 X」與 X 到第幾階；零 finding 的輪次也要填，填不出來寫 `unproven`）；② 「grep 停下的地方」清單放 `plugins/code-audit-rigor/tools/`（動態關聯、字串類名、序列化 payload、DB 欄位與 JSON 形狀），codegraph skill 加一行指過去 | R | M，設計文件 | 裁決點：第 4 階是鼓勵還是正確性類必要。建議先鼓勵，用 W0-1 量一輪再定。驗收：拿已記錄的逃逸案例回放，看動態關聯那一類有沒有被點名 |
| W5-2 | **量測數字審查**（P1 2.2）：七問 skill；CLAUDE.md 加一行 trigger | R 或 C | S | W2 的 eval 與 W0-1 統計就是第一批適用對象 |
| W5-3 | 決策軌跡（P2 3.3）：`/loop`、`/goal`、`tree` 長跑用 | R | M | 裁決點：併入 scope-ledger 或獨立 |
| W5-4 | 證據分級用語（P2 3.5）收進 refs，供 pr plugin 與分析文件引用 | C | S | |
| W5-5 | ~~專案驗證 skill 產生器（P2 3.6），可接內建 `run`~~ **2026-11-11 修訂**：Claude Code 已內建 `/run-skill-generator` 與讀取其產出的 `run`，不再移植產生器。改為：在一個 Laravel 專案跑內建產生器，對照 pstack 的六段與 feature map，只補缺的部分（唯讀健康檢查、副作用驗證、cleanup 後證據仍在、功能清單） | 應用專案 | S | 驗收：checkout 到某個 UI bug 修正前的 commit，照產出的 skill 驅動，必須重現該 bug。定期稽核（maintain）等功能檔有 3 個以上再評估 |
| W5-6 | P3 其餘：攻擊前提（2 次失敗共用同一前提）、測試的第二種想像編輯、`tree` 的「缺口不算通過」、偏好需跨兩段證實、worktree 盤點腳本、catch-up 格式 | 混合 | 各 S | 可隨相關 PR 順手做 |
| W5-7 | **tokenizer differential 試點**（2026-11-11 新增，來自 pstack formal-verification 的方法）：以 bash 當 oracle 測兩支 gate 的 shell tokenizer。**已完成，PR #57**：`tests/tokenizer-differential.pl` 與 `.test.sh`；找到並修正註解撇號的缺陷；每條命令讀兩次取聯集，新規則只能多抓 | R | 已完成 | 能分辨 #48、#51、#55 每次修正前後的版本；對 main 的超集檢查零遺漏。留下三個既有缺口，由 `--gap 0/1/2` 盯著 |
| W5-8 | **gate tokenizer 合成單一 lexer**（2026-11-12 新增）：heredoc pass 與 tokenizer 目前是兩個掃描器，各自判斷引號、註解與續行。合成一個在換行處讀 heredoc 本體的 lexer，是修三個既有缺口的正確位置：雙引號內替換裡的雙引號（直接解決）、`$( … )` 內以 `EOF)` 收尾的 heredoc（要先查 bash 各版本的實際行為）、混合引號的 delimiter（重寫時一併做對，不會自動消失） | R | M–L，設計文件 | 兩支 gate 的共用區段同步改。驗收：三個 `--gap` 檢查轉紅後移回預設語法；對 main 的超集檢查維持零遺漏；兩支 suite 的 mutant 全數仍被殺掉。merge gate 是 fail-closed，先寫設計再動手 |

---

## 依賴與建議順序

```
W0-1 量尺 ─┬─> W1-1 cd hook ──────────────────────┐
           ├─> W0-3 紅燈 eval ─> W2-1 → W2-2 → W2-3 → W2-4 → W2-5 (→ W2-6)
W0-2 查證 ─┼─> W1-2 / W4-4（rules paths）
           └─> W4-3（additionalContext）
W2-1 ─────────> W3-1 / W3-2 收尾 skill
W0-1 rule table ─> W4-1 / W4-2 瘦身 ─> W4-6 reflect
W5-*（任何時候，建議在 W2 之後）
```

- 第一個 PR：W0-1 加 W1-1（C repo，S，立即可量）。
- 第二個 PR：W0-3 加 W2-1、W2-2（R repo，openspec plugin 2.0 的核心）。
- W2 全部完成後重跑 W0-3 的 suite 與 Phase 5 舊 suite（Δ 基準 +0.60 不得下降）。

## 待裁決（附建議）

| # | 問題 | 建議 |
|---|---|---|
| D1 | Wave 2 拆成一個 2.0 版還是逐項 minor | 一份設計文件、逐項 commit、一次出 2.0：W2-1／W2-2／W2-3 都改 hook 與歸檔行為，屬 breaking |
| D2 | W2-4 的提問上限 N | 2 題，其餘列為「假設」寫進 design.md 的 Open Questions |
| D3 | 裸 `cd` hook 要 deny 還是自動改寫 | deny（理由見 W1-1） |
| D4 | Code Review 段的落點 | code-audit-rigor 新 skill |
| D5 | W5-1 第 4 階要不要強制 | 先鼓勵，量一輪再定 |
| D6 | W5-3 要不要併入 scope-ledger | 量一輪 `/loop` 實際用量後再定，目前證據不足 |

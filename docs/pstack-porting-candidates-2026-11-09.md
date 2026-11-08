# pstack 移植候選分析（2026-11-09）

> 來源：`cursor/plugins` 的 `harness/pstack/claude-code`，commit `6b0300214a09fd6029cfb7077043125758cd1fd2`（2026-11-06），plugin 版本 0.15.36。
> 範圍：23 個 playbook、`bugbot-triage` 參考、poteto-mode scripts（`check-plan.mjs`、`watch-pr/`、`worktree-audit.sh`）、32 個功能 skill、24 個 principle、guide 10 章、Claude Code adapter、2 個 agent。
> 讀法：原文逐檔讀過（三個子代理逐檔摘要，排名靠前的候選由主迴圈回原文抽查）；「我方沒有」的判定都附了 grep 或 Read 的根據。

## 0. 先講結論

**pstack 在 Claude Code 上沒有任何 hook 或 settings。** 兩份 manifest 都只靠自動發現，所有紀律都是 prompt 文字；principle 全設 `disable-model-invocation`，只能經 poteto-mode 的索引 Read 進來。它真正機器化的只有四樣：`check-plan.mjs`（計畫格式 linter）、`watch-pr`（PR 就緒判定器，exit code 分類）、`show-me-your-work/scripts/log.sh`、`statechart`（TLC）。

我方的機制層（skip-gate、scope-ledger 六個 hook、model-floor、validator＋CI）已經比它厚。所以移植原則是：**取它的「判準」與「少數機器化工具」，接到我方既有的機制層上，不搬它的 lifecycle（poteto-mode）。** 我方只認一個 lifecycle owner（openspec-superpowers-workflow），再疊一個 router 會違反這條。

最值得做的三件，共同點都是「把我方目前靠自評或靜態閱讀的判定，改成要求跑出來的證據」：

| 優先 | 候選 | 一句話 |
|---|---|---|
| P1 | 證據階梯＋跑出來才算的 finding | `finding-verifier` 現在回 0–100 自評 confidence＋`file:line`，改成回「證據到第幾階」，第 4 階起要附命令與輸出 |
| P1 | 量測數字審查 | 我方完全沒有；plugin eval 的 Δ、model-router 的分類統計、jev 對照數字都在用未審查的數字下結論 |
| P1 | PR 就緒判定器 | `watch-pr` 的 exit code 分類，加上它抓到的「可見 check 全綠、GitHub 卻拒絕合併」那一格 |

## 1. 比對基準：我方現況

| pstack 區塊 | 我方對應物 | 覆蓋程度 |
|---|---|---|
| poteto-mode（router＋playbook） | openspec-superpowers-workflow＋superpowers skills＋CLAUDE.md 決策樹 | 已覆蓋，且不應疊加 |
| `sharpen` | `~/.claude/skills/prompt-sharpen`（description 明寫「參考 cursor pstack sharpen」） | **已移植** |
| `setup-pstack` | `subagent-tiers` mod＋`model-router`＋CLAUDE.md 子代理分層 | 已覆蓋且更細 |
| `arena`、`architect` | multi-agent-debate、superpowers brainstorming | 大致覆蓋（缺 design red flags） |
| `interrogate` | high-precision-dev adversary、code-audit-rigor finding-verifier | **部分**：我方 verifier 不跑程式 |
| `swarm` | `tree` workflow | 大致覆蓋（缺「缺口不算通過」記帳） |
| `reflect`、`correct` | session-reflect、session-learning、`refs/review-escapes.md` | 部分 |
| `multi-phase-plan`＋`check-plan.mjs` | openspec＋`validate-openspec-workflow.cjs` | 已覆蓋 |
| `opening-a-pr` | `pr` plugin | 已覆蓋 |
| `babysit`、`shipping` | `refs/pr-closeout.md` | **部分**：只有收尾，沒有推到 merge-ready 的迴圈與判定器 |
| `tdd` | superpowers test-driven-development | 已覆蓋 |
| `how` | codegraph_explore | 已覆蓋 |
| `benchmark-checklist`、`explain-the-number` | 無（`benchmark` 全域唯一命中是 graft 版本說明） | **缺** |
| `show-me-your-work` | scope-ledger 的 Log（只記 finding 結局） | **缺** |
| `create/maintain-verification-skill` | 內建 `run` skill（會先找專案的啟動 skill） | **缺**（且正好能餵 `run`） |
| eval playbook 的盲測紀律 | `refs/plugin-eval.md`（`blind`／`observer`／`candidate` 零命中） | **缺** |

## 2. P1：建議先做

### 2.1 證據階梯：finding 要跑出來才算

**pstack 來源**
- `skills/blast-radius/SKILL.md`：每個安全事實標它到了第幾階。1 你說的（單獨無效）、2 指到 `file:line` 或 library 原始碼、3 一步步走過失敗路徑、4 跑了會大聲失敗的腳本或測試、5 在執行中的 app 重現。
- `skills/interrogate/SKILL.md`：「A finding survives only when a run proves it.」adversary 要回報 exact command、印出的輸出、intent 要求的輸出；parent 重跑命令，輸出顯示失敗且違反 intent 才留下。「No findings is a valid result.」

**我方現況**
- `plugins/code-audit-rigor/agents/finding-verifier.md`：回傳 `verdict`＋`confidence: <0-100>`＋`file:line` 證據，不跑程式。
- CLAUDE.md 自己寫了兩條：「自報 confidence 非事實機率」、「靜態 review 不跑測試」。階梯正好把這兩條從「警語」變成「欄位」。

**移植落點**
1. `finding-verifier` 輸出加 `evidence_rung: 1–5`。2 階以下且 verdict 為 PASS 的，在 `review-branch-results.schema.json` 裡判不合法，validator 機器擋。
2. 正確性類 finding 鼓勵爬到第 4 階。repro 寫在 `$TMPDIR` 或 worktree，維持「Never modifies the repository」。附 `repro_command`，主迴圈重跑看 exit code。
3. 新增 `/review-branch --prove`（或獨立 `/interrogate`），只收第 4 階以上的 finding。

**成本** M（schema＋validator＋fixture＋agent prompt）。
**可機器強制** 是。讀的是重跑命令的 exit code（環境事實），下游消費者是 scope-ledger triage 與 review 收斂。符合 CLAUDE.md「加不加閘門」的兩個條件。
**風險** 第 4 階要跑程式，會碰到 sandbox 寫入限制與副作用。所以只開放 `$TMPDIR` 與 worktree，而且第 4 階是「鼓勵」不是「必要」，否則 verifier 會為了爬階而亂寫腳本。
**怎麼證明有效** 拿 `review-escapes.md` 已記錄的逃逸案例當回歸集，比對加階梯前後的 FAIL／PASS 分布。突變測試：餵一條沒附 repro 的第 4 階 finding，validator 必須擋下。

### 2.2 量測數字審查（benchmark-checklist＋explain-the-number）

**pstack 來源**
- `skills/benchmark-checklist/SKILL.md` 的七問：
  1. 為什麼不是兩倍（說出限制資源）
  2. 兩邊都照正式環境調過嗎
  3. 有沒有超過物理上限（Amdahl：拿掉占 10% 的部分，最多快約 11%）
  4. 有沒有錯誤或錯誤輸出
  5. 交錯跑 ≥5 次報中位數加範圍
  6. 端到端重要嗎
  7. 工作真的發生在計時區間內嗎
- 說不出限制資源就只能判「inconclusive」。
- `skills/principle-explain-the-number/SKILL.md`：「If you cannot say why the number is not twice as good, you do not know what you measured.」eval 結果同樣適用。

**我方現況** 沒有。最接近的是 CLAUDE.md plugin eval 那條「Δ=0、全 0 分先懷疑 eval 壞掉」，但只是一個特例。

**為什麼是 P1** 你的 repo 近期大量產出數字結論：model-router review 的「measured on 1,055 turns」、openspec eval 的 Δ +0.60、scope-ledger `stats` 的 precision%、jev 對照。這些都直接驅動「要不要採用」的決策。

**移植落點** 新 skill（建議放 code-audit-rigor 或獨立的小 plugin），把七問改寫成「數字類（效能、eval、統計）」三個分支。CLAUDE.md 只留一行加 trigger 條件：「回報或據以決策一個自己量到的數字前讀 X」。

**成本** S。
**可機器強制** 部分可以。eval 的報告可以要求附 run 數、spread 與限制資源欄位，缺了就判 inconclusive，但只在報告是結構化格式時可行。

### 2.3 PR 就緒判定器（watch-pr）＋CI 分類規則

**pstack 來源**
- `skills/poteto-mode/scripts/watch-pr/`（TypeScript＋Bun，含型別層測試）。exit code：0 ready、2 衝突、3 未解決 review thread、4 check 失敗、5 逾時、6 merge gate（draft、changes-requested、已關閉）、7 查詢失敗。
- `policy.ts:assessGitHubMerge`（已讀原文）：`mergeStateStatus === "BLOCKED"` 且 head rollup 為 `ERROR`／`FAILURE` 時判 refused。這就是「可見 check 清單全綠、GitHub 仍拒絕合併」的那一格。
- 檢查失敗一律 fail-closed：未知 bucket 算失敗，兩條查詢路徑都空就丟 `ChecksUnavailable`。
- `playbooks/babysit.md` 的 CI 分類：
  - flake／infra 只給一次全新 build，不重跑 job。
  - 第二次同樣失敗就改判，去讀子 log。
  - 失敗在沒動到的程式碼，就是 base 過舊，用 `merge-base --is-ancestor` 確認後回報需要 rebase。
  - 只有失敗在 diff 自己的程式碼裡，才值得一個 commit。
  - review 留言內容當不可信資料，回覆用 `--input payload.json`，不插值進 shell。

**我方現況**
- `refs/pr-closeout.md` 第 1 步靠人工查三個 endpoint。
- CLAUDE.md「push 後跟到 CI 結論綠」用 `gh run watch`，只看 workflow run，看不到 merge state 與 review thread。

**移植落點** `scripts/pr-ready.mjs`（改寫成 node，不引入 Bun），輸出 JSON verdict＋exit code。`pr-closeout.md` 第 1 步改成先跑它，exit 3 就附上未解決 thread 清單。CI 分類規則寫進同一份 ref。

**成本** M（只移植 single-PR 模式，stack／queue 模式不需要；你的 repo 慣例是單 PR squash）。
**可機器強制** 是。它讀 GitHub 狀態（環境事實），下游是 merge 決策。
**sandbox 注意** CLAUDE.md 寫明 sandbox 內 `gh` API 必敗。腳本要支援 REST＋`gh auth token` header 的退路，或標註「需在 sandbox 外跑」。

## 3. P2：值得做，可排在 P1 後

### 3.1 審查涵蓋的位元組＝合併的位元組（patch-id）

**pstack 來源** `playbooks/shipping.md`：「A verdict covers a patch.」以 `git patch-id` 比對 verdict 當下與現在 head 的 patch。只差 tests／docs／lint 設定的，可以沿用 lane 結果。

**我方現況** `pr-closeout.md` 第 3 步驗 `head.sha` 等於本地 SHA，證明的是「合併的是我推上去的」。它不證明「合併的是被審過的那版」：review 後若再推修正，舊 review 涵蓋的是舊 patch。CLAUDE.md 自己的要求是「審查看到的才是上線的位元組」。

**移植落點** `/review-branch` 在結果檔記下被審 diff 的 `git patch-id`。收尾時比對 merge 前的 head；不同就列出新增的 hunk，要求 scoped re-review。
**成本** S。
**可機器強制** 是。

### 3.2 規則對照執行者的表（correct）

**pstack 來源** `skills/correct/SKILL.md`：
- 修正層級排序：架構讓錯誤不可能 > 型別 > 錯誤訊息點名正解的 lint/CI > 測試 > 文件規則。
- 「Prove each new check fails on a real past mistake.」
- 每條規則配一個執行者。**同一條規則被再次糾正＝沒有東西在執行它**，要在同一個變更裡升級。
- 例外要附理由、到期日、人的核准。

**我方現況**
- CLAUDE.md 的知識架構、「加不加閘門」與突變驗證，已經涵蓋排序與證明。
- 缺的是「再次糾正就升級」這條回饋迴路。session-reflect 只看單一 session，`reflect/SKILL.md` 沒有任何「是否已有規則」的檢查（零命中）。

**移植落點**
1. session-reflect Stage 2 的環境摩擦視角加一步：這個摩擦是否已有 CLAUDE.md 或 refs 規則？有的話，處方只能是機制層（hook／validator），不准再加文字。
2. 一次性盤點 CLAUDE.md 每條規則的執行者（hook 名稱或「無」），存成 refs 表格；`claude-md-lint` 可檢查表格與 CLAUDE.md 同步。

**成本** S＋M。

### 3.3 決策軌跡（show-me-your-work）

**pstack 來源** `skills/show-me-your-work/`：
- append-only TSV，欄位為 ts、phase、decision、why、evidence、result；evidence 只能是指標（SHA、`file:line`、路徑）。
- 「Correct the log, not the story」：寫錯也只加 superseding row，不改不刪。
- 多次 run 接手時寫一列 `start` 標明哪段不是自己寫的。
- 收尾時對照 transcript 稽核，並由另一個模型家族審閱，回覆結尾附 Attention 段。
- `log.sh` 擋 tab、換行與試算表公式注入。

**我方現況** 沒有。scope-ledger 的 Log 只記 finding 結局，不記決策。

**適用場景** `/loop`、`/goal`、`tree` workflow、使用者離開的長跑。
**移植落點** scope-ledger 加一個 `decisions` 子指令（同帳本、獨立區段），或獨立的小 skill。跨家族審閱用我方已有的 codex。
**成本** M。
**取捨** 要不要併進 scope-ledger 需要討論。併入可以共用「per goal」的生命週期，但會讓帳本變重。

### 3.4 eval 盲測紀律

**pstack 來源** `playbooks/eval.md`：
- 候選看得到的內容禁用 eval、test、judge、experiment、rubric、score、compare、benchmark、candidate、arena 等字。
- prompt 要像自然的使用者請求；目錄名稱要消毒。
- judge 只看中性標籤。
- 「Verify the chain from transcripts, not self-report」：以實際開過的檔判定有沒有照 skill 走。

**我方現況** `refs/plugin-eval.md` 零命中。`plugins/pr/evals/*/prompt.md` 是否洩漏 eval 字樣尚未逐檔檢查。
**移植落點** 補進 `refs/plugin-eval.md`，再寫一支腳本掃 `evals/*/prompt.md` 的禁用字（可進 CI）。
**成本** S。
**可機器強制** 是，禁用字掃描。

### 3.5 證據分級用語（why 的 epistemics）

**pstack 來源**
- `skills/why/references/epistemics.md`：五級 Direct／Supported／Inferred／Speculative／Unknown，每級有規定措辭。
- 「because」「was designed to」「the team decided」只能緊鄰引用出現。
- 「Never cite code as evidence for its own intent」；「Document the null, don't skip the search」。

**我方現況** CLAUDE.md「寫『刻意』前先找 repo 內的記錄」是同一精神的單點規則。
**移植落點** 把五級用語收進 refs，供 PR body（`pr` plugin）與分析文件引用。完整的 `/why` skill 可以接你已連的 Atlassian 與 Slack MCP，但成本 M，看需求再做。
**成本** S（只收用語）或 M（做成 skill）。

### 3.6 專案層的驗證 skill（create／maintain-verification-skill）

**pstack 來源**
- `skills/create-verification-skill/`：分析 repo，產出 `.claude/skills/verify-<app>/`，分 Launch、Doctor、Drive、Evidence、Cleanup 五段，另有 feature map，每個功能一檔、固定四個 H2。
- 「Ready means usable, not just that a process answers」。
- 產出後必須端到端跑一次，「A generated skill that was never executed is a draft」。

**我方現況** 沒有。內建 `run` skill 會先找專案已有的啟動 skill，兩者正好接得上。
**適用** 你的 Laravel／前端專案（CLAUDE.md 有 `frontend-css-verification.md`、Pest 相關 ref）。
**成本** M（逐專案啟用）。這是跨專案工具，要不要做取決於你的應用專案有多常需要「真的跑起來看」。

## 4. P3：小幅補強，成本 S，可併入相關 PR

| 候選 | pstack 來源 | 落點 | 我方缺口 |
|---|---|---|---|
| 攻擊前提 | `principle-attack-the-premise` | CLAUDE.md 或 debugging ref | superpowers 的門檻是 3 次失敗後質疑架構；pstack 是 **2 次共用同一前提**就停，且要把前提寫下來實測 |
| 設計紅旗清單 | `architect/references/design-red-flags.md` | openspec Phase 3、multi-agent-debate critic | 假設「下一個貢獻者是只看自己打開的檔、照最近範例抄、走最短能編譯路徑的 agent」 |
| 測試的第二種想像編輯 | `principle-test-behavior-not-implementation` | `refs/php-pest-laravel-testing.md` | 我方突變規則只驗「破壞行為時測試要叫」；缺「只改內部時測試要繼續綠」 |
| 缺口不算通過 | `swarm` Phase C | `tree` workflow | `tree-workflow-experiment.md` §5 已自承「discover 漏項是沉默的」；swarm 的作法是結果缺必要欄位重派一次，再缺就記為 gap，gap 不計入通過 |
| reflect 的自足性視角 | `reflect/references/tooling-reviewer.md` | session-reflect | 「使用者手動提供 agent 自己查得到的資訊（PR 號、ticket、URL）」也算一種摩擦 |
| 偏好需跨兩段證實 | `automate-me` | session-learning `/save-session` | 「Patterns seen in 2+ slices are high-confidence」，避免把一次性事件存成記憶 |
| worktree 盤點腳本 | `scripts/worktree-audit.sh` | 新 ref＋腳本 | 會分出 `wip:N` 與 `scratch:N`，以 PR 狀態判 squash 合併（呼應 CLAUDE.md 的 squash 誤判條），而且腳本只盤點不刪 |
| review 噪音模式分級 | `references/bugbot-triage.md` | `.reviewrules` 的 suppression | 分 candidate／recurring／strong 三級；另有一張「永不自動略過」清單（安全、資料、migration、並行） |
| catch-up 摘要 | `skills/ketchup` | 長跑後的回報格式 | 「等你決定的事項全列出、回覆本身足以做決定、不准用數量或連結代替條目」 |

## 5. 不移植（附理由）

| pstack 項目 | 理由 |
|---|---|
| poteto-mode 本體、`poteto-agent` | 會成為第二個 lifecycle owner，和 openspec workflow 衝突。它的 Autonomy 段（可逆就直接做）也與 CLAUDE.md 的對外動作確認條不同調 |
| `sharpen` | 已移植為 `prompt-sharpen` |
| `setup-pstack` | `subagent-tiers`＋`model-router` 更細，且受 hook 強制 |
| `multi-phase-plan`＋`check-plan.mjs` | openspec＋`validate-openspec-workflow.cjs` 已是同型 linter |
| `autopilot-full/stack`、`orchestrate`、`shipping` 的 stack 部分 | 依賴 Cursor cloud agents、Projects、Origin forge；你的 repo 慣例是單 PR squash，沒有 stacked PR |
| `arena`、`architect` 本體 | multi-agent-debate＋brainstorming 已覆蓋；跨家族 judge 在 Claude Code 只剩 Claude，我方已有 codex 作跨 vendor 層。只取紅旗清單（見 P3） |
| `how` | codegraph_explore 一次呼叫即可 |
| `tdd` | superpowers TDD 已覆蓋 |
| `unslop`、`technical-writing` | 規則以英文為對象（em dash、AI 詞彙表）；中文寫作要另訂。只有 rule 27「這句放進別的專案文件也成立，就等於沒說」值得借（可併入 `claude-md-authoring.md`） |
| `no-comments`／Comment Sicko | 立場是幾乎刪光註解，與你目前「comment 寫事實、寫理由」的路線方向不同；pr-review-toolkit comment-analyzer 已覆蓋準確性。其中「約束型註解應改成型別、測試或 lint 來表達」與 encode-lessons 同構，可在 P2 的 3.2 一併處理 |
| `create/maintain-formal-verification-skill`、`statechart` | TLA+／TLC 需 mise、Java、網路；你的專案類型（Laravel、plugin 工具）少有並行狀態機。等出現「測試到不了的 race 或狀態機」時再評估 |
| `hillclimb`、`perf-issue`、`runtime/trace-forensics`、`visual-parity` | 領域偏效能與 UI 像素；需要時以 P1 的 2.2 數字審查打底即可 |
| `recall`、`session-pickup`、`pause-safely` | 內建 resume、compaction、usage-limit 續跑已覆蓋（CLAUDE.md 明文「內建已做，別重造」） |
| `make-bot-ui`、`ketchup-video`、`bro`、`in-your-own-words`、`teach`、`typescript-best-practices`、`automate-me` 本體 | Cursor 專屬、與既有 skill（eli5、show-me、session-learning）重疊，或價值低 |
| 24 條 principle 全文 | 大部分已在 superpowers 與 CLAUDE.md 以更具體的形式存在；依知識架構三問，不值得當常駐文字。個別借用見 P3 |

## 6. 建議的討論順序

1. **2.1 證據階梯**：動到 code-audit-rigor 的 schema，屬 public contract，依 SKIP 條款要走 openspec workflow。要先決定第 4 階是「鼓勵」還是 correctness 類「必要」。
2. **2.2 數字審查**：最便宜，能立刻套到下一輪 eval 或 model-router 分析。
3. **2.3 PR 就緒判定器**：要先決定 sandbox 內外的執行方式。
4. P2 的 3.1（patch-id）可與 2.3 合併成同一個「PR 收尾強化」變更。

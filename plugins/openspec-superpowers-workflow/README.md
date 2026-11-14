# OpenSpec + Superpowers Workflow Plugin

強制執行 OpenSpec（規格生命週期，WHAT）與 Superpowers（開發紀律，HOW）嚴格角色分離的六階段功能開發工作流程，避免兩種工具的職責重疊與規格漂移。

## 前置需求

- **[OpenSpec CLI](https://github.com/Fission-AI/OpenSpec) 2.x**（`npm i -g @fission-ai/openspec`，需要 Node 22.12 以上）— 規格生命週期管理。文件裡的 CLI 與 skill（`/openspec-*`）敘述以 `tests/openspec-version` 記的版本為準，由 `tests/cli-claims.test.sh` 對照真實 CLI 檢查
  - **從 OpenSpec 1.x 升級（本 plugin 4.0 起）**：2.0 移除了 `/opsx:*` slash 指令，每個都改成同一個 workflow 的 skill：propose 是 `/openspec-propose`、apply 是 `/openspec-apply-change`、archive 是 `/openspec-archive-change`，其餘見 `phases.md` 的「OpenSpec skills by phase」。升級 CLI 後在每個專案跑一次 `openspec update` 並 commit；它會裝上 skill、移除舊的指令檔（改過的會保留並列出）。仍用 OpenSpec 1.x 的專案請留在本 plugin 3.x
- **[Superpowers](https://github.com/anthropic-experimental/claude-code-plugins/tree/main/superpowers)** — 開發紀律 skills（`brainstorming`、`writing-plans`、`subagent-driven-development`、`test-driven-development` 等）
- 專案需先跑過 `openspec init .`（無 `--here` flag）

## 概述

這個 plugin 包含一個 skill（`openspec-superpowers-workflow`）與兩個 PreToolUse hook（skip-gate、archive-gate，見下方專節）。當 skill 偵測到使用者在進行功能開發任務（propose / brainstorm / plan / implement / review / reconcile / archive）時會被自動觸發，引導 Claude 依六階段推進，並嚴格禁止常見的反模式（如 Phase 5 code review 期間改 spec、Phase 6 reconcile 時用 patch 而非 clean rewrite、把 cross-cutting 規則塞進 feature spec 等）。

## 六階段工作流程

| Phase | 主導工具 | 動作 | 產出 |
|-------|---------|------|------|
| 1. Spec Definition | OpenSpec | `openspec new change` + 填入 proposal / specs | `proposal.md`（含 `## Decisions`）、`specs/<capability>/spec.md`（`gate-check.cjs p1` 決定要不要等核准，見下方 Gates） |
| 2. Design Refinement | Superpowers `brainstorming` | 先列假設、全 phase 至多 2 題提問，對照設計紅旗後精煉設計 | **覆寫** `design.md` |
| 3. Task Planning | Superpowers `writing-plans` | 切出 2-5 分鐘粒度任務 | **覆寫** `tasks.md` |
| 4. Implementation | Superpowers `executing-plans`（task 獨立時 `subagent-driven-development`）+ TDD | RED → GREEN → REFACTOR | 程式碼 |
| 5. Review & Feedback | 人類主導 | 分類 `[REQUIREMENT\|DESIGN\|CODE\|CONSTITUTION]` + Y/N | `review-notes.md`，**spec 一律不動** |
| 6. Reconcile & Archive | OpenSpec | Clean rewrite spec（非 patch）+ `openspec archive` | 歸檔至 `openspec/changes/archive/<date>-<name>/`，合併到 `openspec/specs/` |

## 不可妥協的六條硬規則

1. **Phase 5 期間絕不修改 spec 檔**。所有審查意見必須記到 `review-notes.md`，用 `[REQUIREMENT|DESIGN|CODE|CONSTITUTION]` tag 加 Y/N 分類——Y 只回答「Phase 6 是否必須更新某個 OpenSpec artifact」，不是「已處理」，所以 `[CODE] Y` 不存在；tag 看修改落在哪個檔案，不看問題性質。1.5.0 起 Phase 1 建檔即預填一段標頭把這套語意釘住，避免各專案自行發明「Y = 已處理」（真實歸檔資料曾出現 54 條 `[CODE] Y`）。被明確要求「現在改 spec」時必須明講拒絕並記錄，不得默默改道
2. **Superpowers 絕不新建自己的 design / plan 檔**。輸出一律覆寫 OpenSpec 的 `design.md` / `tasks.md` 原位
3. **Phase 6 reconcile 必須 clean rewrite**。目標是讓 spec 讀起來像「一開始就知道所有這些事」，而非「一份加註解的修訂史」。歸檔前必須跑 `reconcile-check.cjs check`，歸檔閘門 hook 會驗證它的結果
4. **`tasks.md` 是執行紀錄**：Phase 4 每完成一個任務就把它的框勾成 `[x]`，不做的任務保持未勾並在行尾寫 ` — skip: <理由>`；每個 `### Task N` 標題下只放一個勾選框（OpenSpec 把每個框都算成一個 task）。Phase 6 的 snapshot 之後絕不修改，它是執行歷史，不是當前規格
5. **`[CONSTITUTION]` 項目絕不進 feature spec**。改到 `openspec/config.yaml` 的 `context:` / `rules:` 欄位
6. **Phase 4 TDD 強制**。先寫失敗測試，再寫實作，永遠如此

## Skill 結構（Progressive Disclosure）

```
skills/openspec-superpowers-workflow/
├── SKILL.md                    # 61 行：trigger 條件、SKIP 條款、phase map、六條硬規則（常駐載入）
├── PHASE-IDENTIFICATION.md     # 97 行：Phase 判定決策樹、SKIP 判定程序（Phase 不明時載入）
├── phases.md                   # 447 行：完整六階段 playbook、tag 分類細節、路徑慣例、anti-pattern（需要時才載入）
├── SUPERPOWERS-HANDOFF.md      # 142 行：Phase 2/3/4 sync-back 範本、sidecar 檔 anti-pattern
├── OUTPUT-CONTRACTS.md         # 219 行：各 Phase 產出契約、requirement 寫法正反例、deferred 項慣例
├── RECONCILIATION-CRITERIA.md  # 128 行：Phase 6 歸檔前核查清單
├── DESIGN-RED-FLAGS.md         # 八條設計紅旗（Phase 2 覆寫 design.md 前自檢）
└── validators/
    ├── validate-openspec-workflow.cjs  # change folder 寬鬆 pre-check（見下方 Validator）
    ├── reconcile-check.cjs             # Phase 6 歸檔前核查（snapshot／check／verify，見下方 Archive gate）
    ├── gate-check.cjs                  # p1／p2／p3／p6b 確認點：停下等使用者（exit 10）或繼續（exit 0），見下方 Gates
    └── safe-write.cjs                  # .claude/ 底下的狀態檔，寫入時不跟隨 symlink（gate-check 與 reconcile-check 共用）
```

觸發時 Claude 先讀 `SKILL.md`，確認當前 Phase 後只載入該 Phase 需要的 reference（Phase 不明讀 `PHASE-IDENTIFICATION.md`、playbook 讀 `phases.md` 對應段落、Phase 2/3/4 交接讀 `SUPERPOWERS-HANDOFF.md`、Phase 6 歸檔前讀 `RECONCILIATION-CRITERIA.md`），避免一次吃下近 900 行拖慢 context。

## 解決的問題

無此 skill 時常見的混亂：

- ❌ 跑完 Superpowers `brainstorming` 後把結果寫到 `docs/superpowers/specs/<date>-<topic>.md`（Superpowers 預設路徑），而非覆寫 OpenSpec 的 `design.md`，導致兩份「設計檔」彼此漂移
- ❌ Code review 拿到意見後直接改 spec，archive 時才發現 spec 和實作對不上
- ❌ Phase 6 reconcile 時用「加一段 Round 1 修訂」的方式 patch spec，結果半年後沒人看得懂修訂史
- ❌ 把「所有 PHP 檔都要 `declare(strict_types=1)`」這種 cross-cutting 規則塞進某個 feature 的 spec，下個 feature 又要重寫一遍

有此 skill 時：

- ✅ Claude 自動認出當前 Phase 並套用對應紀律
- ✅ 所有中間產物都落在 `openspec/changes/<name>/` 同一個資料夾，不會分散
- ✅ `review-notes.md` 作為 Phase 5/6 的唯一 feedback 通道，reconcile 時有明確的 Y 項清單
- ✅ CONSTITUTION 規則有明確的寫入目標（`openspec/config.yaml`），不會污染 feature spec

## 何時不適用

- 單一模組、驗收明確、且不觸碰任何契約面（public API / data contract / schema / migration / 向後相容 / 安全權限邊界 / 並行一致性 / 跨模組行為）的變更，例如無規格影響的小型 bug 修復 — 直接用裸 superpowers skills 以 TDD 修好，不走六階段；看契約風險，不看 LOC 或檔案數。SKIP 前必須逐項核對八項契約面，並把結論寫進聲明檔（見下方 skip-gate hook）

SKIP 的唯一依據是上述契約面判定，沒有其他豁免類別（例如「原型探索」本身不構成豁免，仍依契約面判定）。**觸發也不以專案已有 `openspec/` 資料夾為前提**：只要是提出／新增／精煉 feature 等 trigger 條件即觸發；專案尚未初始化時，skill 會在前置檢查引導執行 `openspec init .`。

## 用法提示

你通常不需要「手動呼叫」這個 skill — 它會在你說「propose a new feature」、「brainstorm the design」、「plan the tasks」、「I got PR review feedback」、「reconcile and archive」等關鍵字時自動觸發。真要手動執行：

```
/skill openspec-superpowers-workflow
```

進入 skill 後它會先讀取當前專案狀態（`which openspec`、`ls openspec/`、`.claude/skills/` 裡的 `openspec-*`，以及 1.x 留下的 `.claude/commands/opsx/`），依結果引導你走正確的 Phase。

## Gates：什麼時候停下來等你（3.0）

2.x 在 P1（proposal／spec）、P2（design）、P3（tasks）、P6b（改寫後的 spec）一律停下等核准。歷史資料顯示，P1–P3 的 87 次確認只有 1 次真的退回；確認點上抓到的問題，都是使用者要求「加跑審查」之後才浮現的（分析見 `docs/openspec-hitl-gate-analysis-2026-11-10.md`）。3.0 改成由事實決定要不要停：

| 確認點 | 3.0（預設 `risk-based`） |
|---|---|
| P1 | `gate-check.cjs p1`：結構事實（`BREAKING`、修改／移除／改名既有 requirement 的 delta）、`[needs user]` 標記（任何項目寫法、任何段落）、命中 `high_risk_paths`、沒有任何 spec（`.openspec.yaml` 設 `skip_specs: true` 者除外）或讀不到 spec 時，先派 opus 獨立審查、重跑一次 p1 更新記錄，再停下；否則公告採用的預設後繼續 |
| P2 | `gate-check.cjs p2`：design.md 任何位置有 `[needs user]`、讀不到 design.md，或出現 P1 沒看過的結構事實（P1 之後才出現的 BREAKING、delta、高風險路徑命中，不論改的是 proposal、spec 還是 high_risk_paths 設定；p1 每次執行都把看到的寫進 `.claude/openspec-gate.<change>.local.json`），才停 |
| P3、P6b | `gate-check.cjs p3`／`p6b` 只在 `gates: supervised` 或設定讀不懂時停；p3 先核對 tasks.md 每個 `### Task N` 恰好一個勾選框，不合格 exit 1 由 agent 修好再跑；P6b 的改寫摘要寫進回覆與歸檔 PR，reconcile-check 仍是歸檔閘門 |
| P5 | 宣告收斂仍由你決定；條件成立時 agent 會主動建議收斂 |

完整的停下規則只寫在 `skills/openspec-superpowers-workflow/phases.md` 的「Gates」節。

**設定**（都是選用，只讀 front matter）：
- `.claude/openspec-workflow.md`（進版控，描述專案）：`high_risk_paths:` 底下列 `- <glob>`，縮排與否都可，中間可以有空白行和 `#` 註解（`**` 跨目錄，`*` 不跨；不含 `/` 的 glob 比對根目錄檔名，如 `Dockerfile`）。行內寫法 `high_risk_paths: [a, b]`、拼錯的 key、重複的 `gates:` 都算設定讀不懂（停下，不會靜默當成空清單）。
- `.claude/openspec-workflow.local.md`（gitignored，個人偏好）：`gates: supervised` 回到 2.x 的每個確認點都停。它的 `gates` 覆蓋前者；`high_risk_paths` 與前者取聯集，只能多加、不能拿掉專案列的路徑。兩個檔案都在專案根目錄（放 `openspec/` 的那一層）的 `.claude/` 底下。

**界線**：
- 設定檔讀不懂、`gates` 值認不得，一律視同停下。方向刻意和兩支 hook 的 fail-open 相反：這裡出錯的代價是跳過人類決策。沒有 shell 的 session 照同一份規則手動判定。
- `[needs user]`／`[default]` 是 agent 自己寫的標記，gate-check 分辨不出誠實與否，只是提醒。真正擋得住漏判的只有結構事實（BREAKING、delta 標題）。

**測試**：`bash plugins/openspec-superpowers-workflow/tests/gate-check.test.sh`（已接 CI；每個停下的理由至少兩個觸發輸入，七個突變各自轉紅）。

## Skip-gate Hook

SKIP 判定曾在真實 session 中被「憑摘要句自由心證」繞過（變更實際觸碰跨模組行為、且落在已 spec 化能力域）。1.4 版的 hook 在第一次編輯擋一次、要求在回覆中逐項核對，但兩個月的紀錄顯示 12 次攔截後沒有一次留下逐項聲明：模型直接重試就放行。現行版本要求把判斷寫成一個 hook 讀得到的檔案：

- **觸發條件**（全部成立才攔）：專案有 `openspec/` 目錄；`openspec/changes/` 無 active change（`archive/` 不算）；本次編輯的是專案內的非文件檔（`openspec/`、`.claude/`、`.md .mdx .txt .rst .adoc`、`docs/`、`doc/` 都不攔）
- **聲明檔**：`.claude/openspec-skip.<session>.local.md`，其中一行 `契約面：API=否 資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 跨模組=否 ｜ 理由：<一句>`。檔案不存在、`｜` 之前缺任何一個 key、同一 key 出現兩次、值不是整個詞的「是／否」都擋（`理由：` 裡的文字不算）；**任何一面是「是」也擋**，並要求啟動 workflow（Phase 1）
- **歸檔之後**：本 session 經歸檔閘門放行過歸檔時，聲明檔必須比那次歸檔新，歸檔前寫的不算。聲明檔也必須比 `openspec/changes/archive/` 目錄本身新：其他 session 的歸檔、以 `OPENSPEC_ARCHIVE_OK=1` 略過閘門的歸檔都不留標記，但都會動到這個目錄。該目錄的 mtime 落在未來時（時鐘偏差、保留 mtime 的複製）這條比較略過，否則聲明怎麼重寫都不會比它新。代價是任何讓該目錄 mtime 前進的動作（例如切到多了一個已歸檔 change 的分支）也會要求重寫一次聲明
- **同一批並行編輯**：聲明檔不存在時全部被擋，寫好後全部重試
- **界線**：hook 只確認判斷被寫下來、八個 key 各出現一次且值為是／否、且沒有任何一面是「是」，不驗證判斷對不對（契約風險是語意判斷，機器判不了）；全面 fail-open——jq 缺失、輸入異常、不明工具形狀等任何錯誤路徑都放行；matcher 只綁核心編輯工具（Edit/Write/MultiEdit/NotebookEdit），MCP 檔案編輯工具（serena、morphllm 等）不在覆蓋面內
- **測試**：`bash plugins/openspec-superpowers-workflow/tests/skip-gate.test.sh`（已接 CI；文件豁免、「任一面是」、歸檔後新舊比較（標記與 `archive/` 目錄兩條）、八個 key 的檢查均經 mutation 驗證）

## Archive Gate Hook

Phase 6 的歸檔前核查原本只寫在文字裡；兩個月內 9 個實際歸檔的 session，對核查清單的讀取次數是 0，另有 4 個 session 在 review 收斂前就先歸檔。archive-gate 讓歸檔必須先有一份新鮮的核查結果：

- **攔哪些命令**：`openspec archive <name>`，以及 `/openspec-archive-change`、`/openspec-bulk-archive-change` 兩個 skill 執行的 `mkdir` + `mv <changes>/<name> <changes>/archive/<date-name>`（bulk 時命令裡每個 change 都要通過）。`hooks.json` 以 `if` 只在 `openspec archive *` 與 `mv *` 時啟動
- **放行條件**：`validators/reconcile-check.cjs check` 對該 change 記下的 pass verdict 存在、是現行核查規則版本寫的（plugin 升級讓規則變嚴時，舊結果回報 `stale:rules`，要重跑 check），且之後 proposal、design、tasks、review-notes、specs 都沒有再改（`verify` 比對雜湊）
- **核查內容**：R1–R9，對應 `RECONCILIATION-CRITERIA.md` 的 C1–C5；其中 R4 要求 review 最後一輪標了 `final`，而 `final` 只能在使用者明說 review 已收斂後才加
- **繞過**：命令前加 `OPENSPEC_ARCHIVE_OK=1`，只在使用者明確要求時使用
- **界線**：機械檢查不取代判斷——C1、C2、C5 以 `manual` 列出，仍由代理逐項判斷並寫在回覆裡；全面 fail-open（缺 jq／perl／node、解析不到 change 名稱、change 目錄不存在、`reconcile-check.cjs` 自身崩潰都放行）；只認上述兩種命令形狀（接在 `then`／`do`／`!`／`{` 等關鍵字或 `env`／`command`／`exec`／`time` 之後、放在反引號裡、交給 `bash -c`／`sh -c`／`eval` 的命令字串都算；經 stdin 餵給 shell 的 `bash <<EOF`、`… | bash` 不算），`git mv`、`cp` 加 `rm`、`npx openspec`、從 `changes/` 目錄內用相對路徑 `mv` 等寫法不在覆蓋面內（設計取捨：解析不到名稱即放行）；heredoc 本體不算命令，但 bash 照樣執行的部分算：雙引號內、以及 delimiter 未加引號的 heredoc 本體內的 `$( … )` 與反引號（`<<'EOF'`、`<<\EOF` 的本體、單引號內、跳脫的 `\$` 都不算）；這些替換與交給 shell 的命令字串排進同一個佇列、最多掃 50 個，超出的部分不再掃描（放行）；here-string（`<<<`）、引號裡的 `<<`（引號狀態跨行延續；`$( … )` 內重新起算）、`$(( … ))` 裡的位移、以及等不到收尾行的 `<<`（算術位移 `$((1<<n))`）都不當成 heredoc，其後的行仍算命令；收尾行必須整行等於 delimiter，在 `$( … )` 裡以 `EOF)` 收尾也算（3.2.0 起）；`#` 開頭的詞到行尾是註解（在反引號替換裡只到結束的反引號），裡面的撇號不會開出字串；`${…}` 整段是一個詞的內部，裡面的 `#`、引號、空白都不開啟任何東西，但其中的 `$( … )`／反引號仍會被當命令掃；每條命令會用三種讀法各掃一次、結果取聯集：前兩種是上述規則與加入註解規則之前的讀法，第三種（3.2.0 起）是照 bash 逐字元讀的 lexer，另外讀得到行尾 `\` 續行後的命令、反引號裡沒收尾的引號、黏在詞上的重導向、混合引號的 delimiter（`<<'E'"F"`）、雙引號內替換裡的雙引號字串（`echo "x $(echo "a"; openspec archive foo) y"`）、`$(( … ))` 與 `$[ … ]` 裡的替換；新讀法即使有錯也只會多擋、不會少擋。已知缺口：bash 判為語法錯誤而整行丟棄的那一行（例如 `a=(-( <<EOF`）上的 heredoc 不算數，其後的行 bash 照常執行，三種讀法卻都當成本體（記在 follow-ups，由 `tokenizer-differential.test.sh` 的 `--gap 0` 盯著）
- **測試**：`bash plugins/openspec-superpowers-workflow/tests/archive-gate.test.sh`、`bash plugins/openspec-superpowers-workflow/tests/reconcile-check.test.sh`（已接 CI；放行與 deny 路徑、`mv` 解析、繞過字樣、歸檔標記、雜湊失效、各 R 檢查均經 mutation 驗證；另有一組案例讓 archive-gate 放行後接著跑 skip-gate，守住兩支 hook 共用的標記名稱；lexer 的 11 條路徑由套件內建的 mutant 守，跑在只留 lexer 的副本上）；`bash plugins/openspec-superpowers-workflow/tests/tokenizer-differential.test.sh` 用 bash 本身當正確答案：在只放了假 `openspec`／`gh` 的環境裡執行隨機生成的命令，在這套生成語法範圍內，兩支 gate 的 parser 必須抓到 bash 實際執行到的每一個 `openspec archive`／`gh pr merge`（反方向不要求，閘門刻意保守；`mv` 歸檔、`gh api …/merge` 與 MCP merge 不在生成語法內）；並且要能分辨 #48、#51、#55、W5-8 每次修正前後的版本；另有一項不靠 bash 的不變量（3.2.1 起）：在生成的命令上，兩支 gate 回報的不得少於 3.2.0（`b16fb23`）——這是保留兩種舊讀法的理由，只留 lexer 時這項檢查會失敗（從 git 歷史讀，CI 以 `fetch-depth: 0` 取完整歷史）；`bash plugins/openspec-superpowers-workflow/tests/shared-tokenizer.test.sh` 比對 archive-gate 與 pr-closeout merge 閘門裡以 `# >>> shared-tokenizer:` 標記界定的兩段 tokenizer 必須一致（兩個 plugin 分開安裝、無法互相引用，各留一份副本）

## 版本

詳見 [CHANGELOG.md](./CHANGELOG.md)。

## Validator

OpenSpec change folders are validated by a zero-dependency Node script. Run from the repo root:

```bash
# Validate a change folder (checks required files + SHALL/MUST in spec.md requirement blocks)
node plugins/openspec-superpowers-workflow/skills/openspec-superpowers-workflow/validators/validate-openspec-workflow.cjs openspec/changes/<name>

# Run all fixture checks
node scripts/validate-fixtures.cjs
```

> The `.cjs` validator is a fast, lenient **pre-check**: it confirms the required files exist and that each `### Requirement:` block's first paragraph contains SHALL/MUST (a bullet immediately after the heading is treated as that paragraph). It does not fully replicate `openspec validate --strict` — the strict CLI remains the authoritative gate (e.g. it rejects a SHALL that appears only inside a bullet list). Run `openspec validate --strict` before archiving.

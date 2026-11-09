# OpenSpec + Superpowers Workflow Plugin

強制執行 OpenSpec（規格生命週期，WHAT）與 Superpowers（開發紀律，HOW）嚴格角色分離的六階段功能開發工作流程，避免兩種工具的職責重疊與規格漂移。

## 前置需求

- **[OpenSpec CLI](https://github.com/Fission-AI/OpenSpec)**（`npm i -g @fission-ai/openspec`）— 規格生命週期管理
- **[Superpowers](https://github.com/anthropic-experimental/claude-code-plugins/tree/main/superpowers)** — 開發紀律 skills（`brainstorming`、`writing-plans`、`subagent-driven-development`、`test-driven-development` 等）
- 專案需先跑過 `openspec init .`（無 `--here` flag）

## 概述

這個 plugin 包含一個 skill（`openspec-superpowers-workflow`）與兩個 PreToolUse hook（skip-gate、archive-gate，見下方專節）。當 skill 偵測到使用者在進行功能開發任務（propose / brainstorm / plan / implement / review / reconcile / archive）時會被自動觸發，引導 Claude 依六階段推進，並嚴格禁止常見的反模式（如 Phase 5 code review 期間改 spec、Phase 6 reconcile 時用 patch 而非 clean rewrite、把 cross-cutting 規則塞進 feature spec 等）。

## 六階段工作流程

| Phase | 主導工具 | 動作 | 產出 |
|-------|---------|------|------|
| 1. Spec Definition | OpenSpec | `openspec new change` + 填入 proposal / specs | `proposal.md`、`specs/<capability>/spec.md`（使用者審核） |
| 2. Design Refinement | Superpowers `brainstorming` | Socratic 問答精煉設計 | **覆寫** `design.md` |
| 3. Task Planning | Superpowers `writing-plans` | 切出 2-5 分鐘粒度任務 | **覆寫** `tasks.md` |
| 4. Implementation | Superpowers `subagent-driven-development` + TDD | RED → GREEN → REFACTOR | 程式碼 |
| 5. Review & Feedback | 人類主導 | 分類 `[REQUIREMENT\|DESIGN\|CODE\|CONSTITUTION]` + Y/N | `review-notes.md`，**spec 一律不動** |
| 6. Reconcile & Archive | OpenSpec | Clean rewrite spec（非 patch）+ `openspec archive` | 歸檔至 `openspec/changes/archive/<date>-<name>/`，合併到 `openspec/specs/` |

## 不可妥協的六條硬規則

1. **Phase 5 期間絕不修改 spec 檔**。所有審查意見必須記到 `review-notes.md`，用 `[REQUIREMENT|DESIGN|CODE|CONSTITUTION]` tag 加 Y/N 分類——Y 只回答「Phase 6 是否必須更新某個 OpenSpec artifact」，不是「已處理」，所以 `[CODE] Y` 不存在；tag 看修改落在哪個檔案，不看問題性質。1.5.0 起 Phase 1 建檔即預填一段標頭把這套語意釘住，避免各專案自行發明「Y = 已處理」（真實歸檔資料曾出現 54 條 `[CODE] Y`）。被明確要求「現在改 spec」時必須明講拒絕並記錄，不得默默改道
2. **Superpowers 絕不新建自己的 design / plan 檔**。輸出一律覆寫 OpenSpec 的 `design.md` / `tasks.md` 原位
3. **Phase 6 reconcile 必須 clean rewrite**。目標是讓 spec 讀起來像「一開始就知道所有這些事」，而非「一份加註解的修訂史」。歸檔前必須跑 `reconcile-check.cjs check`，歸檔閘門 hook 會驗證它的結果
4. **`tasks.md` 在 reconcile 時絕不修改**。它是執行歷史，不是當前規格
5. **`[CONSTITUTION]` 項目絕不進 feature spec**。改到 `openspec/config.yaml` 的 `context:` / `rules:` 欄位
6. **Phase 4 TDD 強制**。先寫失敗測試，再寫實作，永遠如此

## Skill 結構（Progressive Disclosure）

```
skills/openspec-superpowers-workflow/
├── SKILL.md                    # 61 行：trigger 條件、SKIP 條款、phase map、六條硬規則（常駐載入）
├── PHASE-IDENTIFICATION.md     # 95 行：Phase 判定決策樹、SKIP 判定程序（Phase 不明時載入）
├── phases.md                   # 330 行：完整六階段 playbook、tag 分類細節、路徑慣例、anti-pattern（需要時才載入）
├── SUPERPOWERS-HANDOFF.md      # 140 行：Phase 2/3/4 sync-back 範本、sidecar 檔 anti-pattern
├── OUTPUT-CONTRACTS.md         # 218 行：各 Phase 產出契約、requirement 寫法正反例、deferred 項慣例
├── RECONCILIATION-CRITERIA.md  # 116 行：Phase 6 歸檔前核查清單
└── validators/
    ├── validate-openspec-workflow.cjs  # change folder 寬鬆 pre-check（見下方 Validator）
    └── reconcile-check.cjs             # Phase 6 歸檔前核查（snapshot／check／verify，見下方 Archive gate）
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

進入 skill 後它會先讀取當前專案狀態（`which openspec`、`ls openspec/`、`ls .claude/commands/opsx/`），依結果引導你走正確的 Phase。

## Skip-gate Hook

SKIP 判定曾在真實 session 中被「憑摘要句自由心證」繞過（變更實際觸碰跨模組行為、且落在已 spec 化能力域）。1.4 版的 hook 在第一次編輯擋一次、要求在回覆中逐項核對，但兩個月的紀錄顯示 12 次攔截後沒有一次留下逐項聲明：模型直接重試就放行。現行版本要求把判斷寫成一個 hook 讀得到的檔案：

- **觸發條件**（全部成立才攔）：專案有 `openspec/` 目錄；`openspec/changes/` 無 active change（`archive/` 不算）；本次編輯的是專案內的非文件檔（`openspec/`、`.claude/`、`.md .mdx .txt .rst .adoc`、`docs/`、`doc/` 都不攔）
- **聲明檔**：`.claude/openspec-skip.<session>.local.md`，其中一行 `契約面：API=否 資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 跨模組=否 ｜ 理由：<一句>`。檔案不存在、`｜` 之前缺任何一個 key、同一 key 出現兩次、值不是整個詞的「是／否」都擋（`理由：` 裡的文字不算）；**任何一面是「是」也擋**，並要求啟動 workflow（Phase 1）
- **歸檔之後**：本 session 經歸檔閘門放行過歸檔時，聲明檔必須比那次歸檔新，歸檔前寫的不算
- **同一批並行編輯**：聲明檔不存在時全部被擋，寫好後全部重試
- **界線**：hook 只確認判斷被寫下來、八個 key 各出現一次且值為是／否、且沒有任何一面是「是」，不驗證判斷對不對（契約風險是語意判斷，機器判不了）；全面 fail-open——jq 缺失、輸入異常、不明工具形狀等任何錯誤路徑都放行；matcher 只綁核心編輯工具（Edit/Write/MultiEdit/NotebookEdit），MCP 檔案編輯工具（serena、morphllm 等）不在覆蓋面內
- **測試**：`bash plugins/openspec-superpowers-workflow/tests/skip-gate.test.sh`（已接 CI；文件豁免、「任一面是」、歸檔後新舊比較、八個 key 的檢查均經 mutation 驗證）

## Archive Gate Hook

Phase 6 的歸檔前核查原本只寫在文字裡；兩個月內 9 個實際歸檔的 session，對核查清單的讀取次數是 0，另有 4 個 session 在 review 收斂前就先歸檔。archive-gate 讓歸檔必須先有一份新鮮的核查結果：

- **攔哪些命令**：`openspec archive <name>`，以及 OpenSpec 1.16 `/opsx:archive` 範本的 `mkdir` + `mv <changes>/<name> <changes>/archive/<date-name>`（bulk 時命令裡每個 change 都要通過）。`hooks.json` 以 `if` 只在 `openspec archive *` 與 `mv *` 時啟動
- **放行條件**：`validators/reconcile-check.cjs check` 對該 change 記下的 pass verdict 存在，且之後 proposal、design、tasks、review-notes、specs 都沒有再改（`verify` 比對雜湊）
- **核查內容**：R1–R9，對應 `RECONCILIATION-CRITERIA.md` 的 C1–C5；其中 R4 要求 review 最後一輪標了 `final`，而 `final` 只能在使用者明說 review 已收斂後才加
- **繞過**：命令前加 `OPENSPEC_ARCHIVE_OK=1`，只在使用者明確要求時使用
- **界線**：機械檢查不取代判斷——C1、C2、C5 以 `manual` 列出，仍由代理逐項判斷並寫在回覆裡；全面 fail-open（缺 jq／perl／node、解析不到 change 名稱、change 目錄不存在、`reconcile-check.cjs` 自身崩潰都放行）；只認上述兩種命令形狀，`git mv`、`cp` 加 `rm`、`npx openspec`、從 `changes/` 目錄內用相對路徑 `mv` 等寫法不在覆蓋面內（設計取捨：解析不到名稱即放行）
- **測試**：`bash plugins/openspec-superpowers-workflow/tests/archive-gate.test.sh`、`bash plugins/openspec-superpowers-workflow/tests/reconcile-check.test.sh`（已接 CI；放行與 deny 路徑、`mv` 解析、繞過字樣、歸檔標記、雜湊失效、各 R 檢查均經 mutation 驗證）

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

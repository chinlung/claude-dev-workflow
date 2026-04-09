# OpenSpec + Superpowers Workflow Plugin

強制執行 OpenSpec（規格生命週期，WHAT）與 Superpowers（開發紀律，HOW）嚴格角色分離的六階段功能開發工作流程，避免兩種工具的職責重疊與規格漂移。

## 前置需求

- **[OpenSpec CLI](https://github.com/Fission-AI/OpenSpec)**（`npm i -g @fission-ai/openspec`）— 規格生命週期管理
- **[Superpowers](https://github.com/anthropic-experimental/claude-code-plugins/tree/main/superpowers)** — 開發紀律 skills（`brainstorming`、`writing-plans`、`subagent-driven-development`、`test-driven-development` 等）
- 專案需先跑過 `openspec init .`（無 `--here` flag）

## 概述

這個 plugin 只包含一個 skill：`openspec-superpowers-workflow`。當 skill 偵測到使用者在進行功能開發任務（propose / brainstorm / plan / implement / review / reconcile / archive）時會被自動觸發，引導 Claude 依六階段推進，並嚴格禁止常見的反模式（如 Phase 5 code review 期間改 spec、Phase 6 reconcile 時用 patch 而非 clean rewrite、把 cross-cutting 規則塞進 feature spec 等）。

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

1. **Phase 5 期間絕不修改 spec 檔**。所有審查意見必須記到 `review-notes.md`，用 `[REQUIREMENT|DESIGN|CODE|CONSTITUTION]` tag 加 Y/N 分類
2. **Superpowers 絕不新建自己的 design / plan 檔**。輸出一律覆寫 OpenSpec 的 `design.md` / `tasks.md` 原位
3. **Phase 6 reconcile 必須 clean rewrite**。目標是讓 spec 讀起來像「一開始就知道所有這些事」，而非「一份加註解的修訂史」
4. **`tasks.md` 在 reconcile 時絕不修改**。它是執行歷史，不是當前規格
5. **`[CONSTITUTION]` 項目絕不進 feature spec**。改到 `openspec/config.yaml` 的 `context:` / `rules:` 欄位
6. **Phase 4 TDD 強制**。先寫失敗測試，再寫實作，永遠如此

## Skill 結構（Progressive Disclosure）

```
skills/openspec-superpowers-workflow/
├── SKILL.md      # 58 行：trigger 條件、phase map、六條硬規則（常駐載入）
└── phases.md     # 290+ 行：完整六階段 playbook、tag 分類細節、路徑慣例、anti-pattern（需要時才載入）
```

觸發時 Claude 先讀 `SKILL.md`，確認當前 Phase 後再讀 `phases.md` 的對應段落，避免一次吃下 350 行拖慢 context。

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

- 無規格影響的小型 bug 修復 — 直接 TDD 修好，不走六階段
- 純實驗性原型 — Phase 1 的正式 spec 會拖慢探索
- 不使用 OpenSpec 的專案 — skill 會自動不觸發（偵測不到 `openspec/` 資料夾）

## 用法提示

你通常不需要「手動呼叫」這個 skill — 它會在你說「propose a new feature」、「brainstorm the design」、「plan the tasks」、「I got PR review feedback」、「reconcile and archive」等關鍵字時自動觸發。真要手動執行：

```
/skill openspec-superpowers-workflow
```

進入 skill 後它會先讀取當前專案狀態（`which openspec`、`ls openspec/`、`ls .claude/commands/opsx/`），依結果引導你走正確的 Phase。

## 版本

1.0.0 — 初始發布。詳見 [CHANGELOG.md](./CHANGELOG.md)。

---
name: scope
description: 工作範圍帳本（<project>/.claude/scope-ledger.local.md）的維護指令：`init "<原始請求>"` 建帳本、`status` 看未完成項（無參數時預設）、`defer` 把項目移到 Deferred（理由與去處必填）、`done` 收帳並寫專案記憶。Use when — the scope-gate hook denied an edit and asked for init; a review / scan / audit just produced findings and the triage hook said to put them in the ledger first; the Stop hook listed open In-scope items; the user asks what is still unfinished, what was deferred, or to wrap up the branch. 政策：review／scan 的產出是 input、不是工單——每條 finding 先 triage（採納／延後／需使用者裁定／噪音）進帳本，未進帳本的 finding 不得動手修；原目標的 In scope 未全勾前只採納「屬於本次變更且 Must-fix」者。本 skill 不改 .gitignore、不評判 triage 內容、不取代 OpenSpec 的 tasks.md。
argument-hint: "[init \"<goal>\" | status | defer \"<item>\" --why <理由> --to <去處> | done]"
---

# /scope-ledger:scope — 工作範圍帳本

帳本是一個檔案：`<project>/.claude/scope-ledger.local.md`（每個 worktree 一份）。它是本次工作的**基線**：原始請求逐字、In scope 清單、被延後的 finding 與去處。四個 hook 讀它：主代理首次改程式碼沒有它會被 deny 一次（子代理放行）；review 入口 skill（review-branch、review-pr、security-review、codex-review-bg、claude-security、security-audit、code-review、simplify、debate、high-precision-dev:start 等）呼叫時注入 triage 政策並把 `review_rounds` 加一，review 型子代理派發只注入不計輪；Stop 時 In scope 有未勾項會 block 一次；SessionStart（含 compaction 後）會把它印回 context。帳本若被 git 追蹤，四個 hook 一律忽略它（repo 控制的內容不回放、不寫入）——`init` 會檢查並提醒。

## 帳本格式（逐字使用）

```markdown
---
goal: <使用者的原始請求，逐字一句>
branch: <git 分支名>
opened: <YYYY-MM-DD>
review_rounds: 0
---
## In scope
- [ ] <項目> ← 來源: user
- [x] <項目> ← 來源: review-branch@r1
## Deferred
- <項目> ← 來源: security-review@r2 ｜ 理由: <四問之一> ｜ 去處: <issue #N｜專案記憶｜review-notes｜won't-fix>
## Log
- <YYYY-MM-DD HH:MM> <工具> r<N>: <n> findings → <a> adopted / <d> deferred
```

三條硬規則：

1. `goal` 是使用者的話，逐字，不改寫成你的理解。
2. In scope 每一行都以 `← 來源: user` 或 `← 來源: <工具>@r<N>` 結尾（`N` 取 hook 訊息裡的輪數）。
3. Deferred 每一行都有 `理由:` 與 `去處:`；沒有去處的延後等於遺忘。

frontmatter 的 `review_rounds` 由 hook 維護，你不用動。

## `init "<goal>"`

1. 若帳本已存在且 `branch` 不是目前分支：拒絕，說明那是另一項工作，請先 `done`（或 `status` 看內容）再 `init`。
2. `git rev-parse --abbrev-ref HEAD` 取 `branch`；今天日期填 `opened`。
3. 決定 In scope：
   - `openspec/changes/<name>/`（`archive` 以外）存在 → 只寫三個階段項：`- [ ] 完成 openspec/changes/<name>/tasks.md 全部任務 ← 來源: user`、`- [ ] Phase 5 review-notes 收斂 ← 來源: user`、`- [ ] Phase 6 archive ← 來源: user`。不要把 tasks.md 的內容抄進來。
   - 否則從請求本身拆 1 到 7 項，只寫請求裡有的事，不寫你猜「順便該做」的事。
4. 用 Write 寫檔（`.claude/` 路徑不受 gate 管）。
5. 檢查是否被 git 忽略，三個 rc 都要處理：
   ```bash
   git check-ignore -q -- .claude/scope-ledger.local.md; echo "check-ignore rc=$?"
   ```
   - rc 0：已忽略，不用做事。
   - rc 1：未忽略。先 `git ls-files --error-unmatch -- .claude/scope-ledger.local.md` 看是否已被追蹤；然後**告訴使用者**在專案 `.gitignore` 加 `*.local.md`（已追蹤要先 `git rm --cached`）。**不要自己改 `.gitignore`**——那是專案自己的設定。
   - rc 128：不是 git repo 或 git 失敗，略過。
6. 回覆：印出帳本，並說明之後 review finding 會先進帳本。

## `status`（無參數時的預設）

Read 帳本、原樣印出，最後一行：`In scope 未完成 N 項｜Deferred M 項｜review 第 R 輪`。帳本不存在就說沒有，並提示 `init`。

## Triage 政策（每次 review／scan／audit 的結果在你面前時都適用）

review 的產出是 **input，不是工單**。先把每條 finding 分到四格，寫進帳本，然後才動手：

| 分類 | 判準 | 帳本動作 |
|---|---|---|
| 採納（fix now） | 屬於本次變更引入或直接相關，且不修會有實際後果 | In scope 加一行，`← 來源: <工具>@r<N>` |
| 延後（Deferred） | 真問題但不屬於本次；或 pre-existing | Deferred 加一行，`理由:` 與 `去處:` 必填 |
| 需使用者裁定 | 業務決策、取捨、範圍是否擴張 | In scope 加一行「請使用者裁定：…」，回覆中明列 |
| 噪音／won't-fix | 誤報、與設計刻意相反、無攻擊面 | 只在 Log 記一行，不進 In scope |

`理由:` 用「過度修正濾鏡」的四問之一回答：①pre-existing、非本次引入 ②已有前置檢查防護 ③不對稱是刻意設計（要能指出記錄） ④攻擊面不實存。

收斂規則：**原目標（goal）的 In scope 未全部勾完前，只採納「屬於本次變更且 Must-fix」的 finding，其餘一律 Deferred。** 每輪 review 結束在 Log 記一行：`- <日期時間> <工具> r<N>: <n> findings → <a> adopted / <d> deferred`。

hook 在 review 累計第 3 輪起會要求你先列出 In scope 剩餘項與 Deferred 清單再決定要不要再開一輪——照做，別直接開下一輪。

## `defer "<item>" --why <理由> --to <去處>`

1. 在 In scope 找到該行（未勾的）；找不到就列出現有項目讓使用者指認。
2. 用 Edit 刪掉那一行，並在 Deferred 底下加：`- <item> ← 來源: <原來源> ｜ 理由: <理由> ｜ 去處: <去處>`。
3. `--to` 只接受：`issue #N`、`專案記憶`、`review-notes`、`won't-fix`。缺 `--why` 或 `--to` 就不動檔案，直接問。

## `done`

前置條件，任一不滿足就列出缺什麼並停止：

- In scope 沒有 `- [ ]`。
- Deferred 每行都有 `去處:`。

滿足後：

1. 寫一則專案記憶（`~/.claude/projects/<專案>/memory/`，type `project`）：goal、日期、Deferred 摘要（含去處）、review 輪數。已有同主題記憶就更新它。
2. 刪除帳本檔。
3. 回覆摘要：做了什麼、延後了什麼到哪裡。

## 本 skill 不做的事

- 不改 `.gitignore`（只回報）。
- 不評判 triage 的內容——hook 逼判斷發生並寫下來，判斷是你的。
- 不取代 OpenSpec 的 `tasks.md`；有 active change 時 In scope 只放三個階段項。

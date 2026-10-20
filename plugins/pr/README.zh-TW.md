# pr

> 寫出好審的 PR body。 [English](README.md)

## 快速開始

```bash
/plugin marketplace add chinlung/claude-dev-workflow
/plugin install pr@scl-claude-plugins
```

Claude 在寫 pull request 描述時會觸發 `pr` skill，例如你說「寫 PR body」的時候；也可以用 `/pr:pr` 直接呼叫。`/commit-commands:commit-push-pr` 不會載入它：那個指令要求 Claude 在一則訊息內只呼叫工具、不用其他工具，body 由它自己依 diff 產生。

## body 長什麼樣子

```markdown
## Summary
<圖、diff 草圖或樹狀圖>

## Evidence
- **Before:** <截圖／輸出／失敗的測試執行>
  **After:** <截圖／輸出／通過的測試執行>

## Merge Danger
**Door:** <one-way 或 two-way>
**Blast Radius:** <一個詞的描述>
```

- **Summary**：用最小、足以說清重點的視覺化呈現變更，例如 pseudocode、call tree、component／file tree、Mermaid 圖，或針對變動形狀的 `diff` 草圖。每張圖都放在它支撐的那段短文字旁邊。
- **Evidence**：before 和 after。視覺變更以截圖為最優先，其次是測試執行與 console 輸出。
- **Merge Danger**：這個變更是 one-way door（破壞性或難以撤回）還是 two-way door（容易 rollback），以及影響範圍有多大。

文字保持簡短。repo 有 `GLOSSARY.md` 時，body 會用裡面的用語。

在參考版本之上加的規則：

- **語言跟著 repo 走**（1.2.0）：body 用 repo 既有 PR 的語言（用 `gh pr list` 查，或依你提供的資訊）；查不到或沒有前例時用繁體中文。段落標題、`**Door:**` 這類欄位名、檔名、指令與程式碼保留原文。
- **repo 自己的 PR template 優先**（1.1.0）：repo 有 pull request template 時，保留它的段落，三段的寫法套進去。
- **證據要親眼看到**（1.1.0，1.2.0 放寬）：只引用 session 中實際跑過的命令輸出、CI 結果，或你貼上的命令輸出，一律逐字引用並註明來源；只用文字描述的結果（「測試都過了」）不算證據，這時 body 會寫 `Not verified: <原因>`（中文 body 寫 `未驗證：<原因>`）。
- **截圖**（1.1.0）：`gh` 沒辦法上傳圖片，所以 body 會留 `**Screenshot pending:**` 佔位，由你到 GitHub 上把圖片拖進去。

## 它不做什麼

它只負責 body 的內容。不會 commit、push，也不會指派 reviewer；只有你要求時才會開或更新 PR。skill 會讓 Claude 把 body 寫成 repo 外的檔案：你只要草稿時，它交出檔案路徑；你要它開或更新 PR 時，它用 `gh pr create --body-file <file>`（或 `gh pr edit <number> --body-file <file>`）交出去。

## 檔案

- `skills/pr/SKILL.md`：Claude 載入的版本（繁體中文）。
- `skills/pr/SKILL.en.md`：英文對照版，模型不會讀它。改規則時兩份要一起改。
- `evals/`：行為回歸測試，見下一節。

## 行為驗證（eval）

`evals/` 有 7 個 case，用 with／without plugin 兩組比較來量 uplift（Δ）：只用文字描述的結果不當成證據、沒有證據時不編造、repo template 優先、沒有前例時用繁中、跟著英文前例、引用使用者貼上的輸出並註明來源與評估 merge 風險，以及一個「只要 commit message、不該觸發」的反向 case。在 plugin 根目錄執行：

```bash
claude plugin eval . --ablation with-without --model sonnet --judge-model opus --no-publish
```

judge 不可與 agent 同一個模型。結果寫在 `evals/results/`，不進版控。交付段（`gh pr create`／`edit`）沒有 case：測它需要讓 agent 能對 GitHub 寫入，而 `gh` 無法 mock。

## 來源與致謝

移植自一個獨立的 `pr` skill。1.0.0 只改了一行（`GLOSSARY.md` 那句改成 repo 有該檔才適用）；1.1.0 加了上面標 1.1.0 的三條規則與 skill 結尾的「交付 body」段（見「它不做什麼」）；1.2.0 加了語言規則，並把 skill 改寫成繁體中文，英文原文保留為 `SKILL.en.md`。原 skill 只給 Codex 用的 `agents/openai.yaml` 沒有搬過來，因為 Claude Code 不讀它。Summary 的視覺化選單取自 Humanlayer Dex Horthy 的 `show-me` skill，見 [`skills/pr/CREDITS.md`](skills/pr/CREDITS.md)。

---
description: "處理 PR review comments：抓取所有評論、分類、修復安全性/邏輯問題、測試、提交並回覆。使用方式：/review-pr <PR號碼>"
argument-hint: "<PR號碼>"
---

處理 PR #$ARGUMENTS 的所有 review comments。

## Phase 1：抓取評論

使用 `gh api` 並行抓取以下 3 個 endpoint（缺一不可，從 `git remote get-url origin` 推導 owner/repo）：

```
gh api repos/{owner}/{repo}/pulls/{id}/comments    # inline review comments（Copilot 等行級別）
gh api repos/{owner}/{repo}/pulls/{id}/reviews      # review summary body（含 suppressed/low-confidence comments）
gh api repos/{owner}/{repo}/issues/{id}/comments    # 一般留言（claude[bot]、GitHub Actions bot、人工留言）
```

彙整為統一清單，記錄來源 endpoint、審查者、內容。

## Phase 2：分類

將每個評論分類：

| 分類 | 處理 |
|------|------|
| 安全性修復 | 必須修復 — 子代理實作 + 驗證測試 |
| 邏輯錯誤 | 必須修復 — 子代理實作 + 驗證測試 |
| 程式碼風格 | 評估後修復或跳過（附理由） |
| 建議 | 驗證是否有實質問題，否則跳過 |

輸出分類表格供使用者確認後再進入修復階段。

## Phase 3：修復與驗證

對每個需要修復的評論（安全性修復 + 邏輯錯誤）：
1. 生成子代理（可並行），各自讀取相關程式碼與上下游依賴、實作修復、編寫驗證測試
2. 所有修復完成後執行全部測試套件確認無回歸

## Phase 4：提交與回覆

1. Commit — 訊息包含處理了哪些評論
2. Push 到遠端
3. 使用 `gh pr comment` 在 PR 發布回覆，格式：

```markdown
## PR Review 回應摘要

### 評論來源
| Endpoint | 審查者 | 評論數 |
|----------|--------|--------|

### 處理結果
| # | 分類 | 評論內容 | 處理 | 說明 |
|---|------|---------|------|------|

### 測試結果
Tests: N passed (M assertions)
```

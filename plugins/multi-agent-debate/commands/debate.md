---
description: 啟動多代理辯證系統，對需求進行多角度分析與辯論
argument-hint: <需求描述> [--max-rounds N] [--perspectives "角度1,角度2,角度3"]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, TodoWrite, AskUserQuestion
---

# /debate - 多代理辯證系統

啟動多代理辯證流程，透過三個不同角度的 Agent 對需求進行深度分析，並由 Critic Agent 進行批判審查，最終產出最優實踐方案。

## 任務輸入

需求描述：$ARGUMENTS

## 參數解析

在開始流程前，先解析參數：
- 從 `$ARGUMENTS` 中提取 `--max-rounds N`（預設 10），作為最大辯論輪數
- 從 `$ARGUMENTS` 中提取 `--perspectives "角度1,角度2,角度3"`，如有提供則跳過 Orchestrator 的角度配置
- 移除參數後的剩餘文字作為需求描述

## 執行流程

### Phase 0：需求分析與角度配置

**如果使用者提供了 `--perspectives`**：直接使用使用者指定的三個角度，跳過 Orchestrator 呼叫。

**否則**，使用 Task tool 調用 orchestrator agent：
```
Task(
  subagent_type="multi-agent-debate:orchestrator",
  prompt="需求描述：{需求描述}\n\n請分析需求並決定三個 Agent 的思考角度。"
)
```

等待完成後，獲取三個 Agent 的角度配置。

### Phase 1：初始方案生成（並行）

並行啟動三個 perspective agents：
```
Task(
  subagent_type="multi-agent-debate:perspective-a",
  prompt="需求描述：$ARGUMENTS\n思考角度：{角度A}\n\n請從此角度提出解決方案。",
  run_in_background=true
)

Task(
  subagent_type="multi-agent-debate:perspective-b",
  prompt="需求描述：$ARGUMENTS\n思考角度：{角度B}\n\n請從此角度提出解決方案。",
  run_in_background=true
)

Task(
  subagent_type="multi-agent-debate:perspective-c",
  prompt="需求描述：$ARGUMENTS\n思考角度：{角度C}\n\n請從此角度提出解決方案。",
  run_in_background=true
)
```

收集三個方案後，進入 Phase 2。

### Phase 2：批判審查

使用 Task tool 調用 critic agent：
```
Task(
  subagent_type="multi-agent-debate:critic",
  prompt="請審查以下三個方案並提出挑戰：\n\nAgent A 方案：{方案A}\n\nAgent B 方案：{方案B}\n\nAgent C 方案：{方案C}"
)
```

### Phase 3：反駁與修正（並行）

將 Critic 的挑戰傳遞給各 Agent 進行回應：
```
Task(
  subagent_type="multi-agent-debate:perspective-a",
  prompt="Critic 對你的挑戰：{對A的挑戰內容}\n\n請回應挑戰並表態。",
  run_in_background=true
)

Task(
  subagent_type="multi-agent-debate:perspective-b",
  prompt="Critic 對你的挑戰：{對B的挑戰內容}\n\n請回應挑戰並表態。",
  run_in_background=true
)

Task(
  subagent_type="multi-agent-debate:perspective-c",
  prompt="Critic 對你的挑戰：{對C的挑戰內容}\n\n請回應挑戰並表態。",
  run_in_background=true
)
```

### Phase 4：共識檢查

檢查共識狀態：
- ≥2 個 Agent 同意某方案 → 達成共識，進入 Phase 5
- 未達成共識且未達 {max-rounds} 輪 → 回到 Phase 2
- 達到 {max-rounds} 輪仍未達成 → Critic 最終裁決

### Phase 5：使用者互動

每輪結束後，使用 AskUserQuestion 詢問使用者：

```
AskUserQuestion(
  questions=[{
    question: "第 N 輪辯論結束，請選擇下一步",
    header: "辯論進度",
    options: [
      { label: "繼續", description: "進行下一輪辯論" },
      { label: "採納", description: "採納當前最高分方案" },
      { label: "介入", description: "調整方向或追加條件" },
      { label: "重設角度", description: "重新設定思考角度" }
    ],
    multiSelect: false
  }]
)
```

### Phase 6：最終輸出

輸出格式：

```markdown
# 🎯 最終方案

## 採納方案: [方案名稱]
**來源**: Agent [X]（[共識狀態]）
**總分**: X/30

[完整方案內容]

## 📊 評分明細

| Agent | 可行性 | 效益 | 風險控制 | 總分 |
|-------|--------|------|----------|------|
| A     | X/10   | X/10 | X/10     | X/30 |
| B     | X/10   | X/10 | X/10     | X/30 |
| C     | X/10   | X/10 | X/10     | X/30 |

<details>
<summary>📜 辯論過程（點擊展開）</summary>

[完整辯論記錄]

</details>
```

## 使用範例

```bash
# 基本用法
/debate 我想為電商網站新增商品推薦功能

# 指定最大輪數
/debate 重構使用者認證系統 --max-rounds 5

# 自訂思考角度
/debate 設計新的快取策略 --perspectives "效能優先,成本優先,簡單優先"
```

## 參數說明

- `--max-rounds N`：最大辯論輪數（預設 10）
- `--perspectives "角度1,角度2,角度3"`：自訂三個思考角度

## 注意事項

1. **進度追蹤**：使用 TodoWrite 追蹤每個 Phase 的進度
2. **錯誤處理**：如果某個 Agent 失敗，記錄錯誤並詢問使用者是否重試
3. **文件語言**：所有輸出使用繁體中文

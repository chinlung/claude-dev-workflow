---
description: 完整開發工作流程 - 從需求分析到文件撰寫的自動化流程
argument-hint: [任務描述或 GitHub Issue URL]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, WebFetch, TodoWrite, AskUserQuestion, Skill
---

# 開發工作流程主控命令

你將執行一個完整的開發工作流程，包含以下階段：
1. 需求分析 (Issue Analyst)
2. 代碼探索 (Code Archaeologist)
3. 架構設計 (Solution Architect)
4. 功能實作 (Implementation Specialist)
5. 測試撰寫 (Test Engineer)
6. 品質檢查 (Quality Assurance)
7. 文件撰寫 (Documentation Specialist)

## 任務輸入

任務描述：$ARGUMENTS

## 執行流程

### 步驟 0：初始化

1. **建立任務目錄**：
   - 獲取當前時間戳
   - 從任務描述中提取簡短名稱（英文、kebab-case）
   - 建立目錄：`docs/task-{YYYYMMDD-HHMM}-{brief-name}/`

2. **建立 handoff.md**：
   在任務目錄下建立 `handoff.md` 文件，初始化任務交接文件：

   ```markdown
   # 任務交接文件

   ## 任務資訊
   - **任務名稱**：[從任務描述提取]
   - **建立時間**：[當前時間 YYYY-MM-DD HH:MM:SS]
   - **相關 Issue**：[如有 GitHub Issue URL 則填入，否則填 N/A]
   - **任務描述**：[完整任務描述]

   ## 工作流程狀態

   ### 當前狀態
   - **Status**: 🆕 New Task
   - **Current Role**: Issue Analyst
   - **Progress**: 0/7 角色完成

   ### 角色完成狀態

   | 角色 | 狀態 | 完成時間 | Deliverable |
   |------|------|----------|-------------|
   | 01. Issue Analyst | ⏳ Pending | - | 01-requirements-analysis.md |
   | 02. Code Archaeologist | ⏳ Pending | - | 02-code-analysis.md |
   | 03. Solution Architect | ⏳ Pending | - | 03-architecture-design.md |
   | 04. Implementation Specialist | ⏳ Pending | - | 04-implementation-report.md |
   | 05. Test Engineer | ⏳ Pending | - | 05-test-report.md |
   | 06. Quality Assurance | ⏳ Pending | - | 06-quality-report.md |
   | 07. Documentation Specialist | ⏳ Pending | - | 07-documentation-report.md |

   ## 角色工作摘要

   ### 01. Issue Analyst
   **狀態**: ⏳ 等待開始
   **任務**：分析需求，理解問題背景

   ### 02. Code Archaeologist
   **狀態**: ⏳ 等待開始
   **任務**：檢視現有程式碼，分析可重用元件

   ### 03. Solution Architect
   **狀態**: ⏳ 等待開始
   **任務**：提出解決方案並推薦最佳選項

   ### 04. Implementation Specialist
   **狀態**: ⏳ 等待開始
   **任務**：實際撰寫程式碼

   ### 05. Test Engineer
   **狀態**: ⏳ 等待開始
   **任務**：撰寫並執行測試

   ### 06. Quality Assurance
   **狀態**: ⏳ 等待開始
   **任務**：驗證程式碼品質

   ### 07. Documentation Specialist
   **狀態**: ⏳ 等待開始
   **任務**：更新相關文件，產生 PR 描述

   ---

   ## 注意事項
   - 每個角色完成後會更新此文件
   - 所有 deliverable 都會儲存在此目錄下
   - 完成後會產生 pr.md 供建立 Pull Request 使用
   ```

3. **初始化進度追蹤**：
   使用 TodoWrite 建立以下任務清單：
   ```
   - 需求分析 (01-requirements-analysis.md)
   - 代碼探索 (02-code-analysis.md)
   - 架構設計 (03-architecture-design.md)
   - 功能實作 (04-implementation-report.md)
   - 測試撰寫 (05-test-report.md)
   - 品質檢查 (06-quality-report.md)
   - 文件撰寫 (07-documentation-report.md)
   ```

### 步驟 1：需求分析

使用 Task tool 調用 issue-analyst agent：
```
Task(
  subagent_type="dev-workflow:issue-analyst",
  prompt="任務描述：$ARGUMENTS\n任務目錄：{task_directory}\n\n請執行需求分析並產生 01-requirements-analysis.md"
)
```

等待完成後：
- 更新 handoff.md：
  - 標記 Issue Analyst 為 ✅ Completed
  - 記錄完成時間
  - 填入工作摘要
  - 設定 Status 為 ⏳ In Progress
  - 設定 Current Role 為 Code Archaeologist
  - 更新 Progress 為 1/7
- 更新 TodoWrite 標記需求分析為 completed
- 讀取並確認 01-requirements-analysis.md 已建立

### 步驟 2：代碼探索

使用 Task tool 調用 code-archaeologist agent：
```
Task(
  subagent_type="dev-workflow:code-archaeologist",
  prompt="任務目錄：{task_directory}\n需求文件：@{task_directory}/01-requirements-analysis.md\n\n請探索代碼庫並產生 02-code-analysis.md"
)
```

等待完成後：
- 更新 handoff.md：
  - 標記 Code Archaeologist 為 ✅ Completed
  - 記錄完成時間
  - 填入工作摘要
  - 設定 Current Role 為 Solution Architect
  - 更新 Progress 為 2/7
- 更新 TodoWrite 標記代碼探索為 completed
- 讀取並確認 02-code-analysis.md 已建立

### 步驟 3：架構設計（暫停點）

使用 Task tool 調用 solution-architect agent：
```
Task(
  subagent_type="dev-workflow:solution-architect",
  prompt="任務目錄：{task_directory}\n需求文件：@{task_directory}/01-requirements-analysis.md\n代碼分析：@{task_directory}/02-code-analysis.md\n\n請設計架構方案並產生 03-architecture-design.md"
)
```

**重要**：完成後暫停，使用 AskUserQuestion 確認：
- 向用戶展示推薦的架構方案摘要
- 詢問用戶是否同意繼續實作
- 如果用戶有修改意見，調整設計後再繼續

等待完成後：
- 更新 handoff.md：
  - 標記 Solution Architect 為 ✅ Completed
  - 記錄完成時間
  - 填入工作摘要
  - 設定 Current Role 為 Implementation Specialist
  - 更新 Progress 為 3/7
- 更新 TodoWrite 標記架構設計為 completed

### 步驟 4：功能實作

確認用戶同意後，使用 Task tool 調用 implementation-specialist agent：
```
Task(
  subagent_type="dev-workflow:implementation-specialist",
  prompt="任務目錄：{task_directory}\n架構設計：@{task_directory}/03-architecture-design.md\n\n請根據架構設計實作功能並產生 04-implementation-report.md"
)
```

等待完成後：
- 更新 handoff.md：
  - 標記 Implementation Specialist 為 ✅ Completed
  - 記錄完成時間
  - 填入工作摘要
  - 設定 Current Role 為 Test Engineer
  - 更新 Progress 為 4/7
- 更新 TodoWrite 標記功能實作為 completed
- 讀取並確認 04-implementation-report.md 已建立

### 步驟 5：測試撰寫

使用 Task tool 調用 test-engineer agent：
```
Task(
  subagent_type="dev-workflow:test-engineer",
  prompt="任務目錄：{task_directory}\n實作報告：@{task_directory}/04-implementation-report.md\n需求文件：@{task_directory}/01-requirements-analysis.md\n\n請撰寫測試並產生 05-test-report.md"
)
```

等待完成後：
- 更新 handoff.md：
  - 標記 Test Engineer 為 ✅ Completed
  - 記錄完成時間
  - 填入工作摘要
  - 設定 Current Role 為 Quality Assurance
  - 更新 Progress 為 5/7
- 更新 TodoWrite 標記測試撰寫為 completed
- 讀取並確認 05-test-report.md 已建立

### 步驟 6：品質檢查

使用 Task tool 調用 quality-assurance agent：
```
Task(
  subagent_type="dev-workflow:quality-assurance",
  model="opus",
  prompt="任務目錄：{task_directory}\n實作報告：@{task_directory}/04-implementation-report.md\n測試報告：@{task_directory}/05-test-report.md\n\n請執行品質檢查並產生 06-quality-report.md"
)
```

等待完成後：
- 更新 handoff.md：
  - 標記 Quality Assurance 為 ✅ Completed
  - 記錄完成時間
  - 填入工作摘要
  - 設定 Current Role 為 Documentation Specialist
  - 更新 Progress 為 6/7
- 更新 TodoWrite 標記品質檢查為 completed
- 讀取並確認 06-quality-report.md 已建立

### 步驟 7：文件撰寫

使用 Task tool 調用 documentation-specialist agent：
```
Task(
  subagent_type="dev-workflow:documentation-specialist",
  prompt="任務目錄：{task_directory}\n實作報告：@{task_directory}/04-implementation-report.md\n測試報告：@{task_directory}/05-test-report.md\n品質報告：@{task_directory}/06-quality-report.md\n\n請撰寫文件更新並產生 07-documentation-report.md 和 pr.md"
)
```

等待完成後：
- 更新 handoff.md：
  - 標記 Documentation Specialist 為 ✅ Completed
  - 記錄完成時間
  - 填入工作摘要
  - 設定 Status 為 🎉 All Roles Completed
  - 更新 Progress 為 7/7
- 更新 TodoWrite 標記文件撰寫為 completed
- 讀取並確認 07-documentation-report.md 和 pr.md 已建立

### 步驟 8：產生摘要

在任務目錄下建立 `summary.md`，包含：
- 任務概述
- 完成的功能
- 測試結果摘要
- 品質檢查結果
- PR 文件連結
- 下一步建議（如：建立 PR）

### 步驟 9：完成報告

向用戶報告：
- 所有階段完成狀態
- 產生的文件清單
- 如何查看詳細報告
- PR 文件位置
- 是否需要建立 PR

## 注意事項

1. **專案標準**：實作階段應檢查專案是否有 `CLAUDE.md` 或類似的代碼標準文件，並遵循專案規範。如專案有提供 coding standards skill，可調用該 skill。

2. **錯誤處理**：如果任何階段失敗：
   - 記錄錯誤原因
   - 詢問用戶是否重試或跳過
   - 更新 TodoWrite 和 handoff.md 反映實際狀態

3. **文件語言**：所有產出文件使用繁體中文

4. **進度透明**：每個階段開始和結束時都更新 TodoWrite 和 handoff.md

5. **handoff.md 更新**：每個步驟完成後必須更新 handoff.md，確保狀態同步

## 單步執行模式

如果任務描述以 `--step` 開頭，只執行指定的步驟：
- `--step analyze`：只執行需求分析
- `--step explore`：只執行代碼探索
- `--step design`：只執行架構設計
- `--step implement`：只執行功能實作
- `--step test`：只執行測試撰寫
- `--step qa`：只執行品質檢查
- `--step docs`：只執行文件撰寫

## 繼續執行模式

如果任務描述以 `--resume` 開頭，從指定的任務目錄繼續：
- 讀取任務目錄中的 handoff.md
- 根據 Current Role 確定下一個未完成的步驟
- 從下一個未完成的步驟繼續執行

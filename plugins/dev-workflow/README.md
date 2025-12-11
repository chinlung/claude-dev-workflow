# Dev Workflow Plugin

完整的開發工作流程系統，將 Kiro IDE 的 8 角色工作流程轉換為 Claude Code 可用的自動化流程。

## 概述

這個 plugin 提供了一套結構化的開發流程，包含 7 個專業化 Agent：

| Agent | 職責 | 產出物 |
|-------|------|--------|
| Issue Analyst | 需求分析、用戶故事、成功標準 | `01-requirements-analysis.md` |
| Code Archaeologist | 探索代碼庫、識別可重用元件 | `02-code-analysis.md` |
| Solution Architect | 架構設計、方案比較 | `03-architecture-design.md` |
| Implementation Specialist | 功能實作、程式碼撰寫 | `04-implementation-report.md` |
| Test Engineer | 測試規劃、撰寫測試 | `05-test-report.md` |
| Quality Assurance | Lint、型別檢查、品質審查 | `06-quality-report.md` |
| Documentation Specialist | 文件更新、PR 描述產生 | `07-documentation-report.md`, `pr.md` |

## 使用方式

### 完整流程

```
/dev-workflow 實作購物車清空功能
```

執行完整的 7 階段開發流程。

### 單步執行

```
/dev-workflow --step analyze 分析購物車需求
/dev-workflow --step explore 探索購物車相關代碼
/dev-workflow --step design 設計清空功能架構
/dev-workflow --step implement 實作清空功能
/dev-workflow --step test 撰寫清空功能測試
/dev-workflow --step qa 執行品質檢查
/dev-workflow --step docs 撰寫文件更新
```

### 繼續執行

```
/dev-workflow --resume docs/task-20241211-1430-cart-clear/
```

從指定的任務目錄繼續未完成的流程。系統會讀取 `handoff.md` 確定當前進度。

## 流程特點

### 任務交接文件 (handoff.md)

每個任務目錄包含 `handoff.md` 作為中央狀態管理：
- 追蹤每個角色的完成狀態
- 記錄各角色的工作摘要
- 管理工作流程狀態轉移
- 支援工作流程的暫停和恢復

### 暫停確認點

在架構設計完成後，系統會暫停並詢問用戶確認：
- 展示推薦的架構方案
- 等待用戶同意後再開始實作
- 允許用戶提出修改意見

### 進度追蹤

使用 TodoWrite 追蹤每個階段的進度：
```
✅ 需求分析
✅ 代碼探索
⏳ 架構設計
⬜ 功能實作
⬜ 測試撰寫
⬜ 品質檢查
⬜ 文件撰寫
```

### 文件產出

所有報告儲存在 `docs/task-{timestamp}-{name}/` 目錄：
```
docs/task-20241211-1430-cart-clear/
├── handoff.md                    # 任務交接文件（中央狀態管理）
├── 01-requirements-analysis.md
├── 02-code-analysis.md
├── 03-architecture-design.md
├── 04-implementation-report.md
├── 05-test-report.md
├── 06-quality-report.md
├── 07-documentation-report.md
├── pr.md                         # PR 描述（供建立 PR 使用）
└── summary.md
```

## 與 Kiro 的對應關係

| Kiro 角色 | Claude Code Agent |
|-----------|-------------------|
| 00 Task Initializer | 整合到主控命令（建立 handoff.md） |
| 01 Issue Analyst | issue-analyst |
| 02 Code Archaeologist | code-archaeologist |
| 03 Solution Architect | solution-architect |
| 04 Build Engineer | 整合到主控命令 |
| 05 Implementation Specialist | implementation-specialist |
| 06 Test Engineer | test-engineer |
| 07 Quality Assurance | quality-assurance |
| 08 Documentation Specialist | documentation-specialist |

## 目錄結構

```
plugins/dev-workflow/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   ├── issue-analyst.md
│   ├── code-archaeologist.md
│   ├── solution-architect.md
│   ├── implementation-specialist.md
│   ├── test-engineer.md
│   ├── quality-assurance.md
│   └── documentation-specialist.md
├── commands/
│   └── dev-workflow.md
└── README.md
```

## 通用化設計

所有 Agent 都設計為通用化，可以適應不同的技術棧：

- **語言無關**：支援 JavaScript/TypeScript、Python、Go、Rust、Java 等
- **框架無關**：不假設特定框架，會先探索專案結構
- **工具鏈適應**：自動識別 npm、yarn、pytest、go test 等測試/建構工具

每個 Agent 在執行前會：
1. 檢查專案的 `CLAUDE.md`、`CONTRIBUTING.md` 等標準文件
2. 探索現有代碼模式
3. 適配專案的技術棧和慣例

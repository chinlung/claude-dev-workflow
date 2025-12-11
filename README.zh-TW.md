# Claude 開發工作流程插件

[English](README.md) | [繁體中文](README.zh-TW.md)

一個為 Claude Code 打造的完整開發工作流程系統，自動化從需求分析到品質保證的整個開發過程。

靈感來自 [Kiro IDE](https://kiro.dev) 的 8 角色工作流程系統，由 [Pahud Hsieh](https://www.facebook.com/pahud.hsieh) 設計。觀看[教學影片](https://www.youtube.com/watch?v=RdrRHXbXZF8)了解更多原始概念。本插件將此工作流程適配於 Claude Code 架構。

## 功能特色

- **7 個專門代理人**依序協作
- **結構化文件輸出**涵蓋每個階段
- **handoff.md 機制**用於代理人間無縫上下文傳遞
- **暫停點**在架構設計後等待使用者確認
- **進度追蹤**使用 TodoWrite
- **彈性執行**：完整工作流程、單一步驟或從檢查點繼續
- **語言無關**：適用於任何程式語言

## 安裝方式

```bash
# 新增 marketplace
/plugin marketplace add chinlung/claude-dev-workflow

# 安裝插件
/plugin install dev-workflow@scl-claude-plugins
```

或直接安裝：

```bash
/plugin install chinlung/claude-dev-workflow
```

## 使用方式

### 完整工作流程

```bash
/dev-workflow 實作使用者驗證功能
```

這會依序執行全部 7 個階段：
1. **需求分析** → `01-requirements-analysis.md`
2. **程式碼探索** → `02-code-analysis.md`
3. **架構設計** → `03-architecture-design.md`（暫停等待確認）
4. **實作** → `04-implementation-report.md`
5. **測試** → `05-test-report.md`
6. **品質保證** → `06-quality-report.md`
7. **文件更新** → `07-documentation-report.md`

### 單一步驟執行

```bash
/dev-workflow --step analyze 分析購物車需求
/dev-workflow --step explore 探索驗證程式碼
/dev-workflow --step design 設計支付整合
/dev-workflow --step implement 實作功能
/dev-workflow --step test 撰寫功能測試
/dev-workflow --step qa 執行品質檢查
/dev-workflow --step docs 更新文件並產生 PR
```

### 從檢查點繼續

```bash
/dev-workflow --resume docs/task-20241211-1430-auth-feature/
```

## 代理人說明

| 代理人 | 角色 | 輸出 |
|-------|------|--------|
| 議題分析師 | 需求分析、使用者故事、成功標準 | `01-requirements-analysis.md` |
| 程式碼考古學家 | 程式碼庫探索、模式識別、可重用元件 | `02-code-analysis.md` |
| 解決方案架構師 | 架構設計、方案比較、實作計畫 | `03-architecture-design.md` |
| 實作專家 | 依循最佳實踐的程式碼實作 | `04-implementation-report.md` |
| 測試工程師 | 測試規劃、撰寫與執行 | `05-test-report.md` |
| 品質保證 | Lint、型別檢查、建置驗證、程式碼審查 | `06-quality-report.md` |
| 文件專家 | README、CHANGELOG、API 文件、PR 描述 | `07-documentation-report.md` |

## 輸出結構

所有報告都儲存在任務目錄中：

```
docs/task-{YYYYMMDD-HHMM}-{簡短名稱}/
├── 01-requirements-analysis.md
├── 02-code-analysis.md
├── 03-architecture-design.md
├── 04-implementation-report.md
├── 05-test-report.md
├── 06-quality-report.md
├── 07-documentation-report.md
├── handoff.md
└── summary.md
```

## 工作流程圖

```
┌─────────────────┐
│   議題分析師    │ → 需求與使用者故事
└────────┬────────┘
         ▼
┌─────────────────┐
│程式碼考古學家   │ → 程式碼庫分析
└────────┬────────┘
         ▼
┌─────────────────┐
│解決方案架構師   │ → 架構設計
└────────┬────────┘
         ▼
    ⏸️ 暫停（使用者確認）
         ▼
┌─────────────────┐
│   實作專家      │ → 可運作的程式碼
└────────┬────────┘
         ▼
┌─────────────────┐
│  測試工程師     │ → 測試套件
└────────┬────────┘
         ▼
┌─────────────────┐
│   品質保證      │ → 品質報告
└────────┬────────┘
         ▼
┌─────────────────┐
│   文件專家      │ → 文件與 PR 描述
└─────────────────┘
```

## 設定

此插件可直接在任何專案中使用。每個代理人都會適應您專案的結構和慣例。

如需專案特定的程式碼規範，建議在專案根目錄建立 `CLAUDE.md` 檔案，寫入您團隊的開發指南。

## 授權

MIT

## 貢獻

歡迎貢獻！請隨時提交 Pull Request。

## 致謝

- 靈感來自 [Kiro IDE](https://kiro.dev) 的 8 角色工作流程系統，由 [Pahud Hsieh](https://www.facebook.com/pahud.hsieh) 設計
- [教學影片](https://www.youtube.com/watch?v=RdrRHXbXZF8)說明原始工作流程概念
- 專為 [Claude Code](https://claude.ai/code) 打造

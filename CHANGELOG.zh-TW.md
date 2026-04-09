# 變更日誌

本專案所有重要變更都將記錄在此檔案中。

格式基於 [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)，
並遵循 [語意化版本](https://semver.org/spec/v2.0.0.html)。

## [1.5.1] - 2026-04-10

### 變更
- **openspec-superpowers-workflow 1.0.0 → 1.0.1**：強化自動觸發機制。重寫 `SKILL.md` frontmatter `description`，改用 imperative「MUST use」語氣、擴充 trigger 清單（現在也比對 `openspec` CLI 指令與 `openspec/changes/<name>/` 資料夾的存在），並明列四條禁止行為。在 `SKILL.md` 本體頂部新增「Activation reminder」段落，在 Claude 採取任何行動前錨定不可妥協的規則。這樣使用者就不需要在自己的 `~/.claude/CLAUDE.md` 維護獨立的「必須呼叫此 skill」提醒 — 同樣的 meta 指令現在隨 plugin 一併發佈。`phases.md` 不變。

### 修正
- **dev-workflow 1.0.1 → 1.0.2**：修正 `plugin.json` description 從「6 specialized agents」改為「7 specialized agents: ..., quality assurance, and documentation」。這個不一致是 2026-03-12 `35c0a9c` refactor commit 的遺漏 — 當時把版本號 revert 成對應 `CHANGELOG [1.0.1]`，卻也把 description 一併降回 1.0.0 時代的寫法，儘管 `documentation-specialist` agent 檔案從未被移除。僅 metadata 修正，無程式碼變更。

### 文件
- `README.md` / `README.zh-TW.md`：新增 `Session 經驗學習插件` 表格列、安裝指令、完整章節（自 1.4.0 起就應該要有但先前遺漏）
- `CHANGELOG.zh-TW.md`：翻譯英文版的 `[1.5.0]` 和 `[1.4.0]` entry（中文 changelog 先前停在 `[1.3.0]`）
- `marketplace.json`：將 `dev-workflow` entry 的版本從 `1.0.0` → `1.0.1` → `1.0.2` 對齊到 `plugins/dev-workflow/plugin.json`（先前版本對齊 refactor 的漂移修正）

### 備註
- Marketplace 版本從 1.5.0 → 1.5.1 反映 `HEAD` 相對於初始 1.5.0 commit 多了數個 plugin 內容變更。停留在 1.5.0 的使用者若不更新，會錯過較強的自動觸發機制和 dev-workflow description 修正。

## [1.5.0] - 2026-04-10

### 新增
- **OpenSpec + Superpowers 工作流程插件**：六階段功能開發工作流程，強制執行 OpenSpec（規格生命週期，WHAT）與 Superpowers（開發紀律，HOW）嚴格角色分離
  - 單一 skill，採用 progressive disclosure：`SKILL.md`（58 行，常駐載入）+ `phases.md`（290+ 行，需要時才載入）
  - **Phase 1 — 規格定義**（OpenSpec 主導）：proposal + specs 為使用者審核產物；design / tasks 為草稿佔位
  - **Phase 2 — 設計精煉**（Superpowers `brainstorming` → 原位覆寫 `design.md`）
  - **Phase 3 — 任務規劃**（Superpowers `writing-plans` → 原位覆寫 `tasks.md`）
  - **Phase 4 — 實作**（Superpowers `subagent-driven-development` + 強制 TDD）
  - **Phase 5 — 審查與回饋**：`[REQUIREMENT|DESIGN|CODE|CONSTITUTION]` tag 分類 + Y/N 標記，記錄到 `review-notes.md`；審查期間絕不修改 spec 檔
  - **Phase 6 — 調和與歸檔**（OpenSpec）：Clean rewrite 紀律（非增量 patch）、`tasks.md` 凍結為執行歷史、`[CONSTITUTION]` 項目改寫入 `openspec/config.yaml` 而非 feature spec
  - 前置需求段落記錄 OpenSpec CLI vs `/opsx:*` slash command 的替代選項，以及 `openspec init .`（無 `--here` flag）的 gotcha
  - Validator 嚴格性 gotcha：每個 `### Requirement:` 區塊必須在第一段出現 `SHALL` / `MUST`
  - Archive 資料夾日期前綴行為：`openspec/changes/archive/<YYYY-MM-DD>-<name>/`
  - 決策速查表（13 種情境）和 8 條反模式清單
- 更新 marketplace 版本至 1.5.0

## [1.4.0] - 2026-03-12

### 新增
- **Session 經驗學習插件**：漸進式保存對話中的有價值模式為 memory 或 skill
  - `/save-session` 命令：分析對話並保存有價值的模式為 memory 或 skill
    - 5 Phase 分析流程：掃描 → 層級判斷 → 去重合併 → 執行 → 報告
    - 自動區分全域 vs 專案層級保存位置
    - 更新優先於新建，避免記憶膨脹
    - 每次最多 1-2 項變更，精簡克制
  - Stop hook：在實質工作階段結束時輕量提醒執行 `/save-session`
    - Command 類型（非 prompt），不觸發額外 LLM 呼叫
    - Flag file 機制防止同一 session 重複提醒
    - 自動跳過短工作階段（< 10 行 transcript）
- 更新 marketplace 版本至 1.4.0

## [1.3.0] - 2026-03-06

### 新增
- **高精確度開發插件**：針對安全關鍵程式碼的多 Agent 開發模式
  - `/high-precision-dev:init` 指令用於建立 SPEC.md 和 CONSENSUS.md 模板
  - `/high-precision-dev:start` 指令用於執行 4 Phase 驗證工作流程
  - 5 個專門代理人：
    - 實作者 A/B：在隔離 worktree 中獨立進行防禦性實作
    - 批評者：使用 severity 1-5 分級系統性找出問題
    - 攻擊者：三輪紅隊攻擊（邊界、語意、假設）
    - 驗證者：最終整合，100% SPEC.md 需求覆蓋驗證
  - 透過認識論分工將錯誤率從 p 壓縮至 p^4
  - Phase 3 修復循環上限（最多 3 次），含 adversary 重新攻擊
  - 驗證者步驟零：整合前檢查 CRITIQUE.md/ATTACKS.md
  - 三級強度光譜文件（單一 Agent → /debate → /start）
- 更新 marketplace 版本至 1.1.0
- 更新 README 加入高精確度開發插件文件（中英文）

## [1.2.0] - 2025-12-19

### 新增
- **多代理辯證系統插件**：用於多角度決策的辯證系統
  - `/debate` 指令用於啟動辯論
  - 5 個專門代理人：
    - 協調者 (Orchestrator)：分析需求並配置角度
    - 角度 A/B/C (Perspective A/B/C)：從不同角度提出解決方案
    - 批判者 (Critic)：審查方案並提供量化評分
  - 根據需求類型智能配置角度
  - 量化評分系統（30分制）
  - 共識驅動決策（需≥2個代理人同意）
  - 透過多輪辯論迭代優化
  - 在關鍵決策點納入使用者參與
- 更新 README 以記錄插件集合中的兩個插件
- 新增多代理辯證系統的繁體中文文件

## [1.1.0] - 2025-12-11

### 新增
- **文件專家**代理人（步驟 7）：負責文件更新、CHANGELOG 維護和 PR 描述生成
- **handoff.md 機制**：中央狀態管理文件，用於代理人之間的無縫上下文傳遞
- 語言無關設計：適用於任何程式語言
- 繁體中文文件（README.zh-TW.md、CHANGELOG.zh-TW.md）

### 變更
- 泛化所有代理人，使其與語言/框架無關
- 改進實作專家的程式碼模式識別能力
- 強化品質保證的檢查項目
- 更新解決方案架構師的技術考量範圍
- 優化測試工程師對多語言測試框架的支援

### 修復
- package.json 中 repository 欄位格式（應為字串而非物件）
- 修正 GitHub 儲存庫 URL

### 文件
- 新增 Pahud Hsieh 的教學影片連結
- 新增貢獻者名單
- 重新編號開發流程文件以維持序列一致性

## [1.0.0] - 2024-12-11

### 新增
- dev-workflow 插件首次發布
- 6 個專門代理人：
  - 議題分析師：需求分析與使用者故事
  - 程式碼考古學家：程式碼庫探索與模式識別
  - 解決方案架構師：架構設計與方案比較
  - 實作專家：依循最佳實踐的程式碼實作
  - 測試工程師：測試規劃與執行
  - 品質保證：程式碼品質驗證與建置驗證
- 主要指令 `/dev-workflow` 支援：
  - 完整工作流程執行
  - 單一步驟執行（`--step`）
  - 從檢查點繼續（`--resume`）
- 使用 TodoWrite 進行進度追蹤
- 架構設計後的暫停點，等待使用者確認
- 完整的文件輸出至 `docs/task-{timestamp}/` 目錄

# session-reflect Plugin 設計文件

日期:2026-08-03
狀態:設計已核准,待實作

## 目的

Session 收尾時自動回顧本次完成的任務與近期交談,判斷是否有值得提出的改進建議(範圍外 bug、既有問題、延伸優化、知識缺口),有則以互動方式讓使用者勾選執行,無則明確回報「無需回顧」。routine 或無實質內容的 session 以廉價機制跳過。

參考前例:`plugins/session-learning` 的 save-session Stop hook(bash 廉價閘門 + block reason 提醒模式)。

## 已確認的設計決策

| 決策點 | 結論 |
|---|---|
| 觸發頻率 | 一 session 一次(flag file 防重複,比照 save-session) |
| 判斷引擎 | bash 機械閘門 + 主 Claude 兩段 triage(不用 prompt-based hook 小模型冷讀) |
| 建議處置 | 選中即在本 session 執行;未選寫入 backlog 檔 |
| 與 save-session 共存 | 獨立共存,各自防重複,不互相依賴 |

## 架構

```
plugins/session-reflect/
├── .claude-plugin/plugin.json     # version 1.0.0
├── hooks/
│   ├── hooks.json                 # Stop event → gate script(command type,timeout 10)
│   └── reflect-gate.sh            # bash 機械閘門
├── skills/reflect/SKILL.md        # 分析 playbook(核心智慧)
├── commands/reflect.md            # 薄 command:手動觸發同一 skill
└── tests/gate.test.sh             # gate script fixture 測試
```

方案取捨:曾考慮 (B) 完整指令內嵌 block reason——reason 字串會膨脹至數百字、escaping 地雷多,棄;(C) prompt-based hook 小模型 triage——冷讀 transcript 品質差、難 debug、漏判不可見,棄。採 hook + skill + 薄 command:progressive disclosure,不觸發時 zero context 成本。

## 觸發流程(reflect-gate.sh)

```
Stop 事件
  └─ reflect-gate.sh(bash,<1 秒)
       ├─ jq 不可用 / stop_hook_active=true → approve(防迴圈,硬性第一關)
       ├─ flag file 已存在 → approve(一 session 一次)
       ├─ transcript 不存在或 < 10 行 → approve(無實質內容,門檻比照 save-session)
       ├─ transcript 中已出現 reflect 執行紀錄 → approve
       ├─ 互動中偵測:最後一則 assistant 訊息含 AskUserQuestion /
       │   ExitPlanMode tool_use,或文字以「?」/「?」結尾
       │   → approve 且「不標記 flag」(讓路但保留下次觸發權)
       └─ 全部通過 → 標記 flag → block,reason 為一句短指令:
           「session 收尾回顧:請呼叫 session-reflect:reflect skill,
            先快速 triage,routine 直接回報無需執行。」
```

要點:

- `stop_hook_active` 是官方防迴圈欄位(Claude 因上一個 Stop hook block 而繼續時為 true),置於最前。
- 「互動中偵測」刻意不標記 flag:只有真正發出 block(開始分析)才消耗一 session 唯一一次的機會。
- 「不在互動中但任務做到一半」由 skill 的 triage 兜底——主 Claude 持有完整 context,判斷比 bash 猜測準。
- flag file:`${TMPDIR:-/tmp}/claude-session-reflect-<session_id>`。

## 分析 playbook(skills/reflect/SKILL.md)

### Stage 1:快速 triage(必經,目標 < 3 句話內判斷)

任一命中即輸出一句「本次 session 無需回顧:<理由>」並結束(不進 Stage 2、不發問卷):

1. **routine 工作**——純 git 操作、跑既有指令、格式化、依賴安裝、單純問答,無新程式碼或決策產出
2. **無實質產出**——只有討論沒有落地,或工作中途被放棄
3. **任務未完結**——尚有 in-progress 任務,或使用者上一句是新指示而非收尾語氣
4. **已回顧過**——本 session 稍早已跑過 /reflect 且之後無新工作

### Stage 2:深度回顧(產出最多 5 個建議)

四個固定視角掃描 session:

| 視角 | 找什麼 |
|---|---|
| 範圍外發現 | 任務過程中看到但刻意沒碰的 bug、壞味道、過期註解 |
| 既有問題 | 非本次引入、但被這次工作暴露的結構性問題(缺測試、缺 CI 閘門、脆弱耦合) |
| 延伸優化 | 與本次任務直接相關、再走一步就有價值的改進(效能、可讀性、防呆) |
| 知識缺口 | 值得進一步瞭解的主題(新工具、未查證的 API 行為、可寫成 ref 的踩坑) |

產出規則:

- **證據錨點強制**:每個建議必附 `file:line` 或對話中具體事實,說不出錨點直接丟棄(移植 code review 紀律:empty cross-references 駁回)
- 依「價值 × 執行成本」排序,超過 5 個只取前 5,其餘直接寫入 backlog
- 先讀 backlog 去重:已存在(pending / rejected)的項目不重複提出

### 互動與執行

一次 `AskUserQuestion`(multiSelect: true)列出建議,每項附一行證據與預估規模。

- 選中 → 依序在本 session 執行(遵守既有開發紀律),完成後更新 backlog 狀態為 done
- 未選 → 寫入 backlog(pending)
- 使用者以 Other 表達「都不要」或給新指示 → 全部入 backlog(pending),或依新指示行動
- backlog 有既存 pending 項時,問卷前附一句「backlog 尚有 N 項 pending,可用 /reflect 回顧」(提示但不佔 5 個名額)

## Backlog(.claude/reflect-backlog.md)

- **位置**:專案根 `.claude/reflect-backlog.md`,project-scoped;是否版控由使用者 per-repo 決定,plugin 永不自行 commit 它
- **狀態機**:`pending → done | rejected`
  - `done`:執行完成後整個區塊刪除(歷史交給 git)
  - `rejected`:保留,作為未來 session 去重依據(防疲勞關鍵)
  - `pending`:去重時跳過,不重提
- 檔案不存在時由 skill 首次寫入建立

格式範例:

```markdown
## [pending] 補上 parser 邊界測試
- 來源:2026-08-03 session(修復 CSV 匯入時發現)
- 證據:src/parser.ts:142 對空欄位無測試覆蓋
- 分類:既有問題|預估:小(<30 行)
```

## 錯誤處理(全面 fail-open)

Stop hook 壞掉的最壞後果是使用者無法結束 session,每條失敗路徑都放行:

| 失敗點 | 行為 |
|---|---|
| jq 不可用 / transcript 解析失敗 | approve |
| gate script 非預期錯誤 | hooks.json `timeout: 10` 兜底 + script 內 trap 回 approve |
| skill 執行中 backlog 寫入失敗 | 回報原因,建議內容直接印在對話中,不中斷 |
| 分析完成後的下一次 Stop | flag file 已標記 → approve;stop_hook_active 為雙保險 |

方向說明:與 CI 閘門的 fail-closed 相反是刻意的——CI 擋「壞碼進 main」(漏放代價高),Stop hook 擋「session 結束」(誤擋代價高)。

## 驗證

- `tests/gate.test.sh`:餵入各情境模擬 hook JSON(空 transcript、短 transcript、問句結尾、flag 已存在、stop_hook_active=true),斷言 approve/block 輸出——讀環境事實、有消費者(提交前手跑/CI)的真閘門
- skill 為 prompt 內容不可 unit-test,品質靠 playbook 內機械規則(證據錨點、≤5 上限)約束

## 發布

- `plugin.json` version `1.0.0`
- `marketplace.json` 新增條目;metadata.version `1.9.1 → 1.10.0`(新增 plugin = minor)
- 同步 `CHANGELOG.md` / `CHANGELOG.zh-TW.md`;README 若有 plugin 清單一併更新
- 版本變更時檢查所有含版本字串的檔案

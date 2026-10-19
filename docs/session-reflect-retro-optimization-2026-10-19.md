# session-reflect 優化提案：吸收 retro skill 的精髓

日期：2026-10-19
狀態：提案，待使用者核准後實作
參考對象：`~/desktop/test/.claude/skills/retro/SKILL.md`（user-invoked 的 session 回顧 skill）
被優化對象：`plugins/session-reflect`（1.0.2）

## 1. retro 的精髓（值得吸收的五點）

### 1.1 改的是「環境」，不是「工作產物」

retro 開宗明義：「You are suggesting improvements to the coding agent's **environment** to improve future runs.」它問的是「下一個 agent 怎樣才不會再卡在同一處」，產出落在導覽指標、自動檢查、reviewer 規則、steering 檔瘦身、工具效率、資訊取得。

session-reflect 的四視角（範圍外發現／既有問題／延伸優化／知識缺口）全部指向**工作產物**——「下一件該做的事」。兩者正交：reflect 產生 backlog，retro 改進產生 backlog 的那台機器。這是 reflect 目前最大的盲區：同一種摩擦每個 session 都重演，reflect 卻從不提「把它做成機制」。

### 1.2 從「摩擦症狀」反推，每個類別都有 `Use when` 觸發條件

retro 每一類都附一句 _Use when_：「session 花很久才找到資訊」→ 導覽；「agent 犯了機器抓得到的錯」→ 自動檢查；「reviewer 漏抓」→ 規則；「昂貴的工具呼叫」→ 工具經濟。這是**症狀 → 類別 → 處方**的診斷對照表，類別只在症狀出現時才啟用。

reflect 的四視角沒有啟用條件，每次全掃一遍——等於邀請模型為每個視角湊出候選，再靠 Stage 2.5 濾掉。retro 的做法是**在源頭預防**而非**事後過濾**：沒症狀的類別根本不發想。

### 1.3 「處方放哪一層」有明確階梯，且依 context 壓力決定

retro 的 Reference 段是整份 skill 最有價值的部分：

- 實作 agent context 壓力最大，reviewer 最小 → 標準應在 review 時施加，不壓在實作時
- `CLAUDE.md`/`AGENTS.md` 常駐每個 context，「incredibly sparingly」，原則上只放導覽指標
- 違規先分類：**機械性**（固定語法樣式、禁用 API、import 形狀、檔案位置）→ 確定性檢查，「full stop」；只有**判斷題**才寫成文字規則
- 「Default to building the check over writing the rule.」

這與你 `~/.claude/CLAUDE.md` 的 Knowledge Architecture（機制層 > 參考層 > 決策層）是同一套哲學，但 reflect 完全沒用上：它的建議只有「現在做／入 backlog」兩種處置，從不問「這條該變成 hook、按需 rule、ref，還是常駐一行」。結果是 reflect 若提知識類建議，最自然的落點會是「加一行到 CLAUDE.md」——正好是兩邊都想避免的方向。

### 1.4 先找既有的，「既有但沒接線／靜默壞掉」本身就是 finding

「Read the repo's own check command first… so a check that already exists but sits unwired or silently broken is the finding, not a reinvention.」以及「沒有任何 guardrail 的 repo 本身就是 finding」。

reflect 有「已有防護」濾鏡，但只拿來**丟棄**候選；retro 把它反過來當**發現來源**——既有檢查沒被 CI 跑、條件 skip、hook 沒接上，正是你 CLAUDE.md「條件 skip 的測試 = CI 覆蓋假象」那條的通則化。

### 1.5 允許「減法」建議

retro 有兩個減法類別：**No-ops**（steering 檔中不改變 agent 行為的指令）與 **Global AGENTS.md**（該搬去 standards 或 checks 的 steering）。reflect 的四視角全是加法，長期只會讓環境變胖。

## 2. retro 的弱點（reflect 已做得更好，不引入）

| retro 的做法 | 為何不引入 |
|---|---|
| `disable-model-invocation: true`，純手動 | reflect 的價值正在 Stop hook 自動觸發；環境類 finding 也最常在「收尾時才回頭看」時浮現 |
| 無證據錨點要求、無驗證層 | reflect 的錨點強制 + inline 四濾鏡 + 對抗式 verifier 遠較嚴謹，保留 |
| 無數量上限、「依嚴重度呈現」全部候選 | reflect 的 ≤5 + backlog 分流較尊重使用者注意力 |
| 無 triage、無去重持久化 | reflect 的 Stage 1 與 `[rejected]` 永久去重是防疲勞關鍵 |
| 依賴 `writing-for-agents` skill、`CODING_STANDARDS.md` | 你的環境沒有這兩者；對應層是 `/review-branch` 規則包、`~/.claude/rules/*.md`（`paths:` 按需載入）、`~/.claude/claude-security-guidance.md` |

結論：**保留 reflect 的骨架（閘門、triage、驗證、問卷、backlog），只移植 retro 的「環境視角」與「落點階梯」兩個大腦。**

## 3. 差距對照

| 維度 | reflect 1.0.2 | retro | 提案 |
|---|---|---|---|
| 改進對象 | 工作產物 | 環境 | 兩者皆有，新增第五視角 |
| 類別啟用 | 每次全掃 | 症狀觸發（Use when） | 每個視角加啟用條件 |
| 處方落點 | 未定義 | 機械→檢查；判斷→review 時；常駐檔只放指標 | 新增落點濾鏡 |
| 既有機制 | 只當丟棄理由 | 沒接線/壞掉 = finding | 既有優先探查 |
| 減法 | 無 | No-ops、搬家 | 有 session 證據時允許 |
| 證據來源 | 主迴圈記憶（可能已 compact） | 讀 session log 原始資料 | 摩擦事件由 transcript 機械抽取（第二階段） |

## 4. 建議修改（依優先序）

### P1：新增第五視角「環境摩擦」（SKILL.md Stage 2）

| 症狀（啟用條件） | 找什麼 | 典型處方 |
|---|---|---|
| 為找一個檔案/事實繞了多輪搜尋 | 隱藏的跨檔相依、缺導覽 | 按需 ref 或 rule 加指標；常駐檔只在每個 session 都需要時才加 |
| 犯了一個機器能抓的錯（型別、lint、格式、路徑） | 缺檢查，或檢查存在但沒接線/靜默 skip | hook／CI step／lint 規則 |
| review（含自審）漏抓、之後才被發現 | review 規則缺口 | review 規則包或按需 rule；機械性者改做成檢查 |
| 某條 steering 指令在場卻沒被遵守 | 文字規則無效（no-op） | 降為機制，或刪除 |
| 昂貴/重複的工具呼叫、撐爆輸出 | 工具經濟問題 | 更窄的查詢方式、腳本化、改用 codegraph 等索引 |
| 關鍵資訊拿不到（log、外部服務狀態） | 資訊取得缺口 | tee log、唯讀存取、MCP |
| sandbox／權限拒絕反覆發生 | 環境設定摩擦 | 設定調整建議（交使用者決定，不自行放寬） |

錨點規則沿用：證據是**對話中的具體摩擦事件**（第幾次嘗試、哪個錯誤訊息）加上**處方目標的 `file:line`**（要改的 hook、CI workflow、rule 檔）。backlog 分類新增「環境摩擦」。

### P2：Stage 2.5 新增第五濾鏡「落點正確」＋ 既有優先探查

1. **既有優先**：提「新增檢查」前先讀 repo 自己的檢查入口（`package.json` scripts、CI workflow、`.claude/settings.json` hooks、`tests/*.test.sh`）。已有但沒接線、條件 skip、或靜默失敗 → 建議改為「把既有的接上／修好」。
2. **落點階梯**（由上而下取第一個成立的）：
   - 違規是機械性的 → 確定性檢查，full stop；且須同時通過你的閘門判準：讀環境事實（exit code／fs／git），而且有下游消費者（擋 merge、loop 退出、人類裁決）
   - 判斷題、只在碰某類檔案時需要 → 按需載入層（`rules/` 配 `paths:`、refs、skill body、review 規則包）
   - 每個 session 都需要且無法機器化 → 常駐決策層，且優先寫成指向參考層的一行指標
   - 以「加一行到 CLAUDE.md」處理機械性問題的候選 → 改寫落點或丟棄
3. **邊界**：處方本質是「記住某個模式」→ 屬 session-learning（save-session）的職責，reflect 不提。reflect 的環境視角只提**機制與結構搬移**。這維持你 CLAUDE.md 中兩者「刻意獨立」的分工，而且讓分工更清楚：save-session 存文字記憶，reflect 改機制。

### P3：每個視角加啟用條件；triage 調整

- 為原四視角各補一句「只在…時發想」，例如「延伸優化：只在本次改動的程式碼有可觀察的次佳之處時」；沒觸發的視角跳過，不湊數。
- Stage 1 triage 的「routine 工作」條件加但書：**routine 但出現摩擦事件（同一操作失敗 ≥2 次、被權限／hook 擋、使用者糾正）時不跳過**，直接只跑環境視角。目前一個 git 操作連撞三次 sandbox 的 session 會被判 routine 而丟掉最值得回顧的訊號。
- 減法建議（P1 表中的 no-op 列）只在**本 session 有證據**時提出；不在 reflect 裡做 steering 檔全面盤點——那是 `/claude-md-management:claude-md-improver` 的工作。

### P4（第二階段，可選）：摩擦事件從 transcript 機械抽取

長 session 在 Stop 時多半已 compact，主迴圈記得的是摘要，「第三次嘗試才成功」這類摩擦細節最先丟失。retro 讀 session log 原始資料正是為此。

做法：`reflect-gate.sh` 在 block 時把 `transcript_path` 帶進 reason；skill 在 context 曾被 compact 時以 `jq` 從 transcript 抽取 `is_error: true` 的 tool_result、權限拒絕、hook 擋下、使用者中斷等事件作為 P1 的證據來源。

這符合「讀環境事實而非 agent 自寫斷言」，但會動到 gate script 與 `tests/gate.test.sh`，且 transcript 欄位形狀需實測確認，建議與 P1–P3 分開發版。

## 5. 不建議做的

- **不把四視角整個換成 retro 的七類**：retro 的類別適合 user-invoked 的深度回顧；自動觸發的 reflect 若全面改成環境導向，會失去「範圍外 bug」這類工作產物建議。新增而非取代。
- **不在 reflect 內稽核全域 CLAUDE.md**：體積類問題已有 `claude-md-lint.sh` 與 claude-md-improver 負責。
- **不把 reflect 改成手動觸發**。
- **暫不接 Jev（`jev_decide`）**。逐一對照判斷點：gate 必須 <1 秒、fail-open，且不能把 transcript 送出本機；Stage 1 triage 是單一判斷，事實在主迴圈 context 裡，沒有寫下來；候選排序屬「優先序題」，jev skill 實測過「最該先修」會選中誤報；落點分類屬流程內的分類，主幹應由流程自己的事實查表決定。Jev 的價值是「省派發數，不省驗證」，用來決定每條派 1 個還是 3 個驗證者；reflect 只派**一個**批次 verifier，沒有派發可省，且候選常少於 5 條、state 需手寫，正好落在 jev skill「手寫 state 的批次少於 5 條不問」的範圍。**重新評估的條件**：P4 讓候選帶有機械事實、不必手寫 state，候選常超過 5 條，且驗證改為逐條分級派發。屆時每條一題 `noul`、只用來排序；由於 session-reflect 是公開發佈的 plugin，接法只能是選配（工具不存在時照舊）。

## 6. 實作範圍（P1–P3）

- `plugins/session-reflect/skills/reflect/SKILL.md`：Stage 1 但書、Stage 2 第五視角與啟用條件、Stage 2.5 第五濾鏡與既有優先、backlog 分類值
- `plugins/session-reflect/README.md`：How it works 與 Relation to session-learning 段同步
- 版號：`1.0.2 → 1.1.0`（新增行為 = minor）；`plugin.json`、marketplace.json、plugin `CHANGELOG.md`、根 `CHANGELOG.md`／`CHANGELOG.zh-TW.md` 同步
- `~/.claude/CLAUDE.md` 的 session-reflect 描述（「triage → 四視角 → …」）需改為五視角——屬決策層，依 `claude-md-authoring.md` 流程另行處理
- gate：只修互動中偵測的漏判（實作時追加）。2026-10-19 本 session 的實例是收尾問句後還接了五行，gate 只看最後一個字而漏判，回顧在等使用者回答時觸發。改為看結尾 400 字；半形 `?` 須後接空白、結尾或收尾符號。`tests/gate.test.sh` 新增 5 條斷言，每條都以 1.0.2 舊版 gate 或定點突變確認會轉紅。P4 的 transcript 抽取仍未做

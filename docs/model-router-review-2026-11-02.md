# model-router 五級分類 review（2026-11-02）

範圍：`~/.claude/skills/model-router/hooks/register.ts`（claude-config）的 nimble 分類與路由。資料：2026-10-15（cache-aware ratchet 上線）以來 182 個 session 的主迴圈 transcript、1,055 個回合；另從中抽 80 段文字原樣重播給本機 `nimble:latest`。router 每輪的決定只顯示在狀態列、不寫進 transcript，所以「哪一輪被路由」是從實際送出的模型（`message.model`）推回來的。

**狀態（同日更新）**：§2 的 #1～#5 已實作於 claude-config `0b5d4f2`（model-router 0.3.0），#6 依使用者裁定不改；實作與建議的差異、實作中發現的事、仍待驗證的項目見 §4。§1～§3 是審查當時的記錄，保持原樣。

## 1. 發現

### 1.1 四成回合不是人打的字，但照樣被分類

| 回合來源 | 回合數 | 造成模型切換 |
|---|---|---|
| 人打的提示 | 532 | 61 |
| 子代理 hand-back（"Another Claude session sent a message"） | 183 | 21 |
| Stop hook 回饋 | 131 | 0 |
| 展開的 slash 指令 | 84 | 3 |
| plugin 訊息（codex-review-pane 等） | 62 | 0 |
| task notification | 57 | 11 |

`turn.start` 對每個引擎回合都觸發，非人類回合的文字（子代理的報告、hook 的提醒）一樣送給 nimble。hand-back 是長篇技術報告，容易被判成 complex：**cache 還熱（<5 分鐘）時的 34 次升級中，15 次由 hand-back 觸發、5 次由 task notification 觸發**。這類回合的工作是「讀報告、接著做」，難度跟上一輪一樣，不該因為報告文字而換模型。

### 1.2 模型切換的成本

第一個請求的 cache 寫入量（tokens，平均）：

| 情況 | 回合數 | 寫入 >50% 的比例 | 平均 cache 寫入 | 平均請求大小 |
|---|---|---|---|---|
| 同模型、<5 分鐘 | 729 | 2% | 10,876 | 457,497 |
| 同模型、5–60 分鐘 | 57 | 49% | 205,069 | 438,941 |
| **換模型、<5 分鐘** | 40 | 88% | **315,973** | 382,637 |
| **換模型、5–60 分鐘** | 50 | 92% | **422,279** | 464,218 |

一次切換幾乎就是整段 context 重寫一遍（約 32–42 萬 token）。router 自己的觀測（`plugins/store/model-router_skills-dir-*.json`）也一致：model 變更的回合 97 次中 88 次是 heavy。另有 11 次「切過去、下一輪又切回來」。

### 1.3 cache TTL：大致是 5 分鐘，5–10 分鐘偏保守

同模型、只看空檔長短時 cache 還熱的比例：5–10 分鐘 64%（23/36）、10–20 分鐘 33%（4/12）、20 分鐘以上幾乎全冷。router 的 `cacheTtlMs` 預設 5 分鐘：5–10 分鐘這段有六成其實還熱，這時允許降級會白白重寫一次。原本猜測帳號是 1 小時 TTL，數據不支持。

### 1.4 nimble 分類本身

- 延遲：p50 294ms、p90 832ms、最大 1,088ms，80 次都沒超過 4 秒 timeout、0 錯誤。
- 信心度普遍偏低（多在 0.15–0.4）；低於 `minConfidence` 0.15 而被加一級的約一成。
- **risk 題判定偏寬**：人類提示 40 段中 14 段被判 risky（強制墊到 opus）。多數合理（支付、匯款、憑證、安全審查），但「`commit 這次修改`」也被判 risky（0.62）——risk 題裡的「irreversible actions」把 commit 這類可回復的動作也算進去。
- **短回覆不可靠**：「1」「同意」「照建議修改」「分析完就直接產出最終版」這類延續上一輪的回覆，難度取決於上一輪在做什麼，nimble 只看得到上一輪文字的前 500 字（常常是一份 hand-back）。結果分散：「1」因信心度 0.08 被加到 opus，「照建議修改」得 0.84 → sonnet。目前靠 ratchet 在 cache 熱時擋住降級，cache 冷了就照判。

### 1.5 effort 被改寫（已用 transcript 驗證）

tiers 的 effort 是 sonnet `high`、opus `high`、fable `xhigh`，被路由的回合送出 tier 的 effort，不看使用者的 `/effort`。

驗證：本 session 主迴圈每則回覆的紀錄有 `effort`／`perTurnEffort`（送出的值）。11-01 fable 84 則全是 `xhigh`；opus 283 則（11-01 88、11-02 195）與 11-02 sonnet 42 則**全是 `high`**，沒有任何 `xhigh` 或 `medium`。全域 `effortLevel` 是 `xhigh`，無路由的 opus 請求本應是 `xhigh`；11-02 10:23 把 sonnet 的 effort 設成 `medium` 之後，sonnet 的後續回覆仍記錄 `high`。router 程式碼裡唯一會產生 `medium` 的是 haiku session 的 `sessionPick` 上限，與本情況無關。

注意：Bash 的環境變數 `CLAUDE_EFFORT` 反映引擎自己解析出的設定值（本 session 讀到 `medium`），不是送出的值；稽核送出值要讀 transcript 的 `effort` 欄位。

結果：只要 router 運作，`/effort` 對被路由的回合沒有作用，要改實際 effort 得改 `tiers`（例如 moderate／complex 兩級改 `claude-opus-5-5:xhigh`）；`/effort` 只在 router 暫停、故障轉移或棘輪沿用上一輪時生效。

### 1.6 分類決定無法稽核

送出的模型與 effort 有記錄（transcript 的 `requestedModel`、`effort`），但 router 的每輪**決定**（分數、信心度、risk、ratchet 擋了沒）只出現在狀態列，沒有落檔。所以能算「送出了什麼」，算不出「nimble 判錯了幾次」。

## 2. 建議（依效益排序）

| # | 建議 | 依據 | 改動 |
|---|---|---|---|
| 1 | **非人類回合不分類，沿用上一輪實際送出的模型與 effort** | §1.1：20 次熱 cache 升級、9 次降級由它們觸發 | `turn.start` 依文字開頭辨識 hand-back／Stop hook／task notification／plugin 訊息；可行的話優先用事件欄位 |
| 2 | **短的延續回覆（例如 ≤ 12 字、無新任務內容）沿用上一輪** | §1.4：短回覆分數分散、依賴上一輪 | 同上，一個長度＋樣式判斷 |
| 3 | **每輪決定寫進本機 jsonl** | §1.6：下次 review 能直接算誤判率 | 寫 `~/.claude/` 下 gitignored 的檔：turnId、來源、分數、信心度、risk、tier、送出的 pair、是否被 ratchet 擋 |
| 4 | risk 題把「irreversible actions」收窄成破壞性操作（刪資料、force push、正式環境部署） | §1.4：`commit` 被判 risky | 改 `buildRequest` 的 risk instructions；需重播驗證 |
| 5 | `cacheTtlMs` 5 → 10 分鐘 | §1.3：5–10 分鐘 64% 還熱 | 設定值；代價是 10 分鐘內少一次降級機會 |
| 6 | 要不要讓路由保留你的 `xhigh` | §1.5 | 使用者決定：改 tiers 為 `opus:xhigh` 等，或接受 `high` |

不建議改的：換掉 nimble（延遲與穩定度都夠）、調 `minConfidence`（影響約一成，且方向是往上補，符合「資源不足比過度更貴」）。

## 3. 驗證方法（若實作）

- 單元測試：`register.test.ts` 補非人類回合、短回覆、決定落檔三組，每組至少兩個觸發輸入，並做突變（拿掉辨識、拿掉沿用）。
- 重播：用本報告的 80 段樣本重跑，確認 risk 題收窄後支付／憑證類仍判 risky、`commit` 不再判 risky。
- 上線後一週：用 #3 的決定檔與 transcript 對照，比較熱 cache 升級次數與 flip-flop 次數。

工具：分析腳本 `router-hist.mjs`、`router-replay.mjs` 在 session scratchpad（未入版控）。

## 4. 落地結果（2026-11-02）

實作在 claude-config `0b5d4f2`（main，CI 綠），mod 版本 0.2.0 → 0.3.0。使用者裁定 #1～#5 做、#6 不改。設計與證據的完整版在 claude-config 的 `refs/subagent-model-tiers.md` §7.1，本節只記與建議的差異。

| # | 結果 | 與 §2 建議的差異 |
|---|---|---|
| 1 | 已做 | `turn.start` 沒有「來源」欄位，辨識靠文字開頭（8 種前綴）。除了建議的沿用，另加四個**不沿用**的邊界：沒有上一輪 pair、session 模型換過、使用者打了審查指令（floor 贏）、cache 已冷（距上次請求 ≥ TTL）；系統文字含窄的破壞性樣式（force push、DROP TABLE、`rm -rf`、`reset --hard`）也照舊分類。系統文字的字面也不再觸發 command floor |
| 2 | 已做 | 門檻 12 個 code point，選項 `continuationMaxChars` 可調（`0` 關閉）。「無新任務內容」用機器可判的條件落實：不含工作流詞、不含風險詞（含「部署」「發布」「上線」等中文詞）、不以 `/` 開頭。給 nimble 看的「上一個請求」只記真正的提示 |
| 3 | 已做，**形式不同** | 寫進 mod 的 `$.store`（`model-router.log`，環狀 300 筆），不是 jsonl：mod 介面的 `$.fs.write` 是整檔覆寫、沒有 append。只存長度、分數、tier、session／送出的 pair、how、note，不存 prompt 文字 |
| 4 | 已做，**措辭與建議不同** | 只收窄成 destructive 會讓 60 段真實提示的 risky 從 25 降到 14，被放掉的 11 個幾乎全是安全審查提示（不該降到 opus 以下）。最終加上 "a security review or audit" → 36 個 risky；7 個危險探針（force push、DROP TABLE、刪 production 表、正式環境 migration、拿掉 token 驗證、改 JWT secret、`rm -rf`）全程 0.97 以上，`commit 這次修改` 0.39 → 0.10。同一個 nimble 兩次呼叫的比較有雜訊，看分佈不看單值 |
| 5 | 已做 | 600000。引擎把 `plugin.json` 的 `userConfig` 預設值當選項餵給 mod，所以預設值要兩處同步；新增 `scripts/hooks/tests/model-router-defaults.test.sh`（含突變）守同步 |
| 6 | 不改 | 使用者裁定。§1.5 的結論（改 `tiers` 會生效、`/effort` 對被路由的回合無效）仍成立 |

### 實作中發現、報告原本沒預料到的事

- **預設值有兩份真實來源**：只改 `register.ts` 的 `cacheTtlMs` 預設，測試仍看到舊的 5 分鐘，因為引擎餵的是 `plugin.json` 的值。mod 載入器不允許測試匯入 `.json`，所以同步檢查放在 claude-config 的 bash 套件（由 `run-all.sh` 與 CI 跑）。
- **自審抓到的問題**：codex 1 條（bash 套件缺 node 時退出碼錯誤，已重現並修）；獨立 opus 審查 5 條，採納 4 條（破壞性系統文字、中文部署詞、冷 cache、標籤顯示 `undefined`）、駁回 1 條（haiku session 沿用：分類器只看得到上一個請求文字、看不到模型提案，舊行為不比沿用準）；簡化審查 8 條，採納 4 條；安全審查 0 條。
- **突變驗證**：mod 測試 63 → 77 支，28 個突變全被抓到。兩個倖存者的處理不同：「寫入失敗會中斷回合」是測試盲點（引擎吞掉 hook 的例外，改成驗排在紀錄之後的 cache 統計仍寫入）；「≤0 關閉延續」是等價突變（刪掉多餘條件）。
- **歷史驗證**：439 個系統回合中，沒有一個後面夾著人打的字（用來評估「通知與人打的字被合併成同一段」的風險）。

### 仍待驗證

1. 新紀錄累積約一週後，用 `model-router.log` 對 transcript 算 nimble 的誤判率，以及沿用回合之後的升降次數（本報告只能從送出值反推）。
2. `turn.start` 的 `e.text` 是否與 transcript 的 user 文字逐字相同——系統前綴辨識的前提；不符時退回照舊分類，不會更糟，但沿用不會觸發。
3. harness 是否可能把排隊中的通知與使用者剛打的字合併成同一段 `e.text`（歷史資料 0 例，但沒讀 binary 確認）；若會，整段以系統前綴開頭，裡面的請求不會被風險詞篩到。
4. mod 的測試用 `claude plugin test <dir>` 執行，不在 `run-all.sh`／CI 內（CI 沒有 claude binary），改 router 後要手跑。

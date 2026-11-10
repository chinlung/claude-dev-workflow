# openspec-superpowers-workflow 3.0：依風險停下的確認點，與 Jev 的落點（2026-11-10）

> 狀態：設計稿，待使用者核准。使用者選擇跳過提問、直接照報告設計，所以文中所有取捨都是我的決定，集中列在 §9 供核對。
> 依據：`docs/openspec-hitl-gate-analysis-2026-11-10.md`，以下簡稱「分析報告」。
> 版本：plugin 2.2.1 → **3.0.0**（預設行為改變：P2、P3、P6b 不再停）；marketplace 1.15.4 → 1.16.0。

## 1. 為什麼做

分析報告的結論：
- P1–P3 的人工確認幾乎都原樣通過（嚴格反轉約 1／87）。
- 確認點上抓到的 3 個問題，都是使用者要求「加跑更強的審查」之後才浮現的，不是使用者自己讀出來的。
- 經過人工核准的 change，有 92% 在 Phase 5 仍有 REQ／DES Y 項。這些主要是機器審查抓到的。
- 等待的總成本集中在少數長尾：4 次等待超過 1 小時，合計 22.3 小時。
- 但 P1 上仍有 12% 的 change，由人類的取捨改變了要做什麼。這部分驗證測不到，必須保留。

所以方向是：**把「每個 phase 都停」改成「有事實需要人才停」**，並把使用者實際用來抓問題的動作（要求加審）變成停下之前的固定步驟。

## 2. 目標、非目標、反目標

**目標**
1. 典型 change 的硬停次數，從 4–5 次降到最多 2 次：P1 只在觸發條件成立時停，再加上 P5 收斂。
2. 停或不停由腳本判定；腳本讀到的事實中，只有結構事實（BREAKING、delta 標題）能擋住 agent 漏判，流程標記只是提醒（§4.1）。
3. 停下之前先跑獨立審查，把隱含的 WHAT 決策、沒列出的業界替代方案攤開。
4. 保留回到現行行為的開關（`supervised`）。

**非目標**
- 不用 hook 機器驗證「使用者真的核准了」。理由見 §8 的否決方案 R1。
- plugin 不依賴 Jev。plugin 會上 marketplace，Jev 需要個人 mod 和 OpenRouter key（§7）。
- 不改 Phase 5 的標籤語意和 Phase 6 的 archive-gate。

**反目標**（做到了也算失敗）
- agent 跳過了一個 WHAT 決策卻沒讓使用者知道：預設必須寫進 artifact，讓使用者事後看得到、否決得了。
- 為了少停，agent 把該列的待決事項寫成預設。對策：待決事項由獨立審查者列，不只由作者列（§4.1）。
- Phase 5 每個 change 的 REQ-Y 數上升，表示前段品質掉了（§6 的成效量測）。

## 3. 確認點的新行為

| 確認點 | 2.2.1 | 3.0（`risk-based`，預設） | `supervised` |
|---|---|---|---|
| P1 proposal／spec | 一律硬停 | `gate-check p1`：exit 0 → 公告後繼續；exit 10 → 先跑獨立審查，再硬停 | 一律硬停（也跑獨立審查） |
| P2 design | 有提問就停，Phase 3 等核准 | `gate-check p2`：design.md 有 `[needs user]` 問題 → 停；否則繼續 | 一律硬停 |
| P3 tasks | 一律硬停 | 不停；validator 通過就進 Phase 4 | 一律硬停 |
| P5 收斂 | 使用者宣告 `final` | 不變。另加「收斂建議」規則（§4.4），agent 主動提出證據 | 同左 |
| P6b 確認改寫 | 呈現後等確認 | 不停：改寫摘要寫進回覆與歸檔 PR 說明；reconcile-check 是閘門 | 等確認 |
| P6b5 needs_user_decision | 停 | 不變 | 不變 |

「公告後繼續」：回覆裡列出這個 change 採用的預設與理由，然後在同一輪接著做；使用者隨時可以中斷。預設也寫進 artifact，事後可以否決（§4.1）。

## 4. 機制

### 4.1 P1：獨立審查加上事實觸發

**順序**（使用者 2026-11-10 決定：審查只在要停時才跑）：
1. agent 寫 proposal、spec，以及 `## Decisions`。作者自己判斷的 `[needs user]`／`[default]` 也寫進去。
2. 跑 `gate-check p1`。
3. exit 0 → 公告後繼續，不跑審查。
4. exit 10 → 跑下面的獨立審查，把審查結果和停下的理由一起呈現給使用者。

**獨立審查**（只在 gate-check 判定要停時跑）
- 派一個子代理，模型 `opus`（判定類不得低於 opus）。輸入是 proposal.md、spec deltas，以及相關的 `openspec/specs/` 全文。
- 要它回答三件事：
  1. proposal 隱含了哪些「要做什麼」的決定，卻沒寫出來？
  2. 業界或工具（含 Claude Code）的常見做法，有沒有 proposal 沒列出的替代方案？
  3. 和既有 spec 有沒有矛盾？
- 結果寫進 proposal.md 新增的 `## Decisions` 段，格式如下：

```markdown
## Decisions
<!-- reviewed: opus 2026-11-10 -->
- [needs user] 兩種權限方案二選一：(a) … (b) …；我的建議 (a)，理由 …
- [default] 失敗時不重試，記 warning；理由 …
```

- `[needs user]` 是改變 WHAT、而且需要價值或風險取捨的項目；`[default]` 是 agent 採用的預設。
- 規則：審查者或作者列為 `[needs user]` 的項目，作者不得改成 `[default]`。

**`gate-check.cjs p1 <change-dir>`**（新 validator，只讀檔案、不送網路）

| 讀到的事實 | 判定 |
|---|---|
| 設定為 `supervised` | 停 |
| 沒有 `## Decisions` 段（內容可以是「無」，但段落要存在） | 停，理由「待決事項未記錄」：缺紀錄時偏向問人 |
| `## Decisions` 至少一項 `[needs user]` | 停 |
| proposal 含 `BREAKING` 字樣（任何形式，否定句也算；寧可多停） | 停 |
| spec delta 有 `## MODIFIED／REMOVED／RENAMED Requirements` | 停（改變既有契約） |
| proposal `## Impact` 列出的路徑命中設定的 `high_risk_paths` | 停 |
| 以上都不成立 | 繼續 |

- exit code：0 = 繼續、10 = 停、1 = 錯誤：用法或路徑錯，或（p3）tasks.md 格式不合；agent 修好再跑一次，第二次仍失敗才視同停。另有 `p3`／`p6b` 兩個模式：只看設定，p3 先核對 tasks.md 格式。實作時的偏離見 §11。stdout 列出命中的理由，agent 照抄進回覆。

**兩種觸發，強度不同。** 判定由腳本執行，但它讀的內容有兩種：
- **結構事實**：`BREAKING` 字樣、delta 的 `MODIFIED／REMOVED／RENAMED` 標題。這些也是 agent 寫的，但 OpenSpec 會驗證 delta 格式，而且使用者在 review 時看得到。
- **流程標記**：`[needs user]`、`reviewed:` 標記、不得降級的規則。這些全靠 agent 自律，**是提醒，不是閘門**。agent 可以把待決事項寫成 `[default]`，或不跑審查就寫上 `reviewed:`，腳本分辨不出來，這和 §8 R1 否決的弱點相同。審查只在要停時才跑，所以公告後繼續的 change 裡，`[needs user]` 只會來自作者自己。

所以實際能擋住 agent 漏判的只有結構事實；流程標記只能降低漏判的機率。

**回放驗證**（在本機以已歸檔的檔案重跑，不送出任何資料）：
- 分析報告中 P1 由人類改變 WHAT 的 3 個 change：
  - 2 個 delta 有 MODIFIED／REMOVED，結構觸發會停；
  - 第 3 個在歸檔版本裡沒有觸發，但當時對話紀錄寫著 proposal 標了 `**BREAKING**`，是 Phase 6 的乾淨改寫把標記拿掉了。所以在 P1 當下，3 個都會停。
- 經過 P1 的 25 個 change：15 個停、10 個公告後繼續。
- 限制：歸檔檔案是 Phase 6 改寫後的版本，不是 P1 當下的版本，以上只是近似值。
- 其中有一個 change，使用者選的方案是在「要求查最佳實踐」之後才出現的。這類價值完全取決於停前審查有沒有做到使用者當時要求的事；結構觸發只能保證會停，不能保證選項有被列齊。

**預估效果**：
- 275 個已歸檔 change 中，BREAKING 或修改既有 requirement 的佔 39%。
- 不計 `[needs user]`，約六成的 change 在 P1 會公告後繼續；但在既有行為修改較多的專案，比例較低（上述 25 個中 40%）。
- **為什麼不用關鍵字判高風險**：同一批資料上，關鍵字 regex 命中 92%，分不出差別。

**Phase 6a 怎麼處理 `## Decisions`**：
- 改寫成最終決定，拿掉 `[needs user]`／`[default]` 標記和 `reviewed:` 註解，每項寫成「採用 X：理由」。
- 這樣才符合 C5「讀起來像一開始就知道」。
- 已實測：含 `## Decisions` 段的 fixture，`openspec validate --strict` 回 0（OpenSpec 1.17.0），`reconcile-check check` 的 R1–R8 全部 pass。

### 4.2 P2：design 只在有 WHAT 問題時停

- `phases.md:116-120` 的提問預算不變：最多 2 題，而且只問會改變 WHAT 的問題。
- 這些問題在 design.md 的 `## Open Questions` 標成 `[needs user]`，其餘標 `[default]`。
- `gate-check p2`：有 `[needs user]` 就停，沒有就繼續到 Phase 3。
- 停前審查：和 P1 相同，只在 `gate-check p2` 判定要停時才跑。由一個 opus 審查者審 design.md，對照 `DESIGN-RED-FLAGS.md`。分析報告中 P2 有 1 次抓到問題，就是使用者在 P2 要求的 opus 審查抓到的。

### 4.3 P3：拿掉確認

- 這個確認 0／20 次改變了結果。tasks.md 寫完後由 `gate-check p3` 檢查格式（每個 `### Task N` 恰好一個勾選框），通過就直接進 Phase 4（實作時發現 `validate-openspec-workflow.cjs` 並不讀 tasks.md，所以檢查放在 gate-check，見 §11）。
- 執行方式（Native／SDD）照 `phases.md:174` 的既有規則選，不再問。

### 4.4 P5：加收斂建議，宣告權仍屬使用者

- agent 在以下三個條件都成立時，**主動**建議收斂：
  - 最後一輪各審查層都沒有新的 Y 項；
  - 沒有未修的 `[CODE]`；
  - 自最後一次修正後，每層審查都至少跑過一次。
- 建議時只問一題：收斂，還是再加跑哪一種高成本掃描。
- 宣告 `final` 仍然只能由使用者做（不變）。

### 4.5 P6b：改成機器閘門加 PR 審閱

- 6a 改寫完成後直接進 6b5（`reconcile-check.cjs check`），不等確認。
- 改寫摘要（每個 Y 項落在哪一份檔案）寫進回覆和歸檔 PR 的說明，使用者在合併 PR 時審閱。
- 6d 的 constitution 更新仍然要問，因為那會動到 `openspec/config.yaml`。

### 4.6 設定

- 設定分兩個檔案（沿用 plugin-settings 的 frontmatter 慣例）：
  - `high_risk_paths` 描述的是專案本身，放在**進版控**的 `.claude/openspec-workflow.md`；
  - 個人偏好的 `gates` 可以寫在 gitignored 的 `.claude/openspec-workflow.local.md`，覆蓋前者。

```yaml
---
gates: risk-based        # 或 supervised
high_risk_paths:         # 選填，glob；比對 proposal ## Impact 列出的路徑
  - app/Http/Middleware/**
  - src/auth/**
---
```

- 兩個檔案都不存在時，用 `risk-based`、空的 `high_risk_paths`。
- 設定檔讀取失敗時，**視同 `supervised`**（偏向問人）。這和 hook 的 fail-open 方向相反，是刻意的：這裡出錯的代價是跳過人類決策，不是多擋一次。

## 5. 要改的檔案

| 檔案 | 改什麼 |
|---|---|
| `skills/.../validators/gate-check.cjs`（新） | §4.1、§4.2 的判定 |
| `tests/gate-check.test.sh`（新）＋ fixtures | 每個觸發分支至少兩個觸發輸入；做突變測試：拿掉任一判定分支，測試要轉紅 |
| `phases.md` | Phase 1 Quality gate（:100-103）、Phase 2 trigger 與提問（:109-120）、Phase 3 Quality gate 與 Phase 4 trigger（:165、:171）、Phase 5 收斂（:248）、Step 6b（:279-285） |
| `SKILL.md` | Phase map 的「(user approves)」改成「(gate-check)」；How-to 第 3 點 |
| `OUTPUT-CONTRACTS.md` | :28、:72、:88 的「使用者已審核」改成「gate-check 通過，或使用者已核准」；proposal 加 `## Decisions` 契約 |
| `PHASE-IDENTIFICATION.md` | Phase 1→2、2→3、3→4 的轉換條件 |
| `README.md`、根目錄 `README*.md` | 確認點與設定說明 |
| `CHANGELOG.md`、`plugin.json`、`marketplace.json` | 3.0.0；marketplace 1.16.0 |
| `evals-design/`、`evals-phase6/` | 新增三個 eval：P1 有觸發 → 停；P1 無觸發 → 公告後進 Phase 2；P3 不停。既有 eval 重跑看 Δ |
| `tests/skill-docs.test.sh` | 若有斷言舊措辭，跟著改 |

## 6. 驗證與成效量測

**出貨前**
1. `tests/*.test.sh` 全綠，CI 綠。
2. `gate-check` 的突變測試：逐一拿掉每個判定分支，各自至少一個測試轉紅。測試的覆蓋率下限要獨立於受測的迴圈計算。
3. `claude plugin eval` 跑新增與既有的 eval：`--ablation with-without --judge-model sonnet --allow-tools Write Edit`，看 Δ，既有 eval 不得退步。

**上線後 4–6 週**
- 用分析報告的方法重跑，比較三件事：
  - 每個 change 的硬停次數，目標 ≤ 2；
  - Phase 5 每個 change 的 REQ-Y 數，不得上升；
  - 中途改方向與中斷的次數，不得上升。
- 任一項退步，就把對應的確認點改回去，或在 `supervised` 下重新評估。

## 7. Jev：哪些判斷點要加

判準沿用 CLAUDE.md 與 jev skill：
1. 事實已經寫下來；
2. 答案是分類或二選一；
3. 有下游會依結果行動；
4. 只用相對排序或低信心旗標，**不拿絕對機率當門檻**；
5. 送到 OpenRouter 的內容可以外流。

| 判斷點 | 結論 | 理由 |
|---|---|---|
| **Phase 5 review-notes 的標籤**（REQUIREMENT／DESIGN／CODE／CONSTITUTION） | **選用，效益待驗證；放在個人層，不進 plugin** | 實測（合成資料，eval 01／03／04 共 8 條，有 grader 定的正確答案）：8／8 全對，花費 $0.00008。唯一信心低於 0.5 的是「依落點標籤」陷阱題（0.39，DESIGN 0.54 對 CODE 0.46）。但有掛 skill 的 agent 在這些 eval 上本來就拿 1.00，所以還沒有證據顯示 Jev 能多抓到什麼。可能的用法：低信心或和 agent 標籤不一致時，agent 回去讀對應的 artifact 重判；只拿這兩個訊號，不拿機率當門檻 |
| `[CODE] Y` 誤標 | **不用 Jev，改用 validator** | 歷史上有 84 條，可以用 regex 機器偵測；有確定答案的事不需要模型 |
| SKIP 八面核對 | 維持現狀（CLAUDE.md 已列為選用的第二意見） | hook 不能也不該呼叫外部服務 |
| P1「要不要停」 | **否決** | 要停的條件必須是事實；拿 Jev 的機率當門檻，違反「絕對機率無分辨力」（jev skill 兩次對照） |
| P5 收斂 | **否決** | 這是預算決定，屬於使用者 |
| P6 spec「讀起來像一開始就知道」 | **否決** | 補丁措辭已由 reconcile-check 的 R 項以 regex 偵測；而且會把 spec 全文送出去 |
| Phase 5 finding 分配驗證強度 | 已在 scope-ledger 流程，不重複 | — |

**放在個人層的原因**：
- plugin 是公開發佈的，使用者不一定有 Jev mod 和 key。
- review-notes 會含客戶專案內容，要不要送出去由各專案決定。

原本打算在個人層 `~/.claude/skills/jev` 的落點表加一列「openspec review-notes 標籤複核」。**使用者 2026-11-10 決定先不做**：效益還沒證實，等用真實 review-notes 量過再議。

**實測的限制**：
- 只有 8 條，而且是合成資料；有掛 skill 的 agent 在這些 eval 上本來就拿 1.00。
- 所以 Jev 在真實資料上能多抓多少，目前沒有證據。要量就得用真實的 review-notes，會送出客戶內容，需要使用者另外同意。

## 8. 考慮過但否決的方案

- **R1：用 hook 驗證使用者核准**（PreToolUse 讀 transcript，確認 proposal 最後修改之後有使用者訊息）。
  否決理由：判斷「這則訊息是核准」本身是語意判斷；而 agent 自己寫的核准紀錄檔，和自我宣告一樣弱。依 CLAUDE.md「加閘門的判準」，這樣的閘門讀的不是環境事實，只是自寫斷言。
- **R2：關鍵字判高風險。** 在 275 個 change 上命中 92%，分不出差別（§4.1）。
- **R3：完全自動（P1 也不停）。** 分析報告中 12% 的 change 在 P1 由人類改變了 WHAT，而驗證只能確認程式符合 spec、不能確認 spec 是對的需求。
- **R4：P1 的停或不停交給 agent 判斷**（「有待決事項才停」）。中途改方向的案例顯示，agent 會漏掉自己沒注意到的決策；skip-gate 存在的原因也一樣。

## 9. 使用者的決定（2026-11-10）

1. **停前的 opus 審查：只在 `gate-check p1` 判定要停時才跑。**
   - 證據兩面：確認點抓到的 3 個問題中，有 2 個來自「要求加跑審查」；但使用者也至少 3 次拒絕了 agent 主動提議的額外審查。
   - 這個做法讓成本只花在本來就要停的地方。
2. **預設模式：`risk-based`，版本 3.0.0。**
3. **P6b：不停。** 前提成立：歸檔一律透過 PR 合併。

## 10. 我做的決定（請核對）

1. 版本定為 3.0.0，因為預設行為改變（使用者已確認，見 §9.2）。
2. 設定讀取失敗時視同 `supervised`，偏向問人。
3. 高風險只認專案設定的路徑清單；預設空的，只靠結構觸發。
4. Jev 不進 plugin；個人層的落點也先不加（使用者決定，見 §7）。
5. 這份設計跟 3.0 的實作放同一個 PR。

## 11. 實作時與本稿的偏離（2026-11-11）

- **四個模式**：gate-check 除 `p1`、`p2` 外多了 `p3`、`p6b`，讓 supervised 與設定讀不懂的規則只在程式裡寫一次，文件不必在每個確認點各重述。
- **P3 的格式檢查在 gate-check，不在 validate-openspec-workflow.cjs**：後者不讀 tasks.md。
- **沒有 shell 的 session** 照 phases.md「Gates」節的同一份規則手動判定，不是一律停。
- **比對一律從寬**：`[needs user]` 不限項目寫法與段落，delta 標題不分大小寫，Impact 的路徑可被括號、連結、粗體包住；拼錯的設定 key、行內的 `high_risk_paths`、重複的 `gates` 都算設定讀不懂。這是「有疑慮就停」的同一方向，起因是審查時一再找到「該停卻靜默放行」的輸入形式。
- **BREAKING 只認大寫**：小寫的 breaking 在一般文字裡太常見（breaking down work）。

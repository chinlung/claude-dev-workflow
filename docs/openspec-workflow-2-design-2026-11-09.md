# openspec-superpowers-workflow 2.0：歸檔閘門與 skip-gate v2 設計（2026-11-09）

> 狀態：使用者 2026-11-09 核准全文（建構者檢查完成、三個決策點已回答）。範圍是路線圖（`docs/optimization-roadmap-2026-11-09.md`）的 W2-1、W2-2，即 PR 2。W2-3 至 W2-6 與紅燈 eval（W0-3）留給 PR 3，見「出貨方式」。
> 依據：`docs/lifecycle-and-placement-review-2026-11-09.md` 的 P-A、P-C、P-D（用量數字與抽樣都在那份文件）。

## 1. 為什麼做

這個 plugin 有兩個關卡寫在文字裡，實際使用中沒有擋到任何事：

- **Phase 6 歸檔前核查**：`phases.md` 寫「此 gate 不可跳過」，但在 9 個真的跑了 `openspec archive` 的 session 裡，核查清單 `RECONCILIATION-CRITERIA.md` 的讀取次數是 0。
- **skip-gate hook**：它在 openspec 專案的第一次程式碼編輯時 deny 一次，要求「逐項核對八個契約面並明示結論」。12 次 deny 之後沒有一次出現逐項聲明；模型直接重試，第二次就放行。9 個有 deny 的 session 裡 7 個是誤攔：4 個是同 session 歸檔後繼續編輯（`changes/` 空了，gate 以為沒有 change），3 個是只改文件。

另有一個沒人檢查的前提：Phase 6「所有 review 都通過、修正都已合併」才能歸檔。4 個 session 先歸檔、後來才處理 review 或安全審查的問題，那些修訂沒有進到 `openspec/specs/`。

## 2. 目標、非目標、反目標

**目標**

1. 歸檔前有一個機器可驗的核查結果，沒有它，`openspec archive` 被擋下。
2. skip-gate 擋下的是「沒有留下判斷」，而不是「第一次編輯」；留下的判斷是檔案，可稽核。
3. 誤攔從 7/9 降到 ≤1/9；deny 之後留下逐項聲明的比例從 0/12 升到 ≥90%。

**非目標**

- 不驗證聲明的真偽。hook 只能保證「判斷被寫下來、且自己沒寫出矛盾」（任何一面標「是」就不放行），不能保證寫的人誠實。
- 不碰 Phase 5 規則（不准改 spec、tag 依修改落點）和 Phase 6 整份重寫，`[CODE] Y` 誤標已從 48 降到 1，證明它們有效。
- 不做 W2-3 至 W2-6（tasks.md 執行紀錄、Phase 2 提問預算、對齊 OpenSpec 1.16、schema fork）。

**反目標（做到就是失敗，即使技術上能跑）**

- 閘門常常擋住正當工作。skip-gate 檔頭的原則仍然成立：誤擋的代價高於漏觸發。
- 任何一支 hook 因為自己的錯誤讓編輯或歸檔做不了。全面 fail-open。
- 歸檔依賴網路或 GitHub。

## 3. 約束

- 本 repo 沒有 `openspec/`；沿用 scope-ledger 前例：設計文件、計畫、TDD、`/review-branch`。
- 零相依 Node（`.cjs`）加 bash，與現有 validator 和 hook 一致；CI 的 `validate.yml` 自動跑 `plugins/*/tests/*.test.sh`。
- 版本簿記閘門（`scripts/validate-fixtures.cjs`）要求 marketplace 版本、`plugin.json`、changelog 頂部三者一致，且 changelog 標題必須是遞減的 semver，所以沒有 `[Unreleased]` 這種寫法。
- hook 輸入有 `transcript_path`，但官方文件明說該檔「written asynchronously and may lag the in-memory conversation」，hook 觸發時可能還沒有當輪最新的訊息（`hooks.md`，Common input fields）。

## 4. 設計

### 4.1 W2-1 歸檔閘門

三個部分。

**(a) `validators/reconcile-check.cjs`**（與現有 `validate-openspec-workflow.cjs` 同目錄，並把後者的檢查函式改成可 `require`）

```
node reconcile-check.cjs snapshot <change-dir>      # Phase 6 開始時跑一次
node reconcile-check.cjs check    <change-dir> [--json]
exit 0 = 機械檢查全過；1 = 有 fail；2 = 用法錯誤。
```

`snapshot` 把 `tasks.md` 的雜湊記到 `<專案>/.claude/openspec-reconcile.<change>.local.json`。`check` 做下面的檢查，每項輸出 `pass`／`fail`／`warn`／`manual`：

| # | 檢查 | 對應 | 類型 |
|---|---|---|---|
| R1 | 四個檔與至少一個 `specs/**/spec.md` 存在 | 既有 validator | fail |
| R2 | 每個 `### Requirement:` 的第一段含 SHALL 或 MUST | C4，既有 validator | fail |
| R3 | `## Round` 下以 `- [` 開頭的條目：合法 tag、有 Y/N、沒有 `[CODE] Y`。**只有最後一輪違規算 fail**，較早輪次只 warn（Phase 5 規則要求舊語意的輪次保留原文） | Phase 5 規則 | fail／warn |
| R4 | 最後一個 `## Round` 標題含 `final`（不分大小寫）。**只有使用者明說 review 已收斂之後，代理才可以加這個標記**（寫進 `phases.md` Phase 5）；沒有任何 Round 則為 `warn` | P-D 歸檔前置 | fail |
| R5 | `tasks.md` 與 snapshot 的雜湊相同；沒有 snapshot 時，若在 git 內則改比 `git diff HEAD`，兩者都不可用則 `warn` | C3 | fail／warn |
| R6 | 未勾選的 task 數；每個未勾項是否帶 `skip:` 理由 | P-B | **本 PR 只 warn**（見 4.4） |
| R7 | proposal、specs、design 內是否有補丁語言（「修訂：」「原本是」「Round N」等） | C5 | warn（誤報風險高，只提示） |
| R8 | `[CONSTITUTION] Y` 條目清單，請確認已進 `openspec/config.yaml` | C2 | manual |
| R9 | C1（Y 項是否都落到正確 artifact）與 C5 的連貫性 | 需要判斷 | manual，印出判準 |

`check` 沒有 `fail` 時寫入 `<專案>/.claude/openspec-reconcile.<change>.local.json`：`{verdict:"pass", at, hashes:{tasks, reviewNotes, specs, design, proposal}}`。`manual` 項只列出，不計入 verdict，由代理在回覆裡逐項處理（這正是原本 6b5 表格要求的內容，現在由腳本把判準印在眼前，不靠代理記得去讀那份文件）。

**(b) `hooks/archive-gate.sh`**（PreToolUse，matcher `Bash`；兩條 handler，分別帶 `if: "Bash(openspec archive *)"` 與 `if: "Bash(mv *)"`）

```text
input(JSON) → 從命令取出要歸檔的 change 名稱：
  `openspec archive <名稱>`，或 `mv <changes>/<名稱> <changes>/archive/…`（bulk 時有多個）
  取不到任何名稱 → allow（if 欄位已先擋掉其餘命令）
  每個名稱各自檢查，任一個未通過就整個命令 deny
  含 OPENSPEC_ARCHIVE_OK=1 → allow                    # 與 bare-cd 的繞過同形
  取不出 change 名稱、找不到 openspec/changes/<名稱>/ → allow（fail-open）
  <專案>/.claude/openspec-reconcile.<名稱>.local.json
     不存在 / verdict≠pass / 記錄的任一雜湊 ≠ 現在的雜湊 → deny(exit 0 + JSON)
        訊息：先跑 check；列出該跑的指令與 manual 項
     否則 → 寫 ${TMPDIR}/claude-openspec-archived-<session> 後 allow
任何例外（缺 jq、JSON 壞掉、讀檔失敗）→ allow
```

OpenSpec 1.16.1 的 `/opsx:archive` 與 bulk-archive 範本不呼叫 CLI：代理自己同步 spec 後，`mkdir -p …/archive` 再 `mv <changeRoot> <changesDir>/archive/<date-name>`（`dist/core/templates/workflows/archive-change.js` 第 168、178 行，bulk 版第 236–237 行；專案內安裝的 `.claude/commands/opsx/archive.md` 相同）。所以兩種形式都要攔。transcript 兩個月內實際觀察到的是 CLI 36 次、`mv` 0 次（本 plugin 的 `phases.md` 教的是 CLI），但範本路徑一旦被用就會繞過閘門，攔下它的成本只是多一種解析。雜湊比對讓「檢查通過之後又改了檔」自動失效。

**(c) `hooks/hooks.json`** 在 PreToolUse 新增這個 Bash 條目；既有的 skip-gate 條目不動。

### 4.2 W2-2 skip-gate v2

四個改動，全部在 `hooks/skip-gate.sh`：

1. **文件類路徑豁免**：副檔名為 `.md`、`.mdx`、`.txt`、`.rst`、`.adoc`，或路徑在 `docs/`、`doc/` 之下，直接放行（3/9 的誤攔）。
2. **歸檔後情境**：同 session 有 `claude-openspec-archived-<session>` 標記時，deny 訊息改為針對 review 後的修正，並要求聲明檔比標記新（歸檔前寫的聲明不再有效）。沒有特殊的「post-archive fix」字樣：八面規則照舊，碰到契約面就開 follow-up change，因為這正是 spec 漏掉修訂的情況（P-D）。R4 生效後這類編輯應該很少，因為 review 沒收斂就不能歸檔（4/9 的誤攔）。
3. **聲明檔取代批次窗與 session flag**：
   - 狀態只有一個：`<專案>/.claude/openspec-skip.<session>.local.md`。副檔名 `.local.md` 是為了沿用專案常見的 `*.local.md` 忽略規則。
   - 內容必須有一行：`契約面：API=否 資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 跨模組=否 ｜ 理由：<一句>`。
   - 檔案不存在 → deny，訊息附完整路徑與可複製的格式行。八個 key 缺一、值不是「是／否」 → deny 並指出缺哪個。**任何一面是「是」→ deny，要求啟動 workflow（Phase 1）**。八面全「否」 → allow。
   - 同一批並行編輯會全部被擋（檔案還不存在），不再需要 5 秒批次窗和 `stat` 跨平台處理。
4. **不設防死鎖計數器**：按次數計會被一批並行編輯用光，打穿「留下聲明」的目標；而寫聲明檔是一次普通的 Write（`.claude/` 不受本 hook 攔），沒有寫不出來的正常情況。hook 自身出錯時照舊 fail-open。任何一面是「是」時的出路是開 change，這是 plugin 要的行為，不算卡住正當工作。

### 4.3 路線圖的三處修正

| 路線圖原文 | 改成 | 理由 |
|---|---|---|
| W2-2(c) 重試時讀 `transcript_path`，用 regex 驗最後一則 assistant 回覆 | 聲明寫成檔案 | 官方文件明說 transcript 可能落後當輪訊息，會造成「寫了卻被判沒寫」的誤攔；檔案是同步可讀的環境事實，而且可稽核 |
| W0-3 紅燈 eval 在 PR 2 先行 | 移到 PR 3 | W2-1、W2-2 是 hook 與腳本，eval 沒授權 Bash、hook 也不在 eval sandbox 觸發；它們的紅燈是 fixture 測試先寫先紅。LLM eval 只適用改文字的 W2-3、W2-4、W2-5 |
| W2-1 把 R6（未完成 task）列為 fail | R6 本 PR 只 warn | W2-3（Phase 4 逐項勾選、`skip:` 理由）還沒進文字層，現在擋會讓代理面對一個它沒被教過的要求 |

### 4.4 測試（TDD，先紅後綠）

- `tests/skip-gate.test.sh` 改寫為 v2 語意。現有 11 組情境逐一對應（非 openspec 專案、有 active change、只有 archive、openspec／.claude 內路徑、專案外路徑、無 file_path、session_id 消毒等）；新增：文件豁免、歸檔後情境、聲明檔五種狀態（缺檔、缺 key、非是否值、含「是」、合法）、同批並行全擋。
- 新增 `tests/reconcile-check.test.sh`：以 `tests/fixtures/openspec-workflow/` 為底，每個 R 檢查各有通過與失敗 fixture；`snapshot`／`check` 的雜湊流程；雜湊失效。
- 新增 `tests/archive-gate.test.sh`：命令解析（`--yes`、複合命令、無名稱）、四種 deny 條件、繞過字樣、fail-open 路徑。
- **突變驗證**：每個閘門至少對執行路徑做突變（移除雜湊比對、移除「任何一面是」判斷、移除文件豁免），套件必須轉紅。依 CLAUDE.md，突變打在執行路徑，不是它處理的資料。
- 實機：在一個臨時 openspec 專案裡跑真的 `openspec archive`，確認 deny 與放行兩條路徑，以及 `/opsx:archive` 同樣被攔。

### 4.5 要更新的文字

`phases.md` Phase 5 格式段（收斂證據的寫法與時機）、`README.md`（hook 章節）、`SKILL.md` description 與規則（歸檔前須跑 check；SKIP 判定須有聲明檔）、`phases.md` 6a（snapshot）與 6b5（改為「跑 check，處理 manual 項」）、`PHASE-IDENTIFICATION.md` Case 3、`RECONCILIATION-CRITERIA.md`（每項對應 R 編號）、marketplace 的 plugin 描述。changelog 條目留到 2.0.0 那個 PR（4.6）。

### 4.6 出貨方式

PR 2 **不 bump 版本**，內容是本文件加 W2-1、W2-2 的實作與測試；PR 3 做 W0-3 與 W2-3 至 W2-5，並一次出 2.0.0（plugin.json、marketplace、兩份 changelog 同步）。這與路線圖 D1「一次出 2.0」一致。代價是 PR 2 合併後到 PR 3 之間，main 上有未發佈的行為；已安裝的副本不會更新（版號不變），全新安裝是否讀到 main 的最新內容我沒有驗證。

## 5. 驗收

| 指標 | 基準 | 目標 | 量法 |
|---|---|---|---|
| deny 後留下逐項聲明 | 0/12 | ≥90% | 重跑 `knowledge-usage` 的 gate 統計與 transcript 抽樣（2.0.0 發佈後兩週） |
| skip-gate 誤攔 | 7/9 session | ≤1/9 | 同上 |
| 歸檔前沒有核查紀錄 | 9/9 | 0 | 歸檔統計腳本（W0-1 的另一半，PR 3 前補進 repo） |
| 歸檔後同 session 又改程式 | 4 | 0 或全都附聲明 | 同上 |
| 套件 | 24 項斷言 | 全綠加突變全紅 | `bash plugins/openspec-superpowers-workflow/tests/*.test.sh`、CI |

## 6. 風險

- **聲明可以亂寫**：八個「否」很容易寫。這是非目標，但要看清楚：它把「沒做判斷」變成「做了判斷但可能錯」，後者至少留下可稽核的證據，並讓事後統計能算出誰在什麼情況下聲明跳過卻又改了契約面。
- **歸檔閘門擋住正當歸檔**：snapshot 忘了跑、`final` 沒標、review-notes 沒有 Round。對策是 deny 訊息直接給出下一步指令，並有 `OPENSPEC_ARCHIVE_OK=1` 繞過；繞過次數也應該被統計看到。
- **`openspec` 命令形式變動**：以 `openspec archive <name>` 為準；解析不到名稱即放行。
- **`.claude/` 內的狀態檔進版控**：沿用 `*.local.md`／`*.local.json` 慣例，專案若沒有這條忽略規則，要提醒（scope-ledger 的 `init` 已有同型提醒）。

## 7. 已決定與留給實作者的

**使用者已決定**（路線圖 D1–D6）：一份設計文件、逐項 commit、2.0 一次出；設計階段提問上限 2 題（PR 3）；本文件範圍內相關的是 D1。

**使用者已決定**（2026-11-09）

1. 「review 已收斂」由使用者明說，代理之後才在最後一輪標 `final`；閘門檢查這個標記，不查 GitHub。
2. 歸檔閘門硬擋（deny），可用 `OPENSPEC_ARCHIVE_OK=1` 繞過。
3. PR 2 不 bump 版本；PR 3 完成 W2-3 至 W2-5 後一次出 2.0.0。

**建構者檢查後我的決定**（2026-11-09，獨立子代理讀本文件後提出 5 題；第 1 題的前提已讀原始碼確認）

1. 歸檔閘門同時攔 CLI 與範本的 `mv` 路徑（4.1(b)）。
2. 歸檔後沒有特殊聲明字樣，聲明須比歸檔標記新（4.2 第 2 項）。
3. 拿掉防死鎖計數器（4.2 第 4 項）。
4. R3 只對最後一輪判 fail（4.1 表）。
5. 聲明檔取代 transcript 驗證、R6 本 PR 只 warn、W0-3 移到 PR 3（4.3）。

**留給實作者**

R7 的補丁語言樣式清單、`final` 標記的確切寫法（目前定為最後一個 `## Round` 標題含 `final`）、文件豁免的副檔名清單、deny 訊息措辭、雜湊演算法（sha256）、狀態檔命名細節。

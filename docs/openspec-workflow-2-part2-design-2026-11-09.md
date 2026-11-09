# openspec-superpowers-workflow 2.0（下）：紅燈 eval、tasks.md 執行紀錄、Phase 2 提問預算、對齊 OpenSpec 1.16 設計（2026-11-09）

> 狀態：使用者 2026-11-09 核准四個決策點（eval 花費、個人設定 repo 小 PR、CI 裝固定版 OpenSpec、CI 升 Node 22）；建構者檢查已完成，三處缺口（補勾時機、`--yes` 與 verify 的定義、盲測詞表）已併入 4.1、4.3、4.5 與第 8 節。範圍是路線圖（`docs/optimization-roadmap-2026-11-09.md`）的 W0-3、W2-3、W2-4、W2-5，加上 W0-1 的另一半（歸檔統計腳本）與 2.0.0 出貨，即 PR 3。上半（W2-1、W2-2）已在 PR #41 合併，設計見 `docs/openspec-workflow-2-design-2026-11-09.md`。W2-6（schema fork）仍待 W0-2④ 的 spike，不在本 PR。

## 1. 為什麼做

體檢（`docs/lifecycle-and-placement-review-2026-11-09.md`）列出三個仍開著的缺陷，都只存在於文字層，沒有任何機器在看：

- **P-B** `tasks.md` 不是執行紀錄。歸檔統計裡約四成的 change 帶著未完成 task 歸檔，一半以上一格都沒勾。根因已抽查：`writing-plans` 產出每步一個勾選框，執行器改用 TodoWrite 追蹤、不回寫，plugin 的 6c 還教人「用 `--yes` 略過未完成警告」。
- **P-E** Phase 2 的提問量超過使用者耐受度。兩個 session 裡三次被明說「跳過提問」。
- **P-F／P-G** 與 OpenSpec 1.16 脫節。plugin 寫「`/opsx:apply` 沒有對應的 CLI」，實測有；Phase 4 主推的 SDD 兩個月用 0 次，executing-plans 用 5 次。

另外，路線圖要求「每個缺陷先有一題在現行版本上紅的 eval」，PR 2 因為做的是 hook 與腳本而延後，本 PR 補上。

## 2. 目標、非目標、反目標

**目標**
- 用 eval 在改文字之前證明缺陷可被量測（W0-3）。
- `tasks.md` 在 Phase 4 就被勾，歸檔時未勾項一定有理由，由 `reconcile-check.cjs` 的 R6 擋（W2-3）。
- Phase 2 預設先列假設、直接寫 design.md，提問上限 2 題（W2-4）。
- `phases.md` 的 CLI 與 `/opsx:*` 敘述與 1.16.1 一致，且由 CI 測試守著不再漂移（W2-5）。
- 歸檔統計腳本落地，之後驗收用同一把尺（W0-1）。
- 一次出 2.0.0。

**非目標**
- 不做 W2-6（schema fork）。
- 不改 Phase 5「不准改 spec」與 Phase 6「整份重寫」。路線圖的「刻意不改」仍然成立。
- 不為 Phase 2 的紅旗清單加機器閘門。判準是閘門要讀環境事實且有下游消費者，這項兩者皆無。
- 不處理 follow-ups 裡的五個 LOW 項（可在 PR 3 末尾順手收，但不列為交付）。

**反目標**
- 為了湊「一題紅」而改題。若一題在基準版本就綠，結論是「缺陷不在文字層」，照實記錄。

## 3. 約束

- repo 是 public：eval 目錄整個 gitignored，PR 內容、文件、統計輸出都不得出現真實專案名、change 名、session id。
- SKILL.md 的 description 已用 1506／1536 字，本 PR 的新規則只能進正文與參考檔，不能進 description。
- `reconcile-check.cjs`、兩支 hook 的 fail-open 契約與 exit code 契約（0／1／2／3）不變。
- eval 沒授權 Bash，本機 `~/.docker` 含 symlink 時授權 Bash 會整輪拒跑。因此 eval 只能測「只用 Write／Edit／Read 就能表現的行為」。
- 兩個 repo：本 repo 與 `~/.claude`（個人設定 repo，另有 git）。W0-3 要求的 `refs/plugin-eval.md` 與禁用字掃描腳本屬後者，另開一個小 PR。

## 4. 設計

### 4.1 W0-3 紅燈 eval

**基準版本。** 主線已含 PR 2 的文字，但版號仍是 1.5.0。要證明缺陷真實存在，紅燈跑在 PR 2 之前的 plugin（用 `git worktree` 取出 `753baae`，放在 `$TMPDIR`），綠燈跑本分支。

**哪些缺陷能用 eval 測**

| 缺陷 | 測得到嗎 | 做法 |
|---|---|---|
| P-A 歸檔核查只存在文字 | 否 | 需要 Bash 才能「跑」核查。紅燈已由 PR 2 的 fixture 測試先紅後綠提供，不另做 |
| P-B tasks.md 不勾 | 是 | `evals-design`：腳本預放 tasks.md，要求實作前兩項，檢查前兩個框被勾、其餘不動；另一題要求「第三項不做了」，檢查該行出現 `skip:` 加理由 |
| P-C SKIP 判定沒列八面 | 部分 | `evals-trigger`：測回覆是否逐面列結論。hook 本身不在 eval sandbox 觸發 |
| P-D 收斂前歸檔 | 部分 | `evals-phase6`：最後一輪未標 `final`、使用者說「歸檔吧」，回覆應先確認收斂，不做歸檔動作 |
| P-E 提問過多 | 是 | `evals-design`：使用者明說跳過提問時，回覆零問句且 design.md 已寫出；未明說時問句不超過 2 題 |

另有 Phase 6 的 clean rewrite、tasks.md 凍結、`[CONSTITUTION]` 走 `config.yaml` 三題（盤點備忘中的 flow D 本體），放進 `evals-phase6`。

**規模與成本。** 三個新 suite 共約 10 題，每個 suite 一個 `.gitignore`。先用 `--runs 1` 做 pilot，讀產出確認 with 組真的載入 plugin、grader 會叫，再 `runs: 3` 正式跑。估計新 suite 紅綠各一輪約 $30，加舊 Phase 5 suite 回歸 $11，全程約 $60 到 $80，每次執行帶 `--max-cost-usd` 上限。

**盲測規則（個人設定 repo 的小 PR）。** 取自 pstack 的 eval playbook：candidate 看得到的 prompt 與檔名不出現 eval、judge、experiment、score、rubric、compare、benchmark、candidate、arena（及中文「評分」「評審」）。pstack 的詞表還有 test 與「測試」，本 plugin 不禁：題目本身就是開發工作，TDD 的 tasks.md 與程式 scaffold 一定會出現這兩個詞，禁了任何像樣的題目都過不了掃描。掃描只套用新的三個 suite，舊 Phase 5 suite 不動，回歸比對才是同一份題目；不要求 candidate 自述用了哪些規則；目錄名用像專案的名字。新增 `refs/plugin-eval.md` 一節與 `scripts/audit/eval-blind-scan.cjs`（掃 prompt.md 與 scaffold 內容，命中就 exit 1），附含突變的測試。

### 4.2 W0-1 歸檔統計腳本

`plugins/openspec-superpowers-workflow/scripts/openspec-archive-stats.cjs`。

- 輸入 `--root <dir>`（可多次，專案目錄或其上層），掃 `openspec/changes/archive/*/tasks.md`。
- 一個 task 的定義與 OpenSpec 一致：任何深度的 `- [ ]` 或 `- [x]` 項（實測粗體 step 與巢狀項都被計為 task）。
- 輸出 JSON：已歸檔數、無 tasks.md 數、有 task 者中帶未完成者與比例、完全沒勾者、帶 `skip:` 理由者、依歸檔月份分桶。`--since` 供 2.0.0 發佈後的前後對照。
- 專案名預設以雜湊前六碼代替，`--names` 才顯示。輸出可直接貼進 public 文件。
- 測試是 bash 加 `mktemp -d` fixture 樹，突變：把勾選的 matcher 弄壞，測試必須紅。

**基準重現不了。** 路線圖記的 279 個、102 個未完成、56 個零勾，是當時 16 個專案的結果。今天重掃磁碟上的專案只有 133 個，其中 51 個未完成（38.3%）、26 個零勾，比例相近但絕對值不同（有些 worktree 與已刪專案不在磁碟上）。本 PR 以腳本在 2026-11-09 的輸出作為新基準並寫明日期與定義，不假裝重現舊數字。

### 4.3 W2-3 tasks.md 回到執行紀錄

**格式。** `tasks.md` 用 OpenSpec 的分組標題加 superpowers 的任務標題，且**每個 Task 只有一個勾選框**：

```markdown
## 1. 安全邊界
### Task 1: 讀取 session 前先驗證來源
- [ ] 1.1 驗證失敗時回 403，附測試
1. 先寫失敗測試……
2. 實作……
```

理由有二，皆已實測：
- OpenSpec 把**任何**勾選項都算成 task，不分深度與內容。`writing-plans` 的「每步一個框」會讓進度膨脹成五倍，「做完就勾」也變成沒人做的瑣事，這是 P-B 的根因。
- superpowers 的 `task-start`／`task-brief` 以 `### Task N` 標題切出每個 task 的簡報，標題必須留著。

Phase 3 的 sync-back 因此多一步：把 writing-plans 的步驟框改成編號清單，只保留任務標題下那一個框。

**Phase 4。** 每個 task 通過完成條件（executing-plans 的 `task-done`，或 SDD 的審查）後，在同一輪把該框改成 `[x]`。Phase 4 結束的出口檢查是 `openspec instructions apply --change <name> --json` 的 `progress.remaining` 為 0，或每個剩餘項都帶 `skip:` 理由。

**skip 的寫法。** 保持未勾，行尾加 ` — skip: <理由>`。理由不可空。這是 pstack 的「不做的步驟留在清單並寫 skip」。已知代價：OpenSpec 原生仍把它算作剩餘，`/opsx:verify` 會列為 CRITICAL，`/opsx:archive` 會警告。phases.md 6c 改成「警告若只列出帶 `skip:` 的項，屬預期」，刪掉「用 `--yes` 略過」。不選「勾起來加註」，因為那會讓「做完」與「沒做」在執行歷史裡無法區分。

**R6 由 warn 升為 fail。** 未勾且沒有 `skip:` 加非空理由的項，`check` 失敗，歸檔閘門因此擋下。tasks.md 完全沒有勾選框時維持 warn（可能是舊格式或 stub）。舊 change 若沒勾過會被擋，補勾、補 `skip:`，或明確帶 `OPENSPEC_ARCHIVE_OK=1`。這是 2.0 的 breaking 之一。

**補勾的時機。** Phase 5 與 6a 之後 tasks.md 都是凍結的，R5 以 Phase 6 開始時的 snapshot 比對。若等到 6b5 的 `check` 才發現 R6 失敗，就沒有合法時間點可以補，只剩繞過。所以 `snapshot` 在記錄雜湊之前先跑 R6：不過就 exit 1、不寫狀態檔，訊息列出缺理由的行。流程變成：Phase 6 開始，先把每個未勾項補勾或補 `skip:`（只准動框與 `skip:` 後綴，不改任務描述），再 `snapshot`。R5 不受影響，因為 snapshot 發生在補勾之後。Phase 5 期間才發現某項其實沒做完，照舊記成 `[CODE] N` 的條目，到這個 Phase 6 前置步驟再決定補勾還是 `skip:`。`check` 仍會再跑一次 R6，作為縱深防禦。

Phase 5 禁改 tasks.md 的規則不變。SUPERPOWERS-HANDOFF 的「可以 check off」改成只限 Phase 4。

### 4.4 W2-4 Phase 2 提問預算

phases.md Phase 2 改成：

1. 問之前先分類。能靠讀程式、跑指令、看輸出得到的答案是事實，不是問題，自己去查。
2. 只問會改變「做什麼」的問題，全 phase 總共至多 2 題。
3. 其餘不確定處寫成假設，列在 design.md 的 `## Open Questions`，每項附預設值。
4. 使用者說跳過提問（任何措辭），一題都不問，直接寫 design.md。
5. 能用實驗回答的分叉，做一次性 prototype，放在 `$TMPDIR` 或專案的 scratch 目錄，不放進 `openspec/`。結果以一行決定加證據寫進 design.md。這與「不建 sidecar 設計檔」不衝突：prototype 是拋棄式實驗，不是設計文件。
6. 覆寫 design.md 前，對照新增的 `DESIGN-RED-FLAGS.md` 自檢。命中者與處置寫進 design.md 的 `## Trade-offs`。

`DESIGN-RED-FLAGS.md` 是 pstack 八條紅旗的改寫（淺模組、資訊洩漏、依時序切分、穿透方法、分裂的擁有權、同事兩種做法、可匯入的內部、手動同步清單），前提是「下一個貢獻者是只看自己打開的檔的 agent」。檔首標明出處與 MIT 授權。

superpowers 7.0 的 brainstorming 自己已在第一則訊息提供「跳過提問」的出口，且只問一個開放問題。本 plugin 的 2 題上限涵蓋整個 Phase 2，優先於該 skill 的預設節奏。

### 4.5 W2-5 對齊 OpenSpec 1.16

**事實更正（本機 1.16.1 實測）**
- `/opsx:apply` 有 CLI：`openspec instructions apply --change <name> --json`，回傳 `state`、`progress`、`tasks[]`（含 `done`）。
- `openspec status --change <name> --json` 回傳各產物 `status`、`isComplete`、`applyRequires`。
- `openspec archive` 另有 `--skip-specs`、`--json`；`openspec validate --archived` 檢查已歸檔 change 的 task 是否全完成。

**`/opsx:*` 與階段的對照（新增一張表）**

| 指令 | 允許的階段 |
|---|---|
| propose、new、continue、ff | Phase 1（ff 會一次寫滿產物，design.md 與 tasks.md 仍視為草稿，之後被覆寫） |
| update | Phase 1 到 3。它會就地修補既有的規劃產物（proposal、specs、design、tasks）且不碰程式碼；Phase 4 起 tasks.md 是執行歷史、Phase 5 禁改 spec、Phase 6a 要整份重寫，所以都不得用 |
| explore | Phase 0 到 2；Phase 4 起不得用它改任何 spec 檔 |
| apply | Phase 4（其勾選動作與 W2-3 一致） |
| verify | Phase 5 入口，以及 Phase 6 核查的輸入；它的發現依標籤記進 review-notes |
| sync | 僅 Phase 6，且在 6b5 之後；archive 本來就會同步 main specs，所以通常不必 |
| archive、bulk-archive | Phase 6c，歸檔閘門適用，bulk 中每個 change 都要有新鮮的 `reconcile-check.cjs` 通過結果（指本 plugin 的 `verify` 子命令，不是 `/opsx:verify`） |

`--yes` 的處理（1.16.1 實測）：tasks.md 只要有一個帶 `skip:` 的未勾項，不帶 `--yes` 的非互動 `openspec archive` 會因讀不到 stdin 而 exit 1，change 不會被歸檔。所以 CLI 備援指令保留 `--yes`；刪掉的只是 6c 那句「用 `--yes` 略過未完成警告」的說法，改成「警告若只列出帶 `skip:` 的項屬預期，非互動時需帶 `--yes`」。歸檔前的把關是閘門與 R6，不是警告。
| onboard | 不屬任何階段（教學用） |

**Phase 4 主推改成 executing-plans**，SDD 列為「task 彼此獨立時」，與 CLAUDE.md 的決策樹一致。

**守住不再漂移：`tests/cli-claims.test.sh`。** 從 plugin 的 `.md` 抽出所有 `openspec <子命令> … --旗標`，斷言子命令在 `openspec --help`、旗標在該子命令的 help；`/opsx:<名稱>` 的集合由在暫存目錄 `openspec init` 產生的範本檔名推得，不手抄。乾淨設定下的預設 profile 是 `core`，只產生 6 個範本（apply、archive、explore、propose、sync、update），少了 verify、new、continue、ff、bulk-archive、onboard，所以測試必須先在隔離的 `XDG_CONFIG_HOME` 與 `HOME` 下執行 `openspec config set profile custom` 與 `openspec config set workflows '[…十二個名稱…]'`，再 `openspec init`；已實測這樣會產生全部 12 個範本，不需要互動式選單。另含一個格式測試：標準範例 tasks.md 餵給 `openspec instructions apply --json`，`progress.total` 必須等於 Task 標題數，守住 4.3 的格式主張。

**CI 必須真的跑它。** 條件式 skip 會製造覆蓋假象，所以：`validate.yml` 加一步 `npm install -g --ignore-scripts @fission-ai/openspec@<版本>`；測試在 `CI=true` 且找不到 openspec 時失敗，本機找不到才印顯眼訊息後 skip。版本字串只放一處（`plugins/openspec-superpowers-workflow/tests/openspec-version`），workflow 與測試都讀它，避免手動同步。OpenSpec 1.16.1 要求 Node 22.12.0 以上（`npm view` 實測），而 CI 現用 Node 20，所以 job 的 `node-version` 一併升到 22。這會影響所有套件；既有套件是零依賴的 CJS 與 bash，預期不受影響，但升級後整套要綠才算數。

### 4.6 出貨：2.0.0

- `plugin.json` 與 `marketplace.json` 的 plugin 版本改 2.0.0，marketplace 自身版本 1.13.3 → 1.14.0，description 同步。
- `CHANGELOG.md` 一個 2.0.0 條目，涵蓋 PR 2 與本 PR，Breaking 逐項列出：歸檔閘門、skip-gate v2、R6 變 fail、tasks.md 格式、Phase 2 提問預算。
- 版號變動後，已安裝副本才會更新。合併後需 `claude plugin update`。
- 重跑舊 Phase 5 suite，Δ 不得低於基準 +0.60 減一個雜訊容忍（0.05），且 with 組八題維持 1.00。

## 5. 測試（先紅後綠）

| 項目 | 紅燈 | 綠燈 |
|---|---|---|
| archive-stats | fixture 樹的預期數字，腳本尚未存在 | 實作後全過；matcher 突變轉紅 |
| R6 fail | `reconcile-check.test.sh` 新增：無理由未勾項 → exit 1、空理由 → exit 1、有理由 → 通過、零勾選框 → warn。目前 R6 只 warn，前兩案先紅 | 改 R6 後全過；移除理由檢查的突變使兩案轉紅 |
| cli-claims | 暫時把 phases.md 裡「apply 沒有 CLI」放著，斷言應失敗；加入 `openspec instructions apply` 的更正前先紅 | 文字更正後轉綠；突變：寫一個不存在的旗標，測試轉紅 |
| tasks 格式 | 範例 tasks.md 的 `progress.total` 斷言 | 通過 |
| LLM eval | 4.1 的紅燈表（跑在 `753baae`） | 本分支跑出綠，附數字 |

## 6. 驗收

| 指標 | 現況 | 目標 | 量法 |
|---|---|---|---|
| 帶未完成 task 歸檔 | 51／133（38.3%，2026-11-09 本機） | 下降；無理由的未勾項 0 | archive-stats，2.0.0 發佈兩週後 |
| 「跳過提問」糾正 | 3 次 | 0 | `knowledge-usage.cjs` 摩擦統計 |
| `phases.md` CLI 敘述與 help 不符 | 至少 2 處 | 0，且 CI 守住 | cli-claims 測試 |
| 舊 Phase 5 suite Δ | +0.60 | ≥ +0.55，with 組八題 1.00 | `claude plugin eval` |

## 7. 風險

- **eval 的 Δ 可能是空的。** 2.1.270 的 sandbox 只載入目標 plugin，superpowers 是否可用未驗證。第一輪 pilot 必須讀產出，確認 with 組真的依 plugin 文字行事。
- **R6 升級會擋住進行中的 change。** 有繞過變數，且是 2.0 已宣告的 breaking。
- **成本。** 估 $60 到 $80，皆帶上限。
- **CI 多裝一個 npm 套件，且 Node 要升級。** 用 `--ignore-scripts` 與固定版本降低面積。OpenSpec 要求 Node 22.12.0 以上，CI 因此由 20 升到 22，影響所有套件。
- **兩個 repo。** 個人設定 repo 的小 PR 與本 PR 之間無程式依賴，但紅燈 eval 要先過盲測掃描，所以順序是先個人設定 repo 後跑 eval。
- **版號。** 若不 bump，已安裝副本永遠拿不到。

## 8. 已決定與留給實作者的

**我替使用者做的決定（請檢查）**
1. skip 寫法用「保持未勾加 `skip:`」，不用「勾起來加註」。
2. 每個 Task 只留一個勾選框，步驟改成編號清單。
3. CI 固定 OpenSpec 版本並安裝，版本字串單一來源。
4. 歸檔統計輸出預設匿名專案。
5. 紅燈跑在 PR 2 之前的 plugin，不強求每個缺陷都有紅題。
6. 盲測掃描腳本與 refs 放個人設定 repo。
7. `snapshot` 先跑 R6，補勾補 `skip:` 發生在 snapshot 之前（4.3）。
8. CLI 備援指令保留 `--yes`；bulk 的把關指本 plugin 的 `verify`，不是 `/opsx:verify`（4.5）。
9. 盲測詞表不含 test 與「測試」，且只掃新的三個 suite（4.1）。

**留給實作者**：各 eval 題的具體情境與 grader 措辭、統計 JSON 的欄位命名、`DESIGN-RED-FLAGS.md` 的行文、Phase 4 出口檢查的確切用語。

## 9. 需要使用者裁決

1. 核准 eval 花費（上限內約 $60 到 $80）？
2. 同意另開個人設定 repo 的小 PR（refs 加一節、新增一支掃描腳本）？
3. 同意 CI 安裝固定版本的 OpenSpec CLI？
4. 同意 CI 的 Node 由 20 升到 22（OpenSpec 的硬性要求，連帶影響所有套件）？

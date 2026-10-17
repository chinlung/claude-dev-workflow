---
name: scope
description: 工作範圍帳本（<project>/.claude/scope-ledger.local.md，per goal、與分支無關）的維護指令：`init "<原始請求>"` 建帳本並判定 mode（converge／harvest）、`add "<請求>"` 把同一條工作線上的後續請求（commit、push、再審一輪）追加進現有帳本而不重開、`status` 看未完成項與 follow-ups（無參數時預設）、`facts <findings.json>` 跑 scope-facts 腳本替每條 finding 補機械事實（in_diff、hunk 距離、sibling、MUST 守則候選；輸出同時是 jev_decide 的 state）、`defer` 把項目移到 Deferred（嚴重度、理由、去處必填）、`done` 收帳並把 Deferred 搬進跨帳本的 follow-ups。Use when — the scope-gate hook denied an edit and asked for init; the first-prompt reminder said there is no ledger; a review / scan / audit just produced findings and the triage hook said to put them in the ledger first; the Stop hook listed open In-scope items; the user asks what is still unfinished, what was deferred, or to wrap up. 政策：review／scan 的產出是 input、不是工單——每條 finding 先 triage 進帳本再動手；延後是排程不是裁決，可利用的安全 finding、同缺陷 sibling、守則命中、boy-scout 直接採納，HIGH 安全項延後必須有 issue 或下一個 goal；goal 本身是找／修 finding（harvest）時 finding 就是工單。本 skill 不改 .gitignore、不評判 triage 內容、不取代 OpenSpec 的 tasks.md。
argument-hint: "[init \"<goal>\" | add \"<請求>\" | status | facts <findings.json> | defer \"<item>\" --severity HIGH|MEDIUM|LOW --why <理由> --to <去處> | done]"
---

# /scope-ledger:scope — 工作範圍帳本

帳本是一個檔案：`<project>/.claude/scope-ledger.local.md`，**一條工作線一份**，與分支無關——一個 goal 底下開幾個分支、幾個 PR 都記在同一份帳本的 Log 裡；切分支是正常工作，不會被閘門擋。同一條線上接續丟來的請求（commit、push、再審一輪、修審查結果）用 `add` 追加進同一本，不為每句祈使句重開：`done` 是收尾動作，不是每句話的例行步驟（曾一個 session 開了 6 本、其中 3 本的 goal 就是一個字 `commit`）。它是本次工作的基線：原始請求逐字、mode、In scope 清單、被延後的項目與去處。六個 hook 讀它：主代理首次改程式碼（Edit／Write，或 Bash 的 `sed -i`／`perl -pi`／重導向／`cp`／`mv`／`patch`）沒有帳本會被 deny 一次（子代理放行）；每 session 第一則提示若無帳本會提醒一次（不阻擋）；review 入口啟動時（模型呼叫 Skill、使用者手打 `/指令`，或 Workflow 工具跑 `tree` 的 review recipe／`claude-security:scan`）依 mode 注入 triage 政策並把 `review_rounds` 加一（review 型子代理與 codex 伴隨 pass 只注入不計輪；完整政策每 session 只注入一次，之後只提一行指回本檔的「Triage 政策」節，compaction／resume 後重新完整注入）；Stop 時 In scope 有未勾項會 block 一次；SessionStart（含 compaction 後）把帳本與 follow-ups 印回 context。帳本若被 git 追蹤（或經 symlink／submodule 進入 repo），所有 hook 一律忽略它——`init` 會檢查並提醒。

跨帳本的 backlog 是第二個檔案：`<project>/.claude/scope-followups.local.md`。`done` 把 Deferred 搬進去；SessionStart 與 `status` 會報它的件數（HIGH 優先），首則提示在專案沒有可用帳本時也報。延後的東西在這裡，不在記憶裡——記憶是會被忘的地方。

**`<project>` 是哪個目錄**：hook 用的專案目錄，也就是 session 的專案目錄（hook 讀 `CLAUDE_PROJECT_DIR`）。它不隨 Bash 的 `cd` 改變，**也不是你正在改的那個 repo**：在 A 開的 session 改 B 的檔案，帳本與 follow-ups 仍在 A（見 README 的 limits）。Bash 環境讀不到 `CLAUDE_PROJECT_DIR`，所以以 hook 訊息印出的路徑為準：首則提示的「本專案（…）」，或閘門、review 入口、Stop、SessionStart 印出的帳本路徑去掉結尾的 `/.claude/scope-ledger.local.md`。context 裡找不到這類訊息時用 session 開始時的工作目錄，不確定就問；**不要用 Bash 當下目錄推**，它會被並行呼叫的 `cd` 帶走。本 skill 其餘提到的 `.claude/…` 一律指 `<project>/.claude/…` 的絕對路徑，git 一律寫成 `git -C <project> …`。

## 帳本格式（逐字使用）

```markdown
---
goal: <使用者的原始請求，逐字一句>
mode: converge | harvest
opened: <YYYY-MM-DD>
opened_on: <建立時的 git 分支，純記錄>
review_rounds: 0
---
## In scope
- [ ] <項目> ← 來源: user
- [x] <項目> ← 來源: review-branch@r1
## Deferred
- <項目> ← 來源: security-review@r2 ｜ 嚴重度: HIGH ｜ 理由: <四問之一> ｜ 去處: <issue #N｜next: <goal>｜follow-ups｜review-notes｜won't-fix>
## Log
- <YYYY-MM-DD HH:MM> <工具> r<N>: <n> findings → <a> adopted / <d> deferred / <x> noise
- <YYYY-MM-DD> PR #<n> opened on <branch>（或 merged）
```

follow-ups 格式（`done` 產生，也可手寫）：

```markdown
# scope-ledger follow-ups
- [ ] <YYYY-MM-DD> <HIGH|MEDIUM|LOW> <項目> ← from: <goal 摘要> ｜ 來源: <工具@rN> ｜ 去處: <issue #N｜next: <goal>｜follow-ups｜review-notes｜待排程>
```

`去處` 的值與 Deferred 一致（`done` 把 Deferred 原樣搬過來，`won't-fix` 不搬）。一行必須是這個形狀：`HIGH|MEDIUM|LOW` 後面要一個空格、`← from:`／`來源:`／`去處:` 三段齊全；`｜` 可用 ASCII `|`、`來源:`／`去處:` 可用 `source:`／`where:`；行尾 `<!-- scope:… -->` 的 metadata 註解（Pi 版寫入）會被忽略。

**文法只定義在 `hooks/scope-parse.awk` 一處**，所有 hook 都經它讀取；格式不合的行不會被默默算進或漏掉，而是由 SessionStart 大聲報出「第 N 行＋原因」（兩個檔案都報；首則提示只在專案沒有可用帳本時才開口，且只重複 follow-ups 的問題、不報帳本的；只列行號與固定用語、不回放內容；帳本另會報：frontmatter 裡不是 key: value 的行或缺 mode、區段標題與 In scope／Deferred／Log 只差大小寫或空白、未知區段下的清單行、缺 ## In scope——這些過去都會讓工作無聲消失）：欄位不齊但認得出（勾選框＋日期＋嚴重度都對）的行照常計入件數；認不出的行不計入，若它是未勾選的行會特別標明，避免待辦無聲消失。

硬規則：

1. `goal` 是使用者的話，逐字，不改寫成你的理解；`add` 追加的請求同樣逐字進 In scope，goal 不改。
2. In scope 每一行都以 `← 來源: user` 或 `← 來源: <工具>@r<N>` 結尾（`N` 取 hook 訊息裡的輪數）。只有頂層的 `- [ ]` 算未完成，縮排子項不算。
3. Deferred 每一行都有 `嚴重度:`、`理由:`、`去處:`；沒有去處的延後等於遺忘。
4. `mode`、`review_rounds` 由 `init` 與 hook 維護；Log 由你維護，每輪 review 與每個 PR 各記一行。

## `init "<goal>"`

1. 若帳本已存在且可用，看 In scope：
   - **全勾** → 不重開，視同 `add "<這句請求>"`（見下節）：追加一行、Log 記一行，goal／mode／`review_rounds` 不動，回覆說明「已追加到現有帳本（goal: …）」。只有使用者明說收尾（`done`、merge、走收尾 SOP），或請求明顯是另一件事（換 repo、換功能、harvest 型請求落在 converge 帳本、上一本已閒置很久）才先 `done` 再 `init`。
   - **有未勾項** → 拒絕，印出 goal 與未勾項：要接續就 `add`，要換目標先處理未勾項（完成或 `defer`）再 `done`。
   同一個 goal 換分支不需要新帳本。
2. 判定 `mode`：
   - **harvest**——請求本身就是「找出／掃描／審查／修一批 finding」：security-audit、claude-security、Dependabot／依賴漏洞、CI review 一批 comment、hardening follow-ups、「把報告裡的項目修掉」。finding 就是工單。
   - **converge**（預設）——其他所有：修一個 bug、做一個功能、一次重構。
3. `git -C <project> rev-parse --abbrev-ref HEAD` 取 `opened_on`；今天日期填 `opened`。
4. 決定 In scope：
   - `openspec/changes/<name>/`（`archive` 以外）存在 → 只寫三個階段項：`- [ ] 完成 openspec/changes/<name>/tasks.md 全部任務 ← 來源: user`、`- [ ] Phase 5 review-notes 收斂 ← 來源: user`、`- [ ] Phase 6 archive ← 來源: user`。不要把 tasks.md 的內容抄進來。
   - harvest → 先寫 `- [ ] 取得 finding 清單（<工具>） ← 來源: user`，finding 到手後依嚴重度分批加項（HIGH 一批、MEDIUM 一批…），每批對應一個 PR。
   - converge → 從請求本身拆 1 到 7 項，只寫請求裡有的事，不寫你猜「順便該做」的事。
5. 若 `<project>/.claude/scope-followups.local.md` 有未勾項：列出（HIGH 優先）並問使用者要不要把其中哪些併進這個 goal；使用者明說了才併，併入的行在 In scope 標 `← 來源: follow-ups`，並在 follow-ups 把該行勾掉。
6. 用 Write 寫到 `<project>/.claude/scope-ledger.local.md`（絕對路徑；`.claude/` 路徑不受 gate 管；目錄不存在就建）。
7. 檢查是否被 git 忽略，三個 rc 都要處理：
   ```bash
   git -C <project> check-ignore -q -- .claude/scope-ledger.local.md; echo "check-ignore rc=$?"
   ```
   - rc 0：已忽略，不用做事。
   - rc 1：未忽略。先 `git -C <project> ls-files --error-unmatch -- .claude/scope-ledger.local.md` 看是否已被追蹤；然後**在回覆裡明確給出該加的一行**——「請在專案 `.gitignore` 加 `*.local.md`」（已追蹤要先 `git -C <project> rm --cached -- .claude/scope-ledger.local.md`）——並請使用者確認。**不要自己改 `.gitignore`**，那是專案自己的設定；但在使用者加上之前，每次 `status` 都重複提醒。
   - rc 128：不是 git repo 或 git 失敗，略過。
8. 回覆：印出帳本，並說明之後 review finding 會先進帳本。

## `status`（無參數時的預設）

Read 帳本、原樣印出，最後一行：`mode <m>｜In scope 未完成 N 項｜Deferred M 項｜review 第 R 輪`。接著印 follow-ups 未勾項（HIGH 優先）：`follow-ups K 項（HIGH H）`。帳本不存在就說沒有，並提示 `init`；follow-ups 仍要印。

## `add "<請求>"`

同一條工作線上的下一句請求進現有帳本，不重開。

1. 帳本不存在或不可用 → 等同 `init "<請求>"`。
2. In scope 追加 `- [ ] <請求逐字> ← 來源: user`（請求含幾件事就拆成幾行，仍只寫請求裡有的事）；Log 記 `- <YYYY-MM-DD> add: <請求前 40 字>`。
3. 不改 goal、mode、`review_rounds`；不在此處提議 follow-ups（那是 `init` 的事）。
4. 「同一條線」的判準：同一個 repo、同一個原始目標的後續步驟——commit、push、再審一輪、修審查結果、補測試、更新文件。**不是**同一條線（開新帳本）：換 repo、換功能、goal 已 `done` 後隔很久的新需求、harvest 型請求（掃描／修一批 finding）落在 converge 帳本。
5. In scope 有未勾項時也可以 `add`（例如使用者在等結果時又丟一句）；未勾項照舊由 Stop hook 盯著。

## Triage 政策（每次 review／scan／audit 的結果在你面前時都適用）

review 的產出是 **input，不是工單**。先把每條 finding 分類、寫進帳本，然後才動手。**延後是排程，不是裁決**：被延後的真問題仍然是真問題，它只是換了落點；`done` 會擋住沒有落點的延後。

### 第一步：先跑 `facts`，再分類

四分類最關鍵的判準「屬本次變更引入」不是判斷，是事實：finding 的 file:line 在不在分支 diff 的 hunk 裡。先把一批 finding 寫成 JSON（每條 `path`、`line`、`claim`、`evidence`，可帶 `id`），跑：

```
node "${CLAUDE_PLUGIN_ROOT}/scripts/scope-facts.cjs" --repo "<被審 diff 所在 repo 的絕對路徑>" --findings "$TMPDIR/findings.json" > "$TMPDIR/facts.json"
```

（`--repo` 一律明寫：預設是 Bash 當下目錄，會被並行呼叫的 `cd` 帶走；跨 repo 工作時它是被審 diff 所在的 repo，不是 `<project>`。跑完先核對輸出的 `root` 就是那個 repo；`--base <ref>` 指定基準，預設是與 `origin/HEAD` 的 merge-base、沒有 origin 時是 HEAD——這時輸出的 `base_fallback` 是 `HEAD`、stderr 也會提醒，`in_diff` 只反映工作樹；diff 含已 commit 與工作樹，未追蹤的新檔整檔算新增。）每條 finding 會補上 `facts`：

| 欄位 | 用在哪一條判準 |
|---|---|
| `change_kind`、`outside_repo`、`line_invalid` | 先看這三個再看其他：`change_kind` 是 deleted／binary／mode／untracked 時整檔算在 diff 內（`-U0` 不會印 hunk）；`outside_repo` 為真表示路徑解析到 repo 外（含 repo 內的 symlink 指出去），腳本沒讀它，finding 本身先存疑；`line_invalid` 為真表示行號不是正整數，`in_diff` 一律 false，回頭查 finding 的 `line` |
| `in_diff`、`nearest_hunk_distance`、`file_in_diff`、`untracked` | ①「屬本次變更引入」：`in_diff` 為真就是；距離小是「直接相關」的候選；`file_in_diff` 為假通常是 pre-existing → ② |
| `sibling.count`、`sibling.matches[]` | ①「同缺陷 sibling」：同一段文字在 repo 的其他位置，逐一讀過再決定是否一次改齊 |
| `must_rules[]` | ①「專案 MUST 守則命中」：守則檔裡與 claim 共用字詞的規則行，是候選不是結論，要讀原文 |
| `patch_lines` | boy-scout 的「<10 行」與修復範圍估計 |

這些事實決定分類的主幹；剩下要判斷的只有「是不是真問題」與嚴重度。**同一份 `facts.json` 就是 `jev_decide` 的 state**——要先排序一批 finding 的驗證順序時，直接把它當 `state`、每條一題 `noul`，不必另外手寫中性 state（手寫 state 的成本正是 Jev 被跳過的原因）。Jev 的回答只用來排序與分配驗證強度，不用來決定分類。

### converge 模式（預設）

| 分類 | 判準（任一成立即採納） | 帳本動作 |
|---|---|---|
| ①採納（現在修） | 屬本次變更引入或直接相關；**或**可利用的安全 finding——講得出誰攻擊、做什麼、拿到什麼，且修在本次觸碰的範圍內；**或**同一缺陷的其他實例（sibling，一次改齊，別留下「同型 bug 在別處」）；**或**專案明文 MUST 守則命中；**或** boy-scout——<10 行、零退化風險（介面／行為不變）、實際改善 | In scope 加一行，`← 來源: <工具>@r<N>` |
| ②延後（Deferred） | 真問題但不屬本次；或 pre-existing 且不符①的任一例外 | Deferred 加一行，`嚴重度:`、`理由:`、`去處:` 必填；**HIGH 安全項的去處只能是 `issue #N` 或 `next: <goal>`**，不能只是「follow-ups」 |
| ③需使用者裁定 | 業務決策、取捨、範圍是否擴張 | In scope 加一行「請使用者裁定：…」，回覆中明列 |
| ④噪音／won't-fix | 誤報、與設計刻意相反（要能指出記錄）、無攻擊面 | 只在 Log 記一行，**附反證錨點（file:line）**——dismiss 跟 adopt 一樣要證據 |

`理由:` 用「過度修正濾鏡」的四問之一回答：①pre-existing、非本次引入 ②已有前置檢查防護 ③不對稱是刻意設計（附記錄） ④攻擊面不實存。

收斂規則：**原目標（goal）的 In scope 未全部勾完前，不屬①的一律②**——別把這一輪 review 滾成新目標。hook 在 review 累計第 3 輪起會要求你先列出 In scope 剩餘項與 Deferred 清單再決定要不要再開一輪，照做。

### harvest 模式

goal 本身就是找／修 finding：**finding 就是工單**。全部進 In scope，依嚴重度 HIGH→MEDIUM→LOW 分批、每批一個 PR；LOW 或可利用性不確定的項目可進 Deferred（附嚴重度、去處）而不是丟棄；誤報一樣要附反證錨點記 Log。hook 每 5 輪會要求一次盤點（已完成／剩餘／Deferred／follow-ups），照做，並確認是否該收尾。

每輪 review 結束在 Log 記一行：`- <日期時間> <工具> r<N>: <n> findings → <a> adopted / <d> deferred / <x> noise`。

## `facts <findings.json>`

跑 `scripts/scope-facts.cjs`（見「Triage 政策 › 第一步」），把輸出存到 `$TMPDIR/facts.json` 並印出 `root`、`summary` 與每條的 `in_diff`／`sibling.count`／`must_rules` 數；接著依 facts 分類、寫進帳本。沒有帳本時先 `init`。

## `defer "<item>" --severity HIGH|MEDIUM|LOW --why <理由> --to <去處>`

1. 在 In scope 找到該行（未勾的）；找不到就列出現有項目讓使用者指認。
2. 用 Edit 刪掉那一行，並在 Deferred 底下加：`- <item> ← 來源: <原來源> ｜ 嚴重度: <S> ｜ 理由: <理由> ｜ 去處: <去處>`。
3. 三個旗標都必填；`--to` 只接受：`issue #N`、`next: <goal>`、`follow-ups`、`review-notes`、`won't-fix`。`--severity HIGH` 且來源是安全類 review 時，`--to` 只接受 `issue #N` 或 `next: <goal>`。缺任一就不動檔案，直接問。

## `done`

收尾動作：使用者說收尾、merge、走收尾 SOP，或這條工作線確實結束時才做；一本帳本通常跨多個 commit／push，中間的請求用 `add`。前置條件，任一不滿足就列出缺什麼並停止：

- In scope 沒有頂層 `- [ ]`。
- Deferred 每行都有 `嚴重度:` 與 `去處:`；HIGH 安全項的去處是 `issue #N` 或 `next: <goal>`。

滿足後：

1. 把每一行 Deferred（`去處: won't-fix` 以外）搬進 `<project>/.claude/scope-followups.local.md`：`- [ ] <今天> <嚴重度> <item> ← from: <goal 前 40 字> ｜ 來源: <原來源> ｜ 去處: <去處>`。檔案不存在就建（第一行 `# scope-ledger follow-ups`）。`去處: next: <goal>` 的項目另外在回覆裡建議下一個 `init` 的 goal。
2. 寫一則專案記憶（`~/.claude/projects/<專案>/memory/`，type `project`）：goal、日期、Log 摘要（幾輪 review、幾個 PR）、搬進 follow-ups 的件數；已有同主題記憶就更新它。這是敘事，不是待辦——待辦在 follow-ups。
3. 刪除帳本檔。
4. 回覆摘要：做了什麼、延後了什麼到哪裡、follow-ups 現在總共幾項（HIGH 幾項）。

## 本 skill 不做的事

- 不改 `.gitignore`（只回報並給出該加的一行）。
- 不評判 triage 的內容——hook 逼判斷發生並寫下來，判斷是你的。
- 不取代 OpenSpec 的 `tasks.md`；有 active change 時 In scope 只放三個階段項。
- 不替使用者決定要不要把 follow-ups 併進新 goal——只列出來問。

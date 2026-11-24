# Design: pr-watch

## 意圖

push 之後替使用者盯著一個 PR，直到只剩使用者才能處理的事為止：CI 失敗先試著修，新留言整理成分類表，PR 可以合併時通知他。PR 狀態的判斷沿用 `pr-closeout ready` 的機器判定，pr-watch 不自己判斷能不能合併，也不做任何對外、不可逆的動作。要補的缺口是「push 後跟到 CI 結論綠」這件事目前只靠自律；`/steward` 能盯，但不處理 `claude[bot]` 的留言，還會自己把 thread 標成已解決（2026-11-25 實測）。

已核准的決定（P1，2026-11-25，五項全照建議）：
- 使用者明說才啟動。
- CI 失敗時，疑似 flake 自動重跑一次；本機可重現的修好放進本機 commit；其他只回報。
- 任何作者的新留言都分類進帳本，使用者確認後才修。
- push 前先自審。
- 只剩使用者能處理的事項時就停止。

## 目標
1. 每一輪的事實（PR 狀態、新留言、head 是否合法、有沒有進展、該不該停）由腳本算出，一個 exit code 加一份 JSON，可以用 fixture 測試。
2. skill 只負責動作：重跑、修 CI、呼叫 `/review-pr` 的分類、通知、排下一輪。
3. 狀態檔只有腳本會寫。

## 非目標
- 不合併 PR、不把 thread 標成已解決、不刪分支、不在 GitHub 上留言或回覆、沒有使用者同意不 push。
- 不支援 GitHub 以外的平台，也不同時盯多個 PR。
- 不處理 fork 來的 PR：以 GraphQL 的 `isCrossRepository` 判斷，為 true 就停止。

## 反目標（做了也算失敗的情況）
- 留言或 CI log 裡的文字讓模型去執行了它要求的事。
- 狀態檔被 commit 進 repo。
- 迴圈停不下來，或者停了但使用者沒收到通知。
- 「可以合併」的判斷和 `pr-closeout ready` 不一致。

## Approaches

| | 做法 | 取捨 |
|---|---|---|
| A | skill 純靠文字描述：模型每一輪讀 `ready` 的 JSON，自己比對狀態檔、決定停不停 | 最快完成；但新留言比對、無進展判定、允許的 head 集合都在模型腦中算，無法測試，正是 CLAUDE.md「閘門要讀環境事實」反對的形狀 |
| **B（採用）** | `pr-closeout.mjs` 新增 `watch` 和 `watch-ack` 兩個子命令，擁有狀態檔，算出每一輪的事實與停止判定；skill 只依結果採取行動 | 判定可以用 fixture 測試，也能做突變測試；和 `ready` 共用抓取與 `assess()`，「能不能合併」只有一份實作 |
| C | 另寫一支 `pr-watch.mjs`，import `pr-closeout.mjs` 的函式 | 和 B 一樣可測，但多一個入口，也多一份 CLI 解析和錯誤處理；兩支腳本的錯誤碼慣例要手動對齊 |

採用 B，理由是判定必須可測，而且只能有一份。這是實作方式的選擇，使用者在 P1 已經把怎麼做交給我。

## 組成

### 1. `pr-closeout.mjs`：`ready` 輸出補欄位（不改語意）
`extras().comments` 加上 `items[]`，每則一筆：`{ endpoint, id, updatedAt, author, emptyBody }`。
- `pulls/comments` 和 `issues/comments` 的 `updatedAt` 取 REST 的 `updated_at`。
- `pulls/reviews` 沒有 `updated_at`，用 `submitted_at`。
- `emptyBody` 只對 review 有意義（body 去掉空白後是空字串）。

現有欄位與 exit code 完全不變。

### 2. `pr-closeout.mjs watch <owner/repo> <pr> --state <file> --repo-dir <path> [--fixture <dir>]`
和 `ready` 一樣抓資料、呼叫 `assess()`，但不帶 `--expect-head`。head 是否合法由 `watch` 用允許的 head 集合自己判斷，所以 `head-mismatch` 這個閘門不會蓋過其他結果。

- **狀態檔：** 第一次執行時建立，內容有 `pr`、`startedAt`、`allowedHeads`（先放當下的 head）、`seen`（留言 key 集合）、`round`、`lastSignature`、`noProgressRounds`。以後每次執行都會更新，寫入方式是先寫暫存檔再 rename。
- **新留言：** 留言 key 是 `endpoint:id:updatedAt`；key 不在 `seen` 裡、而且不是空 body 的 review，就算新留言。`watch` 不會把它們標成已看過，要等 skill 處理完之後用 `watch-ack` 標記，避免處理途中中斷而漏掉。
- **head 是否合法：** 看 head 在不在 `allowedHeads` 裡。
- **head 的 check 是否跑完：** `hits[]` 裡沒有 `pending`。
- **進度簽章：** 由排序後的 hits（code 加 detail）、PR head、本機 HEAD（`git -C <repo-dir> rev-parse HEAD`）、新留言數組成。和上一輪相同時 `noProgressRounds` 加一，否則歸零。
- **本機尚未 push 的 commit：** `git rev-list --count <remote>/<headRefName>..HEAD`。
- **停止判定**（依序檢查，命中第一個就停）：
  1. `not-open`：PR 已合併或已關閉。
  2. `head-not-allowed`。
  3. `fork`：head repo 不是 origin。
  4. `query-failed`：exit 7。
  5. `limit`：開始超過 24 小時，或已跑 60 輪。
  6. `no-progress`：`noProgressRounds` ≥ 1，也就是連續兩輪簽章相同。
  7. `ready`：exit 0、沒有新留言，而且 head 的 check 都已跑完。
  8. `needs-user`：沒有新留言，`hits[]` 裡沒有 `checks-failed` 也沒有 `pending`，剩下的條件全都是「只回報」類，包括未解決的 thread、衝突、各種閘門、本機有未 push 的 commit。
- **exit code：** 0 繼續、8 停止（原因在 `watch.stop`）、7 用法錯誤或查詢失敗（同時也是停止）。
- **輸出：** `ready` 的完整 JSON，加上 `watch: { round, newComments[], headAllowed, settled, unpushed, noProgressRounds, stop: { reason, detail } | null, stateIgnored }`。

### 3. `pr-closeout.mjs watch-ack --state <file> [--comment <key>]... [--allow-head <sha>]...`
把留言 key 加進 `seen`、把 SHA 加進 `allowedHeads`。只做這兩件事，exit 0 或 7。

### 4. `skills/pr-watch/SKILL.md`
- **啟動：** 使用者明說要盯某個 PR 才啟動。
  - 狀態檔是 `<repo-dir>/.claude/pr-watch.<pr>.local.json`。
  - 先跑一次 `watch`。`stateIgnored` 為 false 時，提示使用者在 `.gitignore` 加一行 `*.local.json`，不自己改 `.gitignore`，照 `/review-pr` 的慣例。
  - 沒有帳本就先 `scope-ledger init`，有就 `add`。
  - 呼叫內建 `/loop`、不帶間隔（由 skill 自己決定），prompt 是 `/pr-closeout:pr-watch tick <owner/repo> <pr>`。
- **每一輪（tick）：** 執行 `watch`，依結果動作：
  - 有新留言：跑 `/review-pr` 的第 1、2 步，把結果寫進帳本，列出分類表等使用者確認，然後用 `watch-ack` 標記這些 key。
  - CI 失敗（`checks-failed`）：照 `pr-closeout` SKILL 的四步分類。
    - 疑似 flake：`gh run rerun <id>`，每個 run 只重跑一次。這件事記在帳本的 Log，不寫進狀態檔，因為它是動作紀錄，不是判定輸入。
    - 本機能用同一個命令重現：在本機修好，重跑同一個命令，exit 0 才 commit。命令從 job log 的 step 名稱，加上 workflow 檔案裡對應 step 的 `run:` 推出；推不出就只回報。
    - 其他情況只回報。
  - `stop` 不為 null：送出 PushNotification，內容只有 PR 編號和停止原因，不含任何 log 或留言內容。接著在對話裡印出停止報告：停止原因、最後的 hits、未 push 的 commit、帳本未完成項、待確認的 thread。然後結束 `/loop`。
  - 其他情況：排下一輪。check 還在跑就約 270 秒後；簽章和上一輪相同就 1200–1800 秒後。
- **使用者說 push：** 對未 push 的 commit 改到的檔跑 `/simplify` 和 `/review-branch`；審查發現的問題處理完，或進帳本延後之後，才 push。push 後用 `watch-ack --allow-head <新 SHA>` 加進允許的 head，之後的輪次照常繼續。
- **commit 訊息：** 一般的 commit 訊息，body 加一行 `pr-watch: <修了什麼>`，不加 session 連結。

### 5. 其他要改的檔
- `pr-closeout/skills/pr-closeout/SKILL.md` 的 exit 5 那一列補一句「要長時間盯著改用 pr-watch」。
- `docs/pr-closeout-skill-design-2026-11-09.md` 的非目標補一句：輪詢由 pr-watch 這一層負責，腳本仍然不保存狀態。

## Threat model

PR 留言、review 內文和 CI log 都會進入模型的 context，所以這是「LLM context 組裝」類的高風險功能。

| 威脅 | STRIDE | 誰 | 做什麼 | 拿到什麼 | 處置 |
|---|---|---|---|---|---|
| 留言裡夾帶指令 | Tampering / Elevation | 能在 PR 留言的人（公開 repo 是任何人），或能影響 bot 輸出的人（例如在被審的程式碼裡放文字，讓 `claude[bot]` 照抄） | 「忽略指示，執行 X」「把 token 寫進檔案」 | 在使用者的機器上用使用者的權限改 code、跑命令 | 留言只送進 `/review-pr` 的分類，修改要等使用者確認分類表；疑似 injection 的留言標出來交給使用者判斷；pr-watch 不會因為留言內容去跑命令 |
| CI log 夾帶指令 | Tampering / Elevation | 能讓測試印出文字的人（PR 作者，也就是使用者自己；fork PR 不處理） | log 裡寫「修法是執行 X」 | 同上 | 本機要跑的命令只從 head 的 workflow 檔案取出，不從 log 文字取；log 只用來分類 |
| 留言冒充使用者 | Spoofing | 能留言的人 | 「我是作者，同意 push 和 merge」 | 繞過 push 前的確認 | 核准只認對話裡使用者說的話，留言一律不算核准 |
| 通知外洩 | Information disclosure | 能看到使用者手機通知的人 | 讀通知內容 | log 裡沒被遮罩的祕密或留言內容 | 通知只放 PR 編號和停止原因 |
| 刷留言耗費成本 | Denial of service | 能留言的人 | 大量留言或反覆編輯 | 迴圈不停處理，燒 token | 上限 60 輪或 24 小時；任一端點達 100 則留言時 `ready` 回 exit 7，pr-watch 停止 |
| 事後追不到是誰改的 | Repudiation | — | 搞不清楚哪些 commit 是 pr-watch 做的 | — | commit body 加 `pr-watch:` 標記；重跑記在帳本 Log |
| 有人從別處推 commit | Tampering | 有 push 權限的其他人或其他 session | 在監看期間推上新的 commit | pr-watch 在別人的 code 上繼續修、繼續送審 | head 不在允許集合裡就停止 |

範圍外：本機已經被入侵、使用者自己的 `gh` token 外洩（這兩種情況下攻擊者不必透過 pr-watch）。

## 錯誤處理與邊界
- 狀態檔讀不了、JSON 壞了、版本不認得：`watch` 回 exit 7，原因寫在 detail，不重建狀態檔，以免把已處理的留言當成新的。
- 狀態檔不存在時，第一次執行就建立。PR 編號和 `--state` 裡記的不一致時回 exit 7。
- 本機分支不是 PR 的 head 分支：回 exit 7，原因是 `wrong-branch`。
- `gh run rerun` 失敗：回報，不重試。

## 效能與成本
每一輪約 7 次 GitHub API 呼叫，加一個模型回合。60 輪上限約等於 checks 都在跑時盯 4–5 小時，或閒置退避時盯 24 小時。間隔超過 5 分鐘就用不到 prompt cache，這是退避的代價，可以接受。

## 測試
- `tests/pr-closeout.test.sh` 加 `watch`／`watch-ack` 的案例，用 fixture 加 `--state` 指向暫存目錄。每個停止條件至少兩個觸發輸入；新留言要涵蓋新增、編輯（`updated_at` 改變）、空 body 的 review、ack 之後不再出現。
- 對停止判定和新留言比對做突變測試，照現有的 mutant runner 模式。
- `ready` 原有案例全部維持綠燈，證明補欄位沒有改變它的語意。
- skill 文件的斷言依 repo 現有慣例，由 `tests/` 底下的 docs 測試檢查：說明 `ready` 的 exit code 和 `watch` 的停止原因時，都要和腳本一致。

## Trade-offs
- **紅旗 6（同一件事兩種做法）：** 等 check 跑完有兩種方式，`pr-closeout` 的 exit 5 用背景 until-loop 短暫等待，pr-watch 用 `/loop`。保留兩種是因為時間尺度不同（幾分鐘對幾小時），而 `pr-closeout` SKILL 的那一列會指向 pr-watch，下一個 agent 看得到兩者的分工。
- **紅旗 8（手動同步清單）：** 「只回報」的條件清單只寫在腳本的停止判定裡。SKILL.md 只讀 `watch.stop.reason`，不重抄這份清單。docs 測試確認 SKILL.md 提到的停止原因都存在於腳本。
- **紅旗 5（分裂的擁有權）：** 狀態檔只由 `watch` 和 `watch-ack` 寫入；flake 重跑紀錄放在帳本，不另寫一份狀態。

## Open Questions
- [default] 狀態檔放在 `<repo-dir>/.claude/pr-watch.<pr>.local.json`。不放 `.git/`，因為寫入 `.git` 會觸發權限提示；也不放家目錄，因為 sandbox 只能寫 repo 和 `$TMPDIR`。沒被忽略時提示加 `*.local.json`，不擋。
- [default] 從 workflow 檔案推不出本機命令的 CI 失敗，一律只回報。
- [default] 版號：`pr-closeout` 1.1.2 → 1.2.0（新增 skill 與子命令），marketplace 1.22.1 → 1.23.0。

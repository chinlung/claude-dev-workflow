# Proposal: pr-watch

## Why

push 之後要盯 PR 到可以合併，這件事目前靠自律：CLAUDE.md 寫了「push 後跟到 CI 結論綠才算收工」，起因是 2026-08-13 連兩輪 push 都沒看 CI，紅燈留在 main。

內建的 `/steward` 會持續盯 PR，但 2026-11-25 在沙盒 PR 上實測（Claude Code 2.1.331），有三點和這個流程不合：

- 只處理 PR 作者本人的留言。`github-actions[bot]` 要求修改的留言它完全沒處理。而使用者的應用類 repo（nou_ace_admin、matc_lama、pi-pstack）近期 PR 上的留言幾乎全是 `claude[bot]`。
- 修完本人的留言後，會用使用者的帳號把 thread 標成已解決（`resolvedBy` 是使用者本人）。
- 只認使用者逐字手打的指令，不能由流程接在 push 後面。

本 repo 已經有 `pr-closeout ready` 用 exit code 回報 PR 能不能合併，也有 `/review-pr` 抓取並分類留言、`scope-ledger` 分類 finding。缺的只有一個迴圈把這些接起來。

## What Changes

- **新增 `pr-watch` skill**（放在 `pr-closeout` plugin）：一次監看就是一段「啟動 → 若干輪 → 停止」，停止後由使用者處理完再重新啟動。每一輪讀 `pr-closeout watch`，依它算出的事實動作：
  - CI 失敗：照 `pr-closeout` 的四步分類處理。
  - 新留言：交給 `/review-pr` 的「只分類」模式處理。
  - 只剩使用者能處理的事項：送通知並停止。
- **`pr-closeout.mjs` 新增 `watch` 子命令：** 擁有以 PR 為單位的狀態檔，算出新留言、head 是否合法、check 是否跑完、本機未 push 的 commit 數、flake 重跑次數，以及停止原因。`--start` 表示使用者明說要開始一段新的監看，`--stop` 結束一段。
- **`pr-closeout.mjs` 的留言抓取改成分頁：** 某個端點有 100 則以上留言時，`ready` 和 `watch` 都能讀完，上限 1000 則。
- **pr-closeout 新增一個 PreToolUse 防護 hook（絆線）：** 有 PR 正在監看時，預設擋下 Bash 命令與 GitHub MCP 工具對 PR 的寫入（把 thread 標成已解決、留言、回覆、送出 review），只放行已知是讀取的。它擋的是習慣性或誤跟文件而做的寫入，不是擋住一個存心繞過的模型；邊界是只分類模式沒有寫入步驟，以及修改一律等使用者確認分類表。
- **code-audit-rigor 的 `/review-pr` 新增「只分類」模式**（`--triage-only`，可帶留言 id 清單）：只做抓取和分類，產出分類表就停，不進入修復、commit、push、回覆。
- pr-watch 永遠不合併 PR、不把 review thread 標成已解決、不刪分支、不在 GitHub 上留言或回覆，使用者沒說就不 push。

## Capabilities

### New Capabilities
- `pr-watch`：push 之後監看一個 PR，依 `pr-closeout watch` 的事實分派處理，直到只剩使用者能處理的事項或觸發停止條件；停止後可以重新啟動。

### Modified Capabilities
（無：本 repo 尚無 `openspec/specs/`。`/review-pr` 的只分類模式與 `ready` 的分頁屬於既有功能的擴充，寫在 pr-watch 的 spec 裡，因為只有 pr-watch 依賴它們的這些行為。）

## Impact

- `plugins/pr-closeout/scripts/pr-closeout.mjs`：`ready` 的留言清單已在 Task 1 完成；本次再加 GQL 欄位、分頁、`watch` 子命令
- `plugins/pr-closeout/skills/pr-watch/SKILL.md`（新增）
- `plugins/pr-closeout/hooks/pr-watch-guard.sh`（新增）、`hooks/hooks.json`
- `plugins/pr-closeout/tests/`（新增案例、fixture、hook 測試、docs 測試）
- `plugins/pr-closeout/skills/pr-closeout/SKILL.md`、`README.md`、`README.zh-TW.md`、`CHANGELOG.md`、`.claude-plugin/plugin.json`
- `plugins/code-audit-rigor/commands/review-pr.md`、`tests/`（新增 docs 測試）、`README.md`、`CHANGELOG.md`、`.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`、根目錄 `CHANGELOG.md`、`CHANGELOG.zh-TW.md`
- `docs/pr-closeout-skill-design-2026-11-09.md`（非目標那一節補註）

## Decisions

- 只在使用者明說「盯 PR」或打 `/pr-watch` 時啟動，push 後不自動開始。
- CI 失敗時，疑似 flake 整個 workflow 重跑一次；失敗出在這次的 diff 裡、而且本機能用同一個命令重現的，修好放進本機 commit；其他只回報。
- 任何作者的新留言都分類進帳本，使用者確認分類表後才修。帳本裡的那一行寫成「請使用者裁定：…」，用模型自己的話、附留言 key 和作者，不照抄留言原文；帳本會被 hook 印回對話，照抄等於讓留言的文字變成待辦事項。
- 使用者說 push 時，先對未 push 的 commit 跑 `/simplify` 和 `/review-branch` 才 push。
- 只剩使用者能處理的事項時，送通知並停止。
- 留言改由 `/review-pr` 的只分類模式處理，pr-watch 不只是列出新留言。對外動作由防護 hook 當絆線攔下；hook 不是邊界，邊界是只分類模式沒有寫入步驟，以及使用者確認分類表之前不做任何修改。
- 防護 hook 預設全擋、只放行已知是讀取的；同一類寫法連續三輪各補一條規則後，改成這個做法，不再逐一列舉寫入的拼法。
- 重新啟動是主要用法。`watch --start` 重設開始時間、輪數、進度簽章和 head 寬限期，保留已處理過的留言。`watch --stop` 結束一段（`active` 設為 false）；停止後的一般檢查被拒絕（exit 7，`stopped`），要繼續得重新 `--start`。
- head 合不合法，看「PR 的 head 是不是本機 HEAD 的祖先」。使用者從本機 push 不會誤停；別人推的 commit 本機沒有，照樣停止。
- 本機未 push 的 commit 數，用「API 回的 PR head 到本機 HEAD」計算，不用可能過期的 remote-tracking ref。
- head 第一次出現後的寬限期（一輪）內，一律不判「可以合併」或「只剩使用者能處理」。必跑 check 還沒出現時，視為還沒跑完，不當成失敗，但只算到該 head 第一次出現起的 3 輪；之後照一般的 `checks-failed` 處理，由「沒有進展」停止。只有 check 都跑完了，skill 才處理 CI 失敗。
- check 還在跑的那一輪不累計「沒有進展」；另外記錄「簽章連續未變的輪數」，只用來決定檢查間隔。「沒有進展」是 check 都跑完、連續兩輪簽章相同。簽章包含排序後的新留言 key，所以同一段時間內陸續出現的留言不會被當成沒有進展。
- 本機有未 push 的 commit 時，遠端的 CI 結果視為過期，直接判成「只剩使用者能處理」（等使用者決定要不要 push）。
- GitHub 查詢連續失敗 3 次才停止；在那之前，查詢失敗的那一輪不判斷其他停止條件。
- 留言的 key 是「端點＋id＋內文雜湊」。這樣 review 內文被編輯也偵測得到（REST 的 review 沒有 `updated_at`）。id 是 null 時，`watch` 回查詢失敗。
- 只在 check 都跑完之後才把新留言交去分類，免得 bot 一則一則貼留言時，被拆成好幾輪重複分類。
- flake 重跑一次的依據是 GitHub 回報的 `run_attempt`（等於 1 才重跑），不靠帳本裡的文字。讀不到 `run_attempt`（或不是 Actions 的 check）只回報。sandbox 內 `gh run rerun` 會失敗，這時改為請使用者執行。
- 有通知工具（PushNotification）就送；沒有就只在對話裡印出停止報告。通知內容只放 PR 編號和停止原因。先印報告、再通知。
- 工作樹有未 commit 的修改時，不自動修 CI，只回報。未追蹤的檔不算：分類和審查的結果檔會寫在 repo 根目錄，算進去會讓本機修復永遠不執行。
- code-audit-rigor 或 scope-ledger 沒安裝時，新留言只列出 key 和作者，請使用者自己處理；不中斷監看。
- 同一個 PR 兩次 `watch` 間隔不到 30 秒，第二次直接拒絕（可能有兩個 session 在盯同一個 PR）。上一段已停止時，`--start` 不受這個限制。
- 一個輪的時間是「不早於」：排定的時間到了，session 正忙時不會打斷，這一輪等回合結束才跑。判定只讀當下的狀態，所以晚到不會誤判；也不會提早，或無聲略過。
- 永遠不合併、不把 thread 標成已解決、不刪分支、不在 GitHub 上留言或回覆。合併仍走 `pr-closeout` skill。
- `watch` 的「可以合併」停止（`ready`）不含審查涵蓋（`unreviewed`）：`watch` 呼叫 `assess` 時不帶涵蓋資料，合併前由帶 `--repo-dir` 的 `pr-closeout ready` 判定。`unreviewed` 因此不在 watch 的只回報清單裡（使用者決定，從 watch 的清單拿掉）。
- 衝突、changes-requested、behind、blocked-unseen、draft 只回報，附上 `baseBehind`。
- 上限：一段監看 24 小時或 60 輪（從 `--start` 算起）。檢查間隔：check 還在跑時約 270 秒，簽章連續未變時退到 1200–1800 秒。用內建 `/loop` 的動態間隔。
- 一個 session 只盯一個 PR，狀態檔以 PR 為單位，存在 `<repo>/.claude/pr-watch.<pr>.local.json`。
- 留言內容和 check 名稱都進入模型的 context，屬於「LLM context 組裝」類高風險功能；design.md 有 threat model。
- 只支援 GitHub；fork 來的 PR（`isCrossRepository`）不處理。
- 輪詢放在 skill 這一層，腳本仍然不保存「要不要繼續等」的邏輯。這和 `pr-closeout` 設計文件的非目標「等待由呼叫端處理」一致，設計文件補一句說明。
- pr-watch 放在 `pr-closeout` plugin 裡。版號：`pr-closeout` 1.1.2 → 1.2.0，code-audit-rigor 2.3.0 → 2.4.0，marketplace 1.22.1 → 1.23.0。

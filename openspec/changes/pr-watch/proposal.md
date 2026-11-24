# Proposal: pr-watch

## Why

push 之後要盯 PR 到可以合併，這件事目前靠自律：CLAUDE.md 寫了「push 後跟到 CI 結論綠才算收工」，起因是 2026-08-13 連兩輪 push 都沒看 CI，紅燈留在 main。

內建的 `/steward` 會持續盯 PR，但 2026-11-25 在沙盒 PR 上實測（Claude Code 2.1.331），有三點和這個流程不合：

- 只處理 PR 作者本人的留言。`github-actions[bot]` 要求修改的留言它完全沒處理。而使用者的應用類 repo（nou_ace_admin、matc_lama、pi-pstack）近期 PR 上的留言幾乎全是 `claude[bot]`。
- 修完本人的留言後，會用使用者的帳號把 thread 標成已解決（`resolvedBy` 是使用者本人）。
- 只認使用者逐字手打的指令，不能由流程接在 push 後面。

本 repo 已經有 `pr-closeout ready` 用 exit code 回報 PR 能不能合併，也有 `/review-pr` 抓取並分類留言、`scope-ledger` 分類 finding。缺的只有一個迴圈把這些接起來。

## What Changes

- 在 `pr-closeout` plugin 新增 `pr-watch` skill，每一輪做兩件事：
  - 讀 `pr-closeout ready`，依它的判定分派：
    - check 還在跑：等下一輪。
    - CI 失敗：照 `pr-closeout` 既有的四步分類處理。
    - 衝突和各種閘門：只回報。
  - 比對留言，找出新留言或內容有更新的留言，交給 `/review-pr` 的抓取和分類步驟，結果寫進帳本。
- pr-watch 的修正只放進本機 commit。使用者說 push 時，先對這些 commit 自審再 push。
- `pr-closeout.mjs` 的輸出加上每則留言的 id 和更新時間。只增加欄位，現有欄位和 exit code 不變。
- 監看狀態以 PR 為單位，存在專案的 `.claude/` 底下（gitignored），可以跨 session 接續。
- 停止時送出通知，報告固定列出：停止原因、最後一次 `ready` 的 hits、還沒 push 的 commit、帳本未完成項、待使用者確認的 thread。
- pr-watch 永遠不合併 PR、不把 review thread 標成已解決、不刪分支、不在 GitHub 上留言或回覆。

## Capabilities

### New Capabilities
- `pr-watch`：push 之後持續監看一個 PR，依 `pr-closeout ready` 的判定和新留言分派處理，直到只剩使用者才能處理的事項，或觸發停止條件。

### Modified Capabilities
（無：本 repo 尚無 `openspec/specs/`）

## Impact

- `plugins/pr-closeout/skills/pr-watch/SKILL.md`（新增）
- `plugins/pr-closeout/scripts/pr-closeout.mjs`（`ready` 的 JSON 加上留言 id 和 `updated_at`）
- `plugins/pr-closeout/skills/pr-closeout/SKILL.md`（exit 5 的等待方式加一句：長時間等待改用 pr-watch）
- `plugins/pr-closeout/tests/`（新增 fixture 與案例）
- `plugins/pr-closeout/README.md`、`README.zh-TW.md`、`CHANGELOG.md`、`.claude-plugin/plugin.json`（版號）
- `.claude-plugin/marketplace.json`、根目錄 `CHANGELOG.md`、`CHANGELOG.zh-TW.md`（版號）
- `docs/pr-closeout-skill-design-2026-11-09.md`（非目標那一節補註：輪詢由 pr-watch 這一層負責）

## Decisions

- [needs user] 誰能啟動 pr-watch：(a) 只在使用者明說「盯 PR」或打 `/pr-watch` 時啟動，不自動開始 (b) 模型在 push 或開 PR 之後自動啟動。建議 (a)：迴圈會建 commit，輸入裡又有不可信的留言內容，啟動權留在使用者手上。和 `/steward` 不同的是，接受灰字建議或由 skill 轉述的指令也算數。
- [needs user] CI 失敗能自動做到哪裡：照 `pr-closeout` 的四步分類。(a) 疑似 flake 時，整個 workflow 自動重跑一次；失敗出在這次的 diff 裡、而且本機能用同一個命令重現的，修好放進本機 commit；其他只回報 (b) 和 (a) 相同，但重跑也要先問 (c) 只回報、不重跑也不修。建議 (a)：重跑 workflow 不改程式碼，`pr-closeout` 也已經把「重跑一次」列為第一步。
- [needs user] 哪些人的新留言要處理：(a) 任何作者（含 `claude[bot]`、Copilot、陌生人），都交給 `/review-pr` 分類、寫進帳本，使用者確認分類表後才修 (b) 只處理 bot 和本人的留言，其他人的只回報。建議 (a)：留言內容一律當不可信資料，靠分類加使用者確認擋 prompt injection，不靠作者名單。
- [needs user] 本機修正要怎麼 push：(a) 使用者說 push 時，先對未 push 的 commit 跑 `/simplify` 和 `/review-branch`（只看這些 commit 改到的檔），通過後才 push (b) 使用者說 push 就直接 push。建議 (a)：不審就 push，`ready` 會一直卡在 exit 6 `unreviewed`（這個閘門排在 pending 和衝突之前），而且違反 commit 前自審的 SOP。
- [needs user] 還有未解決的 thread 時什麼時候停：pr-watch 不會把 thread 標成已解決，所以只要有 inline 留言，exit 3 就會一直在。(a) 剩下的 hits 都只有使用者能處理時（待確認的 thread、待 push 的 commit、閘門），就送通知並停止，等使用者處理完再重新啟動 (b) 繼續盯，直到 24 小時或輪數上限。建議 (a)：一直盯著一個只能等人處理的狀態，只是在花錢。
- [default] pr-watch 永遠不合併、不把 thread 標成已解決、不刪分支、不在 GitHub 上留言或回覆。合併仍走 `pr-closeout` skill，由使用者說 merge 才做。
- [default] 只跑 `/review-pr` 的第 1、2 步（抓取、分類、產出 `review-pr-comments.json` 和分類表）。它的第 3、4 步會 commit、push、在 PR 上留言、回覆並標成已解決，和上一條衝突，由 pr-watch 自己的本機 commit 流程取代。
- [default] 「新留言」由 pr-watch 自己比對：key 是端點＋留言 id＋`updated_at`，所以就地編輯的留言也算新的；body 為空的 review 不算。這是留言的比對，不是另一套「能不能合併」的判斷，合併判斷仍完全由 `ready` 負責。
- [default] 帳本沿用目前的工作範圍帳本，用 `add` 追加（盯自己 PR 的審查結果，屬於同一條工作線的「修審查結果」），不另開 harvest 帳本；沒有帳本就先 `init`。只有確實出現新留言的那一輪才呼叫 `/review-pr`，免得每輪都讓 `review_rounds` 加一。
- [default] 衝突、changes-requested、behind、blocked-unseen、draft、查詢失敗（exit 7，包括某個端點達到 100 則留言）只回報，不自己處理，和 `pr-closeout` 的規定一致。回報衝突或 behind 時附上 `baseBehind`。
- [default] 允許的 PR head 是「監看開始時的 SHA」加上「pr-watch 自己建立、經使用者同意 push 的 commit」。head 不在這個集合裡就回報並停止（有人從別處推了 commit）。
- [default] `ready` 回 exit 0 但這一輪有新留言時，先處理留言，不停止。head 改變之後，要等新 head 的 check 都跑完，才判斷能不能合併（`claude[bot]` 會重新審查）。
- [default] 停止條件：PR 已合併或已關閉；只剩使用者能處理的事項（依上面的決定）；head 不在允許集合裡；沒有進展（連續兩輪 `hits` 的條件和詳細內容都相同，且這兩輪之間本機和遠端都沒有新 commit，也沒有新留言）；使用者說停；監看超過 24 小時或 60 輪。時間從狀態檔記錄的開始時間算起。
- [default] 檢查間隔：check 還在跑時約 4–5 分鐘看一次，連續兩輪沒有變化就退到 20–30 分鐘。用內建 `/loop` 的動態間隔（ScheduleWakeup）。`pr-closeout` 的 exit 5 原本用背景 until-loop 短暫等待，維持不變；長時間監看改用 pr-watch。
- [default] 停止時用 PushNotification 通知使用者，再在對話裡印出停止報告。
- [default] 一個 session 只盯一個 PR，狀態檔以 PR 為單位（沿用 `pr-closeout` 設計「不做多 PR 模式」的非目標）。
- [default] 推翻 `pr-closeout` 設計文件的非目標「不做輪詢或等待模式」的方式：腳本仍然每次查完就結束、不保留狀態，輪詢放在 skill 這一層。設計文件的非目標當時寫的就是「等待由呼叫端處理」，pr-watch 就是那個呼叫端。設計文件補一句說明。
- [default] 留言內容會進入模型的 context，這是「LLM context 組裝」類的高風險功能。Phase 2 的 design.md 要寫 threat model（誰攻擊、做什麼、拿到什麼、STRIDE 分類）。
- [default] 只支援 GitHub（沿用 `pr-closeout.mjs`）。使用者的 repo 都在 GitHub。
- [default] pr-watch 放在 `pr-closeout` plugin 裡，不另開 plugin：它直接讀同一支腳本的輸出，兩者的版號和測試應該一起變動。

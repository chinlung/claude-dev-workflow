# Proposal: pr-watch-state-ack-hardening

## Why

pr-watch 在 #75 的審查（`scoped-rereview@r7` 的 M-a、`final-review@r3` 的 M5）留下兩個小缺口。這個 change 修 M-a；M5 經量測與獨立審查後決定不做（見下）。

**M-a：狀態檔版本不符時，`watch --stop` 清不掉。** `loadState` 對版本不是 1 的狀態檔一律丟錯（`pr-closeout.mjs:546`），`watch --stop` 在讀檔那一步就失敗（exit 7），走不到 `s.active = false`；但防護 hook 用正規式直接讀整份檔案的 `"active": true`，不看版本，所以會一直擋 GitHub 寫入。pr-watch SKILL 在 exit 7 時叫模型「跑 `watch --stop` 把狀態設為停止」（`SKILL.md:38`），遇到這種檔案這條路走不通。只有手改或較新版本的腳本寫的檔案會遇到，所以是 LOW；現況脫困靠 hook 訊息提的「手動把 `"active"` 改成 false」。

單純放寬 `--stop`（讀不懂也照停）不能解：`SKILL.md:38` 會在 exit 7 時自動跑它，舊版 session 就會無聲停掉另一個 session 用較新版本進行中的監看；而且只改最上層的 `active`，未來格式若在別處也有 `"active": true`，hook 仍會擋。

**M5（不做）：`/review-pr --triage-only` 只收裸 id。** GitHub 的三個留言 endpoint（`pulls/comments`、`pulls/reviews`、`issues/comments`）各有 id；`watch` 的 key 是 `<endpoint>:<id>:<雜湊>`，但 pr-watch SKILL 取中間的 id 傳給 `/review-pr`，它用裸 id 在三個 endpoint 的合併清單裡比對，理論上撞號會多分類一則不相關的留言。`watch-ack` 本身已用完整 key，不受影響。

撞號機率（2026-11-27 量測與獨立審查）：三個 endpoint 是**各自單調遞增的計數器**，不是共用序列——PR #9 在 2026-10-07T16:21:48Z 同一秒建立的 review 是 5445186518、review comment 是 4209291886，相差約 12 億。撞號只在同一個 PR 內才有意義：落後的計數器要剛好走到領先的那個值，各計數器每天約增加 1.5e7–2e7，所以兩則留言須相隔數十天以上，還得剛好命中同一個值。本 repo 77 個 PR、88 個 id 跨 endpoint 重複 0，但 id 分散在各 PR，PR 內可比對的配對幾乎沒有，這個 0 本身不算證據；結論靠的是上面的時間結構。GitHub 文件沒有保證數字 id 跨型別唯一。就算撞了，後果是分類表多一則或錯一則，使用者在確認分類表時看得到。三條路的代價都大於它防的事：(a) 讓 `--triage-only` 收 `<endpoint>:<id>` 要處理兩個 plugin 版本錯開（新 pr-closeout 配舊 code-audit-rigor 時，舊版不認 `issues/comments:123`、一則都不留，接著 `watch-ack` 照樣標成已處理，留言無聲漏掉），還得加最低版本要求與「分類表沒涵蓋全部 key 就不 ack」；(c) 改用帶型別前綴的 `node_id`（`IC_…`、`PRR_…`、`PRRC_…`）最乾淨，但 `seen` 的 key 格式要變，狀態檔要升版本，正好是 M-a 要處理的情況。

## What Changes

- `pr-closeout` 遇到本腳本讀不懂的狀態檔（版本、欄位或型別不符，或不是 JSON）時，`watch`、`watch --start`、`watch --stop`、`watch-ack` 仍拒絕（exit 7），但訊息改以 `foreign-state:` 開頭，並指出 `watch --stop --force` 與升級 plugin 兩條出路。
- 新旗標 `watch --stop --force`：把狀態檔改名移開（`pr-watch.<pr>.local.json` → `foreign-pr-watch.<pr>.<時間>.local.json`，不再符合防護 hook 的 glob `pr-watch.*.local.json`，仍以 `.local.json` 結尾所以既有的忽略規則涵蓋它），位元組不動，exit 0，輸出註明新檔名。`--force` 只能與 `--stop` 並用。
- pr-watch SKILL 遇到 `foreign-state` 時不自動停止，改回報使用者：那可能是另一個 session 用較新版本在監看。
- README、CHANGELOG 同步；pr-closeout 1.3.0 → 1.4.0、marketplace 1.24.0 → 1.25.0。
- M5 不改程式：把「不做」的理由寫進 follow-ups。

## Capabilities

### Modified Capabilities
- `pr-watch`：新增「讀不懂的狀態檔一律拒絕並指出出路」與「強制停止把讀不懂的狀態檔移開」兩條需求，既有需求不變。

## Impact

- `plugins/pr-closeout/scripts/pr-closeout.mjs`（`watchCli` 的 `--stop` 路徑、`loadState` 的錯誤訊息與註解）、`plugins/pr-closeout/tests/`（watch 套件）、`plugins/pr-closeout/skills/pr-watch/SKILL.md`、`plugins/pr-closeout/README.md`、`plugins/pr-closeout/README.zh-TW.md`、`plugins/pr-closeout/CHANGELOG.md`、`plugins/pr-closeout/.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`、根目錄 `CHANGELOG.md`、`CHANGELOG.zh-TW.md`
- 不碰 `pr-watch-guard.sh`、`hooks.json` 與 code-audit-rigor；第三項（guard 的內容誤擋）本次不做，留在 follow-ups。
- change 名稱含 `ack-hardening` 是開 change 時 M5 還在範圍內，M5 撤出後名稱不改，歸檔後以目錄名查也不影響。

## Decisions

- [default] M5 不做（使用者 2026-11-27 裁定）：理由見 Why，關成 won't-fix 寫進 follow-ups。
- [default] 讀不懂的狀態檔要 `--stop --force` 才停（使用者 2026-11-27 裁定），一般 `--stop` 仍拒絕，SKILL 不自動加 `--force`：避免舊版 session 無聲停掉另一個 session 用較新版本進行中的監看。
- [default] `--force` 用改名移開狀態檔，不改寫內容：改寫只改最上層 `active`，未來格式若在別處也有 `"active": true`，hook（整份檔案比對文字）仍會擋；parse 再 stringify 也做不到位元組不變（超過 2^53 的整數失精度、重複 key 合併）。改名後 hook 的 glob 不再命中，原檔完整留著供新版或人工讀回。
- [default] `--force` 不檢查檔案內的 `pr` 欄位：路徑本身以 PR 號碼命名，`--force` 只認路徑。
- [default] 只有 `--stop` 有 `--force`；`watch --start`、一輪 `watch`、`watch-ack` 遇到讀不懂的檔案照舊拒絕、不重建（`pr-closeout.mjs:539-540` 的「refused, never rebuilt」對它們仍成立，註解改寫成涵蓋 `--force` 的例外）。
- [default] 版本號：pr-closeout 1.3.0 → 1.4.0（`--force` 是新旗標）；marketplace 1.24.0 → 1.25.0。

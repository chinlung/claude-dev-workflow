# Proposal: pr-watch-guard-segments

## Why

pr-watch 的防護 hook（`plugins/pr-closeout/hooks/pr-watch-guard.sh`）判斷 `gh api` 是不是寫入時，只要整行某處有 `-X GET`，同一行每個 `gh api` 的欄位與 `--input` 都放行。例如 `gh api -X GET … | cat; gh api …/comments -f body=x` 會過關；`-f 'body= -X GET'` 這種值裡的 GET 也一樣。漏擋寫入的代價高於多擋一次讀取，所以要修這一側。

2026-11-26 用 572 份 transcript 裡的 317 條 `gh api` 命令（373 次呼叫）重放 guard：

- 誤放：語料裡沒有實際發生，陽性對照確認量測抓得到；但前提「一行有兩個以上 `gh api`、其中一個帶 `-X GET`」自然出現了 11 條。
- 另一個方向的誤擋（別的命令的 `-f`、`-x` 被當成 `gh api` 旗標，例如 `| cut -f1`）：373 次呼叫中 1 次。

另一個方向的誤擋要把寫入訊號限制在每個 `gh api` 所在的命令段內才能解，而那需要一個永遠不比 bash 早看到邊界的 shell 解析器：切段掃描器在引號內的 GET、`$( )` 與 `xargs` 帶進來的欄位、巢狀的括號與反引號上，都有讓寫入漏出段外的寫法。所以寫入訊號照舊看整行，只縮小 GET 的範圍（使用者裁定）；另一個方向的誤擋接受下來，併入內容誤擋的延後項。

## What Changes

- 防護 hook 的 `gh api` 欄位與 `--input`：除非同一行每個 `gh api` 在自己的參數裡各有一個不在引號內、未被跳脫的 `-X GET` 或 `--method GET`（位於第一個分隔符、引號、反斜線與註解之前），否則視為寫入。方法旗標、GraphQL mutation 與其他規則（`resolveReviewThread` 等字、`/replies`、`gh pr|issue comment|review`、curl／wget 對 github.com）仍看整行。
- 反斜線加換行先拿掉，與 bash 一致。
- 名稱被引號或反斜線拆開的 `gh api`（`"g"h api`）與整行視圖找到的 `gh api` 個數對不上時擋下；欄位要放行，整行視圖也必須看得到 GET，所以本版放行的命令必然是 1.2.0 放行的子集。
- `pr-closeout` 1.2.0 → 1.2.1，marketplace 1.23.0 → 1.23.1。

## Capabilities

### New Capabilities

### Modified Capabilities
- `pr-watch`：新增一條需求，規定防護 hook 只讓 `gh api` 自己的 GET 放行它的欄位與 `--input`。既有需求的文字不變。

## Impact

- `plugins/pr-closeout/hooks/pr-watch-guard.sh`
- `plugins/pr-closeout/tests/pr-watch-guard.test.sh`
- `plugins/pr-closeout/CHANGELOG.md`、`CHANGELOG.md`、`CHANGELOG.zh-TW.md`
- `plugins/pr-closeout/.claude-plugin/plugin.json`、`.claude-plugin/marketplace.json`
- `plugins/pr-closeout/README.md`、`README.zh-TW.md`：guard 說明段落

## Decisions
- 只縮 GET 的範圍，寫入訊號照舊看整行：這是使用者裁定的選項（三輪安全審查都找到逐段切分的繞法）。代價是別的命令的旗標（`gh api … | cut -f1`）仍會被誤擋。
- 別的命令的旗標誤擋，與 heredoc、perl／node 程式本文、文件文字裡出現 `gh pr review`、`/replies` 這些字就擋的內容誤擋，合併成同一個延後項（去處 follow-ups）。兩者都要靠辨認命令位置才能解，又會與「擋直譯器字串內的寫入」這條刻意規則衝突。
- 引號、反斜線、`#` 註解都截斷 GET 的範圍：帶引號的端點寫在 `-X GET` 之前（`gh api "repos/…" -X GET -f …`）因此被擋。接受這個代價，不用局部解析換回來。
- 版本走 patch（1.2.0 → 1.2.1）：hook 行為修正，沒有新功能。

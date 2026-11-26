# Proposal: pr-watch-guard-segments

## Why

pr-watch 的防護 hook（`plugins/pr-closeout/hooks/pr-watch-guard.sh`）判斷一個 `gh api` 呼叫是不是寫入時，拿的是整行命令：只要整行某處有 `-X GET`，同一行任何 `gh api` 的欄位都會放行；只要整行某處有 `-f`、`-x`，就算它屬於 `cut -f1`、`bash -x`，也會被當成 `gh api` 的旗標。前者讓寫入過關，後者擋掉讀取。

2026-11-26 用 572 份 transcript 裡的 317 條 `gh api` 命令（373 次呼叫），在監看中的狀態下重放 guard：

- 誤擋：只有 1 條屬於這一類（`gh api … --jq … | tail -1; … | cut -f1`）。
- 誤放：沒有實際發生。陽性對照確認量測抓得到這種誤放。但它的前提「一行有兩個以上 `gh api`、其中一個帶 `-X GET`」自然出現了 11 條，只要其中一段換成寫入就會過關。

漏擋寫入的代價高於多擋一次讀取，所以這次修 `gh api` 的判斷範圍。使用者已裁定：範圍只到這裡（選項 B）。

## What Changes

- 防護 hook 判斷 `gh api` 的方法（`-X`／`--method`）、欄位（`-f`、`-F`、`--field`、`--raw-field`）與 `--input` 時，只看該 `gh api` 所在的命令段。
  - 命令段的邊界是不在引號內的管線、命令串接與換行。
  - 引號內的 `|`（例如 `--jq '.[] | .id'`）不切段，否則寫在 jq 之後的欄位會漏判。
- 其他規則仍看整行，與現在相同：
  - 命令裡出現 `resolveReviewThread` 等字
  - `/replies` 端點
  - `gh pr|issue comment|review`
  - curl／wget 對 github.com
  - GraphQL mutation
- `pr-closeout` 1.2.0 → 1.2.1，marketplace 1.23.0 → 1.23.1。

## Capabilities

### New Capabilities

### Modified Capabilities
- `pr-watch`：新增一條需求，規定防護 hook 對 `gh api` 的方法、欄位與 `--input` 逐段判斷。既有需求的文字不變。

## Impact

- `plugins/pr-closeout/hooks/pr-watch-guard.sh`
- `plugins/pr-closeout/tests/pr-watch-guard.test.sh`
- `plugins/pr-closeout/CHANGELOG.md`
- `plugins/pr-closeout/.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `plugins/pr-closeout/README.md`、`plugins/pr-closeout/README.zh-TW.md`：只在描述 guard 判斷範圍的段落需要同步時才改。

## Decisions
- [default] 只改 `gh api` 的方法、欄位與 `--input` 的判斷範圍，其他規則照舊看整行。這是使用者裁定的選項 B。
- [default] 引號內的分隔符不切段。若照字面切，`--jq '.[] | .id' -f body=x` 的 `-f` 會落到另一段而被漏判，新增一條誤放路徑。
- [default] 內容誤擋不在本次範圍，已記進帳本 Deferred，去處是 follow-ups。內容誤擋指 heredoc、perl／node 程式本文、文件文字裡出現 `gh pr review`、`/replies` 這些字就擋，量測的 60 條非 curl 擋下中佔 45 條。它要辨認命令位置才能解，又會和「擋直譯器字串內的寫入」這條刻意規則衝突。
- [default] 版本走 patch（1.2.0 → 1.2.1）：這是 hook 行為修正，不加新功能。plugin 沒 bump 版號時，已安裝的副本不會更新。

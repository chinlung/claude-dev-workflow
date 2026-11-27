# Design: pr-watch-state-ack-hardening

## Context

pr-watch 把一段監看的狀態存在 `<repo>/.claude/pr-watch.<pr>.local.json`，只有 `pr-closeout.mjs` 的 `watch`、`watch-ack` 會寫。兩個讀它的地方判斷方式不同：

- 腳本的 `loadState`（`pr-closeout.mjs:541`）逐欄驗證，版本不是 `STATE_VERSION`（1）、`pr` 不符、欄位型別不對、或不是 JSON，一律丟 `QueryError`，`main` 轉成 exit 7。`watch`、`watch --stop`、`watch-ack` 都先過它。
- 防護 hook（`pr-watch-guard.sh:36-38`）對 `.claude/pr-watch.*.local.json` 的每個檔案，用正規式比對整份文字有沒有 `"active": true`，不看版本。

所以版本不符的檔案若寫著 `"active": true`，腳本拒絕處理、hook 照擋，而 `SKILL.md:38` 叫模型在 exit 7 時跑 `watch --stop`，那個命令正是被拒絕的那個。現況的脫困是 hook 訊息裡的「手動把 `"active"` 改成 false」。

事實查證（2026-11-27）：
- `git check-ignore`：`.gitignore` 的 `*.local.json` 涵蓋 `foreign-pr-watch.7.<時間>.local.json`，不涵蓋 `pr-watch.7.local.json.foreign-x`。
- 沒有其他程式讀 `pr-watch.*` 檔：`statePath` 只被 `watchCli`（:681）與 `watchAck`（:725）用，`readdirSync`（:213）是別的用途。

## Goals / Non-Goals

**Goals**
- 讀不懂的狀態檔不再讓 hook 永遠擋、使用者又沒有明確的指令可以解。
- 一般的停止與其他命令遇到讀不懂的狀態檔時仍然拒絕，不重建、不改寫，也不讓 pr-watch 自己決定停掉別人的監看。

**Non-Goals**
- M5（`--triage-only` 只收裸 id）：2026-11-27 裁定不做，理由在 proposal。
- 不改狀態檔格式與 `STATE_VERSION`；不碰 `pr-watch-guard.sh` 與 `hooks.json`；guard 的內容誤擋留在 follow-ups。
- 不處理 `watch` 與 `watch-ack` 之間的鎖、`saveState` 的 I/O 錯誤（既有的 won't-fix）。

## Approaches

考慮過的做法：

| 方案 | 取捨 | 結論 |
|---|---|---|
| A. 放寬 `--stop`：讀不懂也只改 `active` | 改寫只動最上層，未來格式若別處也有 `"active": true`，hook 仍擋；parse 再 stringify 做不到位元組不變；SKILL 在 exit 7 時自動跑它，舊版 session 會無聲停掉較新版本的監看 | 否 |
| B. 新旗標 `--stop --force`：把檔案改名移開 | 位元組不動、hook 的 glob 不再命中、只有明確要求才發生；多一個旗標 | **採用** |
| C. pr-watch 遇到 exit 7 自動停 | 與 A 同一個無聲停掉別人監看的問題 | 否 |
| D. 不改，維持手動改檔 | 零成本；但 SKILL 指向一條走不通的路，使用者看到的是反覆被擋 | 否 |
| 前例：ralph-loop 的 cancel 直接 `rm` 狀態檔 | 簡單，但丟掉 `seen`，已處理過的留言會重新出現 | 否，改名保留原檔 |

## Decisions

### D1：把「讀不懂」做成一個可辨認的錯誤

`loadState` 內所有驗證失敗（含 `parse` 的 JSON 錯誤）改丟 `ForeignStateError extends QueryError`，訊息一律以常數 `FOREIGN_STATE = 'foreign-state'` 開頭：

```
foreign-state: state <file>: <why>; upgrade the plugin, or run `watch --stop --force` to move it aside
```

`main` 的處理不用變（它已把 `QueryError` 的 message 放進 `hits[0].detail`、exit 7）；SKILL 靠 `detail` 的開頭辨認，與它現有的 `too-soon`、`stopped` 同一個慣例。`FOREIGN_STATE` 匯出，docs 測試用它去 grep SKILL，兩處不各寫一份字面值。

`pr` 欄位與檔名不符也算讀不懂（檔名以 PR 號碼定位，裡面卻是別的 PR 的狀態）。

### D2：`--force` 是 `watch --stop` 專用的布林旗標

`parseArgs` 加 `--force`：只允許 `cmd === 'watch'` 且同時有 `--stop`，否則 `UsageError`（exit 7，訊息一律是 `--force is for watch --stop only`，不論搭配的是 `ready`、`landed`、`watch-ack` 或 `watch --start`）。`--start` 與 `--stop` 同時出現的互斥檢查（`--start and --stop together`）也在 `parseArgs`：它必須早於讀任何狀態檔，否則讀不懂的狀態檔搭配 `--start --stop --force` 會在互斥檢查之前就被移開。

### D3：`watchCli` 的 `--stop --force` 路徑

```
try { s = loadState(file, o.pr) }
catch (e) { if (o.stop && o.force && e instanceof ForeignStateError) return moveAside(file, o); throw e }
```

- 狀態檔不存在：`loadState` 回 null，走原本的 `not-started`（沒有東西可移）。
- 狀態檔讀得懂：`--force` 不起作用，照一般 `--stop`（`active` 設為 false、檔案留在原處、`seen` 保留）。`--force` 只為讀不懂的檔案存在，不能變成「丟掉一份好的狀態」的捷徑。
- `moveAside(file, o)`：目的地 `path.join(dirname(file), 'foreign-pr-watch.<pr>.<時間>.local.json')`，時間取 `o.now ?? new Date()` 的 ISO 去掉 `-`、`:`、毫秒（例 `20261127T012044Z`）。名稱以 `foreign-` 開頭，所以不符合 hook 的 `pr-watch.*.local.json`；以 `.local.json` 結尾，所以專案既有的 `*.local.json` 忽略規則涵蓋它。目的地是否已被占用以 `fs.lstatSync` 判斷（懸空的 symlink 也算占用；`existsSync` 會跟隨連結，把懸空連結當成不存在，`renameSync` 就會把它換掉），占用就拒絕（`QueryError`），不覆蓋——`renameSync` 在 POSIX 上會無聲覆蓋。`renameSync` 丟出的 I/O 錯誤包成 `QueryError('could not move … aside: …')`，exit 7，不讓例外外洩成堆疊。
- 回傳 `{ exit: 0, gate: null, hits: [], watch: { active: false, movedAside: <新路徑> } }`，與正常 `--stop` 的形狀一致（多一個欄位）。

`loadState` 的註解（:539-540「refused, never rebuilt」）改寫成：讀不懂的狀態只有 `watch --stop --force` 能動，而且是移開、不是改寫。

### D4：pr-watch SKILL

`SKILL.md` 的 exit 7 處理（:38）在「其他情況」之前加一條：`detail` 以 `foreign-state` 開頭時，**不跑任何停止命令**，把 `detail` 告訴使用者（可能有另一個 session 用較新版本在監看；選項是升級 plugin，或由使用者明說後執行 `watch --stop --force`），用 `ScheduleWakeup stop: true` 結束迴圈。`watch-ack` 遇到 `foreign-state` 同樣回報，不重試。SKILL 不得自行加 `--force`。

### D5：測試

加在 `pr-closeout.test.sh` 的 watch 區段（沿用其 fixture 與突變機制）與 `pr-watch-docs.test.sh`：

1. `"version": 2`、`"active": true`：`watch --stop` → exit 7、`detail` 以 `foreign-state` 開頭、檔案位元組不變（sha 比對）。
2. 同一份加 `--force` → exit 0、原路徑不存在、新檔存在且位元組與原檔相同、新檔名符合 `foreign-pr-watch.<pr>.*.local.json` 並**不符合** `pr-watch.*.local.json`。
3. 不是 JSON（如 `{`、陣列、空檔）加 `--force` → 同樣移開。
4. `pr` 欄位與檔名不符加 `--force` → 移開。
5. 讀得懂的狀態加 `--force` → 一般停止：檔案在原處、`active` false、`seen` 不變、輸出無 `movedAside`。
6. 讀不懂的檔案上 `--start`、一輪 `watch`、`watch-ack` → exit 7、`foreign-state`、檔案位元組不變；拒絕訊息以 `foreign-state:` 開頭，並同時指出 `--stop --force` 與 `upgrade the plugin`。
7. `--force` 搭 `--start`／`ready`／`landed`／`watch-ack`／沒有 `--stop` 的 `watch` → exit 7、訊息 `--force is for watch --stop only`；`--start --stop --force` 遇到讀不懂的狀態檔 → exit 7、訊息 `--start and --stop together`、檔案不動。
8. 沒有狀態檔加 `--stop --force` → `not-started`。
9. 目的地已存在（用 `--now` 固定時間，預先建好同名檔；另測目的地是懸空 symlink）→ 拒絕、原檔不動、既有的檔或連結不變。
10. **接線測試**：用 guard 套件的方式在同一個暫存目錄跑 `pr-watch-guard.sh`：`"active": true` 的讀不懂狀態檔 → guard 擋；`--stop --force` 之後 → guard 放行。這證明「新檔名不被 glob 命中」是 hook 的實際行為，不只是字串斷言。
11. docs：SKILL 提到 `foreign-state`（用匯出的 `FOREIGN_STATE`）與「不自動加 `--force`」；README 兩個語言版本提到 `--stop --force`。

突變（沿用套件的 red 計數）：`f-class`（拿掉 `instanceof ForeignStateError` 判斷）、`f-overwrite`（移開時不檢查目的地）、`f-prefix`（改名不改檔名前綴，讓 glob 命中）、`f-usage`（拿掉 `parseArgs` 的 `--force` 用法檢查）、`f-usage-cmd`（拿掉 `--force` 對非 `watch` 命令的檢查）、`f-json`（JSON 解析失敗不算 foreign）——每一個都必須讓指定的案例最先變紅。「讀得懂的檔案也被移開」沒有做成永久突變，由「讀得懂的狀態加 `--force` 留在原處」那個案例守住。

### D6：文件與版本

`README.md`、`README.zh-TW.md` 的 pr-watch 一節加：讀不懂的狀態檔、`foreign-state` 與 `--stop --force`；`CHANGELOG.md` 1.4.0 一條（`--force` 是新旗標，所以 minor）；`plugin.json` 1.4.0；`marketplace.json` 1.25.0，根目錄兩份 CHANGELOG 同步。

## Risks / Trade-offs

- **威脅模型**：防護 hook 本來就是絆線不是邊界（#75 的裁定）——同一個行為者可以直接編輯狀態檔的 `active`。`--force` 沒有增加任何能力：它做的事（讓 hook 不再擋）用編輯器本來就做得到，只是變成一個有名字、有記錄（輸出 `movedAside`）的動作。被 prompt injection 的模型若自己下 `--stop --force`，效果等於它自己改檔；防的是 SKILL 流程自動走這條路（D4），不是防模型。
- **紅旗 6（同一件事兩種做法）**：停止現在有 `--stop`（讀得懂）、`--stop --force`（讀不懂）、手改檔案（hook 訊息仍提供）。保留：前兩者前提互斥，不重疊；手改是 hook 訊息既有的最後脫困，guard 不在本次範圍。
- **紅旗 2／8（同一個決定在兩處）**：hook 的 glob 與新檔名前綴是耦合的，改其中一個會悄悄讓另一個失效。以 D5 第 10 項的接線測試把耦合變成會叫的；不抽共用常數，因為 hook 是 bash、腳本是 Node，沒有共用的地方。
- **紅旗 5（分裂的擁有權）**：狀態檔仍只有 `pr-closeout.mjs` 會動（寫、改名），沒有第二個 writer。
- **`--start` 在移開後重新開始**：新的一段不帶舊的 `seen`，已處理過的留言會重新被當成新留言。這是 `--force` 的已知代價，訊息與文件寫明；使用者若要保留，應升級 plugin 而不是強制。
- 已知限制：時間戳只到秒，同一秒內第二次移開會因目的地已存在而被拒絕（D3）；實務上原檔已被移走，第二次根本找不到要移的檔案。

## Minor Decisions

- `--force` 的輸出欄位叫 `watch.movedAside`，值是移開後的路徑（相對於傳入的 `--repo-dir`）：不另設布林。
- 讀得懂的狀態檔加 `--force` 不報錯、不警告，照一般停止：多一個警告欄位換不到什麼，使用者看輸出沒有 `movedAside` 就知道沒移。
- 目的地已被占用時拒絕而不是加序號：這情況實務上不會發生，序號邏輯是沒人用的分支。
- 時間戳取 `--now`（有給時）否則現在：沿用 `watch` 既有的測試用時間注入。

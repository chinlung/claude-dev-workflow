## ADDED Requirements

### Requirement: 讀不懂的狀態檔一律拒絕並指出出路
`pr-closeout` 遇到本腳本讀不懂的狀態檔（版本、欄位或型別不符，或不是 JSON 物件）時，`watch`、`watch --start`、`watch --stop` 與 `watch-ack` MUST 拒絕（exit 7）、不改動檔案，且拒絕訊息 MUST 以 `foreign-state:` 開頭，並指出 `watch --stop --force` 與升級 plugin 兩條出路。pr-watch MUST NOT 在 `foreign-state` 時自行停止監看，MUST 改回報使用者，由使用者決定是否強制停止。

#### Scenario: 較新版本的狀態檔
- **WHEN** 狀態檔是 `"version": 2`、`"active": true`，執行 `watch --stop`
- **THEN** 拒絕（exit 7），訊息以 `foreign-state:` 開頭並指出 `--stop --force`，狀態檔不變，防護 hook 照樣擋

#### Scenario: 其他命令也拒絕
- **WHEN** 同一份狀態檔，執行 `watch --start`、一輪 `watch` 或 `watch-ack`
- **THEN** 拒絕（exit 7），訊息以 `foreign-state:` 開頭，狀態檔不變

#### Scenario: pr-watch 遇到讀不懂的狀態檔
- **WHEN** pr-watch 執行一輪時得到 `foreign-state` 的拒絕
- **THEN** 不跑 `--stop` 或 `--stop --force`，回報使用者可能有另一個版本在監看，結束迴圈

### Requirement: 強制停止把讀不懂的狀態檔移開
`watch --stop --force` 遇到讀不懂的狀態檔時，MUST 把該 PR 的狀態檔改名移開，並以 exit 0 結束、在輸出中註明新檔名。新檔名 MUST 不再符合防護 hook 讀取的 `pr-watch.*.local.json`，且 MUST 仍以 `.local.json` 結尾，讓專案既有的 `*.local.json` 忽略規則涵蓋它；檔案位元組 MUST 不變，目的地已存在時 MUST 拒絕而不覆蓋。`--force` MUST 只能與 `watch --stop` 一起使用。`--force` 遇到讀得懂的狀態檔時，MUST 照一般 `--stop` 處理（把 `active` 設為 false，不移動檔案）。

#### Scenario: 使用者要求強制停止
- **WHEN** 狀態檔是 `"version": 2`、`"active": true`，使用者要求停止，執行 `watch --stop --force`
- **THEN** exit 0，狀態檔被改名移開、內容不變，輸出註明新檔名，防護 hook 不再擋

#### Scenario: 讀得懂的狀態檔加 --force
- **WHEN** 狀態檔讀得懂、`"active": true`，執行 `watch --stop --force`
- **THEN** 照一般 `--stop` 處理：`active` 變成 false，檔案留在原處，`seen` 保留

#### Scenario: 不是 JSON 的狀態檔
- **WHEN** 狀態檔內容不是 JSON 物件，執行 `watch --stop --force`
- **THEN** 同樣改名移開，exit 0

#### Scenario: --force 搭配其他命令
- **WHEN** 執行 `watch --start --force`、`watch-ack … --force` 或 `ready … --force`
- **THEN** 拒絕（exit 7），訊息指出 `--force` 只能與 `watch --stop` 一起使用

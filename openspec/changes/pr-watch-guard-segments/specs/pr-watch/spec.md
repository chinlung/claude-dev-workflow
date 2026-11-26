# Spec Delta: pr-watch

## ADDED Requirements

### Requirement: 防護 hook 逐段判斷 gh api 的方法與欄位
有 PR 正在監看時，防護 hook 判斷一個 `gh api` 呼叫是不是寫入，MUST 只看這個呼叫所在的命令段。命令段從 `gh api` 開始，到下一個不在引號內的管線、命令串接或換行為止。別段的 `-X GET` MUST NOT 讓這一段的欄位、`--input` 或非 GET 方法過關；別段的 `-f`、`-x` 等旗標 MUST NOT 被當成這個 `gh api` 的旗標。引號內的分隔符 MUST NOT 切段。

#### Scenario: 前一段的 GET 不放行後一段的欄位寫入
- **WHEN** 有 PR 正在監看，模型執行 `gh api -X GET repos/o/r/pulls/7 | cat; gh api repos/o/r/issues/7/comments -f body=x`
- **THEN** 防護 hook 擋下這個命令

#### Scenario: 別段的旗標不算 gh api 的旗標
- **WHEN** 有 PR 正在監看，模型執行 `gh api repos/o/r/pulls/7 --jq .head.sha | cut -f1`
- **THEN** 防護 hook 不擋這個命令

#### Scenario: 引號內的管線不切段
- **WHEN** 有 PR 正在監看，模型執行 `gh api repos/o/r/issues/7/comments --jq '.[] | .id' -f body=x`
- **THEN** 防護 hook 擋下這個命令

#### Scenario: 同一段的 GET 仍放行查詢參數
- **WHEN** 有 PR 正在監看，模型執行 `gh api -X GET repos/o/r/pulls/7/comments -f per_page=100`
- **THEN** 防護 hook 不擋這個命令

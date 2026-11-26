# Spec Delta: pr-watch

## ADDED Requirements

### Requirement: 防護 hook 只讓 gh api 自己的 GET 放行欄位
有 PR 正在監看時，防護 hook MUST 把 `gh api` 的欄位（`-f`、`-F`、`--field`、`--raw-field`）與 `--input` 視為寫入，除非同一行的每個 `gh api` 都在自己的參數裡帶著 `-X GET` 或 `--method GET`。這個 GET MUST 是該 `gh api` 自己的參數：不在引號內、沒有被跳脫、位於它之後第一個分隔符（`|`、`;`、`&`、`(`、`)`、反引號、換行）與註解之前。別的命令的 GET、引號或跳脫文字裡看起來像 GET 的字、註解裡的 GET，MUST NOT 讓欄位或 `--input` 過關。方法旗標仍看整行：任何一個不是 GET 就擋。反斜線加換行 MUST 先拿掉，與 bash 一致。名稱被引號或反斜線拆開的 `gh api`（`"g"h api`），MUST 與正常寫法同樣判斷，判斷不出來時 MUST 擋下。

#### Scenario: 前一段的 GET 不放行後一段的欄位寫入
- **WHEN** 有 PR 正在監看，模型執行 `gh api -X GET repos/o/r/pulls/7 | cat; gh api repos/o/r/issues/7/comments -f body=x`
- **THEN** 防護 hook 擋下這個命令

#### Scenario: 引號裡的 GET 是值，不是參數
- **WHEN** 有 PR 正在監看，模型執行 `gh api repos/o/r/issues/7/comments -f 'body= -X GET'`
- **THEN** 防護 hook 擋下這個命令

#### Scenario: 註解裡的 GET 不算
- **WHEN** 有 PR 正在監看，模型執行 `gh api repos/o/r/issues/7/comments -f body=x # -X GET`
- **THEN** 防護 hook 擋下這個命令

#### Scenario: 名稱被拆開的 gh api 照樣判斷
- **WHEN** 有 PR 正在監看，模型執行 `"g"h api repos/o/r/issues/7/comments -f body=x`
- **THEN** 防護 hook 擋下這個命令

#### Scenario: 自己的 GET 放行查詢參數
- **WHEN** 有 PR 正在監看，模型執行 `gh api -X GET repos/o/r/pulls/7/comments -f per_page=100`
- **THEN** 防護 hook 不擋這個命令

#### Scenario: 續行上的 GET 照樣算
- **WHEN** 有 PR 正在監看，模型執行 `gh api repos/o/r/pulls/7/comments` 加反斜線換行，把 `-X GET` 與 `-f per_page=100` 寫在後面的續行上
- **THEN** 防護 hook 不擋這個命令

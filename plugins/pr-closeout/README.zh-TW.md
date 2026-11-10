# pr-closeout

[English](README.md)

把 PR 收尾從手打查詢變成讀事實：

- **合併前的 `ready`。** 從 GitHub 讀出 PR 能不能合併，給出 fail-closed、以 exit code 表示的判定。
- **合併後的 `landed`。** 證明合併的是審過的那一版，而且分支已經清乾淨。
- **merge 閘門。** 一個 PreToolUse hook，在 Claude 執行任何 merge 之前先跑 `ready`。

## 安裝

```bash
/plugin install pr-closeout@scl-claude-plugins
```

升級後要跑 `claude plugin update pr-closeout`，因為已安裝的副本是按版本快取的。

## `ready`

```bash
node ${CLAUDE_PLUGIN_ROOT}/scripts/pr-closeout.mjs ready <owner/repo> <pr> \
  [--expect-head <sha>] [--repo-dir <path>] [--accept-unreviewed <path>=<理由>]...
```

輸出一個 JSON。所有檢查都會跑完，`hits[]` 列出全部命中的條件，exit 取其中最優先的一個。

| exit | 意思 |
|---|---|
| 0 | 可以合併 |
| 2 | 與 base 衝突 |
| 3 | 有未解決的 review thread；outdated 不算解決 |
| 4 | check 失敗、rollup 是 FAILURE 或 ERROR，或必跑的 check 沒出現 |
| 5 | 等待中：還有 check 在跑，或 GitHub 還在計算能否合併 |
| 6 | 被閘門擋住，看 `gate` |
| 7 | 查詢失敗、出現不認得的值，或用法錯誤 |

| `gate` | 意思 |
|---|---|
| `not-open`、`draft` | PR 不是開啟狀態，或是 draft |
| `changes-requested` | 有審查者要求修改 |
| `head-mismatch` | PR 的 head 不是 `--expect-head` |
| `unreviewed` | 帶 `--repo-dir` 時：有檔的這個版本，最後一輪 review-branch 沒看過 |
| `blocked-unseen` | GitHub 回報 BLOCKED，但看不出原因（例如需要 review、ruleset） |
| `behind` | base 要求分支先跟上 |

**fail-closed。** 不認得的列舉值、缺欄位、查詢失敗、清單超過 100 筆，一律回 7，絕不判為可合併。所有查詢共用一個 20 秒的總時限（`PR_CLOSEOUT_DEADLINE_MS`），讓 `ready` 在 merge 閘門 hook 的 30 秒時限內結束。

**查詢方式。** 先用 `gh api`。失敗時用 `gh auth token` 取得 token，經 stdin 交給 curl，所以 token 不會出現在命令列參數或輸出裡。

**帶 `--repo-dir`（PR 所在 repo 的本機 clone）時多兩項：**

- **審查涵蓋。** PR 新增或修改的每個檔，逐一比對 blob 與 mode，對照 review-branch 最後一次的紀錄（`<gitdir>/review-branch-last.json`，限同一個分支）。文件列在 `docsOnly`，不擋；但 `skills/`、`commands/`、`agents/`、`output-styles/`、`hooks/` 底下的 prompt 檔，以及 `requirements*.txt`、`CMakeLists.txt` 不算文件。review-branch 在較早一輪之後判定未變動而略過的檔（帶 `unchangedSince`），算已審。`--accept-unreviewed <path>=<理由>` 可以放行單一檔，理由必填。沒有紀錄、分支不同、本地沒有 head 時，`coverage.status` 為 `"unknown"`，不擋。比對的是 git 存的位元組：clone 裡 git 會在寫入時改寫內容、或不追蹤 mode（`core.autocrlf`、`core.fileMode=false`）時，review-branch 對工作樹的紀錄可能與 PR 的 blob 不同，沒人改過的檔也會被列為 `unreviewed`；這種檔用 `--accept-unreviewed` 放行，理由就寫這個。
- **openspec。** repo 有 `openspec/` 時，列出 PR 動到、但還不在 `archive/` 底下的 change，附上 `reconcile-check verify` 的結果。只是提醒。`verify` 讀的是 `--repo-dir` 工作樹裡的 change，不是 PR 的 head，所以回答的是那裡簽出的分支；它與整次執行共用同一個時限，逾時沒回答的列為 `unavailable`。

**JSON 另外附三樣資訊，不影響 exit：** `precedent`（前一個已合併的 PR 是 squash 還是 merge）、`baseBehind`、各 endpoint 的留言數與作者，以及 `suspectedSkip`（見下節）。

### 必跑 check

這是個人設定，不在本 plugin 內。腳本讀 `$PR_CLOSEOUT_CONFIG`，沒設定時讀 `~/.claude/pr-closeout/required-checks.json`：

```json
{
  "<owner>/<repo>": {
    "required": ["security-review", "tests"],
    "minSeconds": { "security-review": 30 }
  }
}
```

- **名單上的 check 沒出現**（被 paths-ignore 略過、workflow 被跳過）：回 4。
- **check 跑完的時間低於 `minSeconds`**：列在 `suspectedSkip`，因為綠勾不證明真的有跑。
- **沒有這個檔**：不檢查必跑項。**檔案讀不懂**：回 7。

## `landed`

```bash
node ${CLAUDE_PLUGIN_ROOT}/scripts/pr-closeout.mjs landed <owner/repo> <pr> \
  --expect-head <sha> --repo-dir <path> [--branch <name>]
```

檢查四件事，回 0 或 6（gate 為 `not-merged`、`head-mismatch`、`not-on-base`、`branch-remains`）；查詢或 `git fetch` 失敗回 7：

- `merged_at` 有值。
- 合併的 head 是 `--expect-head`。
- merge commit 是 `origin/<base>` 的祖先，會先 fetch 再判斷。不看原分支的 tip，因為 squash 後它永遠不會在 base 上。
- 帶 `--branch` 時：該分支沒有 open PR，遠端與本地分支也都已刪除。

## merge 閘門

`hooks/pr-merge-gate.sh` 在 Bash 命令與 GitHub MCP 的 `merge_pull_request` 之前執行。

- **攔什麼。** 命令位置上的 `gh pr merge`（號碼或 URL、`--repo`／`-R`、`--match-head-commit`）與 `gh api …/pulls/<n>/merge`，包括包在 wrapper 後面或用完整路徑呼叫的 `gh`，雙引號或未加引號的 heredoc 裡仍會執行的 `$( )`、反引號，以及交給 `bash -c`、`sh -c`、`eval` 的命令字串。
- **怎麼判。** 對那個 PR 跑 `ready`，exit 0 才放行；擋下時會附上 `ready` 查到的內容。
- **攔不到什麼。** hook 用自己的小型掃描器讀命令文字，不是 bash。它防的是代理誤打的 merge，不是刻意繞過它的命令：藏在變數或 alias 後面、寫在腳本檔裡、放在 `$'…'` 裡，或雙引號內的 `$( )` 本身又帶引號時，可能看不到。真的不能發生的合併要靠分支保護。
- **何時擋下。** 讀不出是哪個 PR 的 merge 一律擋下，包括 GraphQL 的 `mergePullRequest`。缺 jq、node 或腳本時也擋下。`--match-head-commit`（或 MCP 工具的 `sha`）不是字面的 40 碼 sha 時也擋下：hook 讀的是命令文字，變數與 `$( )` 不會展開。
- **時間。** 同一條命令裡所有 `ready` 共用 25 秒的預算（`PR_MERGE_GATE_BUDGET`），在 hook 的 30 秒時限之內；剩餘時間不夠時直接擋下，不交給逾時的 hook 決定。
- **略過。** 在命令前加 `PR_CLOSEOUT_OK=1` 可以略過一次。MCP 工具沒有略過的方式，要略過請改用 `gh`。
- **對其他命令的成本。** 不是 merge 的命令，讀進輸入（一次 `cat`）後在 shell 內建的 `case` 判斷就放行，不啟動 jq、perl 或 node。

## 測試

```bash
bash plugins/pr-closeout/tests/pr-closeout.test.sh
bash plugins/pr-closeout/tests/pr-merge-gate.test.sh
```

測試不需要網路，用 fixture 代替 GitHub 的回應。兩支套件最後都會跑突變，每個突變都必須被它對應的案例抓到才算通過。

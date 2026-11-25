# pr-closeout

[English](README.md)

把 PR 收尾從手打查詢變成讀事實：

- **合併前的 `ready`。** 從 GitHub 讀出 PR 能不能合併，給出 fail-closed、以 exit code 表示的判定。
- **合併後的 `landed`。** 證明合併的是審過的那一版，而且分支已經清乾淨。
- **merge 閘門。** 一個 PreToolUse hook，在 Claude 執行任何 merge 之前先跑 `ready`。
- **push 後的 `pr-watch`（1.2.0）。** 一個 skill，監看一個 PR 直到只剩使用者能處理的事；每一輪由 `watch` 判定，防護 hook 讓它不會寫入 GitHub。

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

**fail-closed。** 不認得的列舉值、缺欄位、查詢失敗、review thread 或 check 達 100 筆、單一端點留言超過 1000 則，一律回 7，絕不判為可合併。留言會逐頁讀取（1.2.0；之前單一端點 100 則就回 7）。所有查詢共用一個 20 秒的總時限（`PR_CLOSEOUT_DEADLINE_MS`），讓 `ready` 在 merge 閘門 hook 的 30 秒時限內結束。

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

- **名單上的 check 沒出現**（被 paths-ignore 略過、workflow 被跳過）：回 4。要讓某些 PR（例如純文件）略過必跑 check，就讓 workflow 每個 PR 都觸發，改用 job 的 `if:` 略過：被略過的 job 會回報 SKIPPED，算通過。本 repo 的 `.github/workflows/security-review.yml` 以讀 diff 的 `changes` job 這樣做。
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
- **怎麼讀。** 每條命令讀三次，任一種讀法找到的都算：掃描器的規則、註解規則之前（1.0.5）的讀法，以及 1.1.0 起照 bash 逐字讀的 lexer（`\` 接行、反引號裡的引號、雙引號內帶雙引號的 `$( )`、`$(( ))` 或 `$[ ]` 裡的 `$( )`、混合引號或以 `EOF)` 收尾的 heredoc delimiter）。新的讀法只能增加要檢查的，不會減少。
- **怎麼判。** 對那個 PR 跑 `ready`，exit 0 才放行；擋下時會附上 `ready` 查到的內容。
- **攔不到什麼。** hook 用自己的掃描器讀命令文字，不是 bash。它防的是代理誤打的 merge，不是刻意繞過它的命令：藏在變數或 alias 後面、寫在腳本檔裡、經 stdin 餵給 shell（`bash <<EOF`、`… | bash`）時可能看不到；bash 因語法錯誤丟棄的那一行上開了 heredoc 時（`a=(-( <<EOF`），其後的行也可能看不到。`gh api` 在某個選項的值裡也放了 merge 路徑時，檢查的是命令裡第一個 merge 路徑，不是 gh 實際合併的端點（`gh api -H repos/o/r/pulls/3/merge repos/o/r/pulls/5/merge` 檢查 PR 3、合併 PR 5）。真的不能發生的合併要靠分支保護。
- **何時擋下。** 讀不出是哪個 PR 的 merge 一律擋下，包括 GraphQL 的 `mergePullRequest`。缺 jq、node 或腳本時也擋下。`--match-head-commit`（或 MCP 工具的 `sha`）不是字面的 40 碼 sha 時也擋下：hook 讀的是命令文字，變數與 `$( )` 不會展開。同理（1.1.1），PR 號碼、PR 網址、repo、選項名稱或 `gh api` 端點裡夾著 `$( )`、反引號或 `${ }` 時擋下，絕不讀成它的字面部分（`gh pr merge 3$(echo 0)` 合併的是 PR 30）；詞之間有未加引號的替換時也擋下，因為它可能展開成零個詞（`gh pr merge --subject $(x) 3`）。交給 `bash -c`、`sh -c`、`eval` 的字串裡，加了引號的替換也照未加引號算：那個 shell 會把字串重新切詞。
- **時間。** 讀命令的時間與同一條命令裡所有 `ready` 共用 25 秒的預算（`PR_MERGE_GATE_BUDGET`），在 hook 的 30 秒時限之內；剩餘時間不夠時直接擋下，不交給逾時的 hook 決定。兩種舊讀法的耗時與命令長度成線性；lexer 另有步數上限（讀不完的 merge 擋下）。
- **略過。** 在命令前加 `PR_CLOSEOUT_OK=1` 可以略過一次。MCP 工具沒有略過的方式，要略過請改用 `gh`。
- **對其他命令的成本。** 不是 merge 的命令，讀進輸入（一次 `cat`）後在 shell 內建的 `case` 判斷就放行，不啟動 jq、perl 或 node。

## pr-watch

`pr-watch` skill 在 push 後監看一個 PR，一段一段進行：使用者說「盯 PR」時啟動，由內建 `/loop` 一輪一輪跑，只剩使用者能處理的事時停下，處理完再啟動下一段。它不合併、不把 thread 標成已解決、不在 GitHub 上發言，使用者沒說就不 push。

- **`watch <owner/repo> <pr> --repo-dir <clone> [--start] [--fixture <dir>] [--now <iso>]`** 跑 `ready` 的查詢、判定這一輪，寫入狀態檔 `<clone>/.claude/pr-watch.<pr>.local.json`（請在 `.gitignore` 加 `*.local.json`）。exit 0 繼續、8 停止（`watch.stop.reason`）、7 是用法錯誤或判定前就拒絕（`not-started`、`too-soon`——距上一輪不到 30 秒——、`wrong-branch`、不是它寫的狀態檔），狀態檔不動。
- **停止原因**依序檢查：`not-open`、`fork`、`head-not-allowed`（PR head 不是本機 HEAD 的祖先）、`query-failed`（連續 3 次）、`limit`（24 小時或 60 輪）、`ready`、`needs-user`、`no-progress`（check 跑完後連兩輪沒有變化）。head 第一次出現的那一輪不會被判成 `ready` 或 `needs-user`；必跑 check 還沒出現時視為還在跑。
- **`watch-ack <owner/repo> <pr> --repo-dir <clone> --comment <key>...`** 把留言標成已處理。key 是 `<endpoint>:<id>:<內文 sha256 的前 16 碼>`，所以被編輯過的留言或 review 會重新算成新留言。
- **新留言**不論作者，都交給 `/review-pr <pr> --triage-only <ids>`（code-audit-rigor 2.4.0），它分類完就停；使用者確認分類表之前什麼都不修。
- **`hooks/pr-watch-guard.sh`** 在監看期間擋下寫入 GitHub 的 Bash 命令（`gh pr|issue comment|review`、帶欄位、`--input`、非 GET 方法或 GraphQL mutation 的 `gh api`、對 github.com 的 curl 或 wget、`resolveReviewThread` 等）以及所有非讀取的 GitHub MCP 工具。它是攔下習慣性失誤、或照著文件錯誤段落去寫入的絆線，不是對付刻意繞過的安全邊界：那樣的模型可以把狀態檔的 `active` 改成 false。要自己寫入，先停止監看。

## 測試

```bash
bash plugins/pr-closeout/tests/pr-closeout.test.sh
bash plugins/pr-closeout/tests/pr-merge-gate.test.sh
```

測試不需要網路，用 fixture 代替 GitHub 的回應。兩支套件最後都會跑突變，每個突變都必須被它對應的案例抓到才算通過。

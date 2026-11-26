# pr-watch-guard-segments Implementation Plan

> **For agentic workers:** execute with superpowers:executing-plans (inline). All four tasks touch the same hook and test file in sequence.

**Goal:** 防護 hook 判斷 `gh api` 的方法、欄位與 `--input` 時，只看該 `gh api` 所在的命令段。

**Architecture:**
- 一支 `LC_ALL=C awk` 把命令掃描一遍：不在引號內的分隔符切成不同行，引號內或被跳脫的分隔符換成 `\x1f`（Q）。
- bash 逐行（逐段）處理段內的每個 `gh api`。寫入訊號看到段尾；GET 只看到第一個 Q。
- 其餘規則不動。

**Tech Stack:** bash 5、POSIX awk（macOS BWK、ubuntu mawk）、jq（既有依賴）、測試是 `tests/pr-watch-guard.test.sh`。

**Spec:** `openspec/changes/pr-watch-guard-segments/specs/pr-watch/spec.md`、`openspec/changes/pr-watch-guard-segments/design.md`

## Global Constraints

- 版本：`pr-closeout` 1.2.0 → 1.2.1（`plugins/pr-closeout/.claude-plugin/plugin.json`，以及 `.claude-plugin/marketplace.json` 裡 pr-closeout 那一筆）。marketplace 的 metadata 版本 1.23.0 → 1.23.1。marketplace.json 裡另一筆 `"version": "1.2.0"` 屬於別的 plugin，不要動。
- 只改 `gh api` 的判斷範圍，其他規則（resolveReviewThread 等字、`/replies`、`gh pr|issue comment|review`、curl/wget、GraphQL mutation）照舊看整行。
- 分隔符清單只出現在 awk 裡一次。
- 現有 87 條案例必須仍然通過。
- 驗證判定只看命令自己的 exit code：先落檔、再看 `$RC`。

## Review Focus

1. heredoc 內含撇號（`don't`）：引號會一路開到下一個 `'`，只能讓寫入範圍變大、不能放行。案例在 Task 1。
2. 命令含中文：`gh api … -f body=已修正 | cut -f1`。awk 以位元組處理，不得中止或吞掉後面的行。案例在 Task 1。
3. 用 tab 隔開的旗標：`gh api x	-f	body=y`。既有案例已涵蓋，Task 1 再補一個跨段的 tab 版本。
4. 段內多個 `gh api`，且第二個沒有 GET（`gh api -X GET a $(gh api b -f c)`）：要擋。案例在 Task 1。
5. 很長的命令（語料最長 7034 字元）：不加計時斷言，因為會不穩。Task 4 用語料重放記錄最慢一條的時間。

---

## 1. 逐段判斷

### Task 1: gh api 的旗標只在自己那一段判斷
- [ ] 1.1 guard 改為逐段判斷 `gh api`，spec 四個情境與邊界案例入測、全綠

**Files:**
- Modify: `plugins/pr-closeout/hooks/pr-watch-guard.sh:84-96`（`gh api` 區塊）
- Test: `plugins/pr-closeout/tests/pr-watch-guard.test.sh`（在 allow 清單之後、cwd 測試之前插入一段 `# gh api is judged per command segment`）

**Interfaces:**
- Produces（Task 2 的突變會用到下面這些行文字）：
  - `Q=$'\x1f'; NL=$'\n'`
  - awk 程式內的 `sep = "|;&()\`\n"`，未引用的分隔符輸出 `"\n"`，引用中或跳脫的輸出 `Q`
  - `while IFS= read -r seg; do … done <<< "$t"`
  - 本身範圍 `own=${rest%%"$Q"*}`
  - 寫入範圍 `w=${rest//$Q/ }`

1. 寫失敗的案例，全部用既有的 `verdict` 與 `bash_in`。
   - deny：
     - `gh api -X GET repos/o/r/pulls/7 | cat; gh api repos/o/r/issues/7/comments -f body=x`
     - `gh api --method GET repos/o/r/pulls/7 && gh api repos/o/r/pulls/7/reviews --input r.json`
     - `gh api repos/o/r/issues/7/comments --jq '.[] | .id' -f body=x`
     - `echo "$(gh api -X GET repos/o/r/pulls/7; gh api repos/o/r/issues/7/comments -f body=x)"`
     - `sh -c 'gh api repos/o/r/issues/7/comments -f body=x; gh api -X GET repos/o/r/pulls/7'`
     - `sh -c 'gh api repos/o/r/issues/7/comments "-f" body=x'`
     - `bash -c "gh api repos/o/r/issues/7/comments '-f' body=x"`
     - `gh api repos/o/r/issues/7/comments $'\'|' -f body=x`
     - `gh api repos/o/r/issues/7/comments \; -f body=x`
     - `gh api repos/o/r/issues/7/comments \| -f body=x`
     - `gh api -X GET repos/o/r/pulls/7 $(gh api repos/o/r/issues/7/comments -f body=x)`
     - `cat <<'EOF'` 加一行 `don't` 再接 `EOF`、換行後 `gh api -X GET repos/o/r/pulls/7; gh api repos/o/r/issues/7/comments -f body=x`
   - allow：
     - `gh api repos/o/r/pulls/7 --jq .head.sha | cut -f1`
     - `gh api repos/o/r/pulls/7/comments --paginate | jq -r '.[].id' | rm -f x; bash -x run.sh`
     - `gh api repos/o/r/pulls/7 --jq .title | grep -F 已修正`
     - `gh api repos/o/r/pulls/7	--jq .title	|	cut	-f1`
     - `gh api -X GET repos/o/r/pulls/7/comments -f per_page=100`（這條已存在，不重複）
2. 用現行 guard 執行並落檔：`bash plugins/pr-closeout/tests/pr-watch-guard.test.sh > "$TMPDIR/pwg.log" 2>&1; RC=$?`。
   預期 `RC` 非 0，FAIL 行恰好是現行 guard 判錯的那幾條：前兩條 deny、`$(…; …)`、`sh -c` 分號那條，以及 allow 的 `cut -f1`、`rm -f`、`grep -F`、tab 那幾條。不能出現其他 FAIL。
3. 照 design.md 實作，換掉第 84–96 行：
   - awk 掃描，未引用的分隔符直接輸出換行，bash 端不再列清單。
   - 段落迴圈用 here-string，`deny` 才會在目前的 shell 生效。
   - GraphQL mutation 規則照舊用 `norm` 判斷，條件是整行有 `gh api`。
   - 改寫第 61–68 行附近的區塊註解，說明 `norm` 給整行規則用、分段文字給 `gh api` 用。
4. 重跑同一個命令，預期 `RC=0`，最後一行是 `pr-watch-guard: N passed, 0 failed`。突變此時可能有失敗，留到 Task 2 處理；這一步用 `NO_MUTANTS=1`。
5. Commit：`git add plugins/pr-closeout/hooks/pr-watch-guard.sh plugins/pr-closeout/tests/pr-watch-guard.test.sh`、`git commit --no-gpg-sign -m "pr-closeout: pr-watch-guard judges gh api per command segment"`。

## 2. 保護力

### Task 2: 突變打在掃描與範圍的路徑上
- [ ] 2.1 新增 7 個突變、修好兩個依附舊行的突變，突變總數檢查從 15 改成 22，全部轉紅

**Files:**
- Modify: `plugins/pr-closeout/tests/pr-watch-guard.test.sh`（`mutant` 清單、`[ "$mut_n" = 15 ]`、`MIN_PASS`）

**Interfaces:**
- Consumes：Task 1 Produces 列的行文字

1. 先重跑完整套件（含突變），落檔看哪幾個舊突變的 `substitution did not apply`。預期 `no-api-write` 與 `no-xanchor` 這兩個不再套得上，因為它們的取代式指向被改寫的行。
2. 把這兩個改成指向新的行，各自仍要被原本那條案例殺掉：
   - `no-api-write`：讓段內 `gh api` 的 while 條件恆為假
   - `no-xanchor`：拿掉寫入範圍 `-x` regex 前面的 `(^|[[:space:]])`
3. 新增 7 個突變，第二個欄位填「第一條應該轉紅的案例」：
   - `scan-noquote`：awk 不進入單引號狀態 → `--jq '.[] | .id' -f`
   - `scan-qsplit`：引號內的分隔符輸出換行而非 Q → `--jq '.[] | .id' -f`
   - `own-is-write`：`own=${rest%%"$Q"*}` 改成 `own=$rest` → `sh -c 'gh api … -f body=x; gh api -X GET …'`
   - `nested-quote`：不拿掉另一種引號字元 → `sh -c '… "-f" …'`
   - `no-ansi`：不辨認 `$'` → `$'\'|' -f`
   - `no-escape`：反斜線不跳脫分隔符 → `\; -f`
   - `pipe-loop`：段落迴圈改成 `printf '%s\n' "$t" | while …` → `| cat; gh api … -f`
4. 把 `[ "$mut_n" = 15 ]` 與它的訊息改成 22。`MIN_PASS` 設為 Task 1 實際通過數減 2。
5. 完整執行並落檔：`bash plugins/pr-closeout/tests/pr-watch-guard.test.sh > "$TMPDIR/pwg.log" 2>&1; RC=$?`。
   預期 `RC=0`，且 `command grep -c 'suite red as required' "$TMPDIR/pwg.log"` 是 22。
6. Commit：`pr-closeout: guard mutants on the segment scanner`。

## 3. 文件與版本

### Task 3: 版本 1.2.1 與文件同步
- [ ] 3.1 plugin.json、marketplace 兩處版本、兩份 CHANGELOG、兩份 plugin README 的 guard 段落同步

**Files:**
- Modify:
  - `plugins/pr-closeout/.claude-plugin/plugin.json:3`
  - `.claude-plugin/marketplace.json:8,92`（第 71 行不動）
  - `plugins/pr-closeout/CHANGELOG.md`
  - `CHANGELOG.md`
  - `CHANGELOG.zh-TW.md`
  - `plugins/pr-closeout/README.md:111`
  - `plugins/pr-closeout/README.zh-TW.md:111`

1. 改版本：1.2.0 → 1.2.1，marketplace metadata 1.23.0 → 1.23.1。
2. plugin CHANGELOG 加 `## [1.2.1] - 2026-11-26`，列 `### Fixed` 兩點：
   - 跨段 GET 不再放行另一個 `gh api` 的寫入
   - 別段的 `-f`／`-x` 不再被當成 `gh api` 旗標
   再寫明突變數、語料重放結果（3 條改變），以及內容誤擋留在 follow-ups。
   根目錄兩份 CHANGELOG 各加 `[1.23.1]`，比照 1.23.0 的格式。
3. 兩份 README 第 111 行的 `gh api` 描述加一句：方法、欄位與 `--input` 只看同一段命令。
4. 驗證：
   - `command grep -rn -F '1.2.1' plugins/pr-closeout/.claude-plugin/plugin.json .claude-plugin/marketplace.json` 有兩筆。
   - `command grep -n -F '"1.23.1"' .claude-plugin/marketplace.json` 有一筆。
   - `jq . .claude-plugin/marketplace.json >/dev/null`，exit 0。
   - 跑 `bash plugins/pr-closeout/tests/pr-watch-docs.test.sh`，RC=0。
5. Commit：`pr-closeout 1.2.1 (marketplace 1.23.1): pr-watch-guard per-segment gh api — versions, changelogs, README`。

## 4. 整體驗證

### Task 4: 四套測試與語料重放
- [ ] 4.1 四套測試各自 RC=0；語料重放的改變只有 design.md 記錄的 3 條，記下最慢一條的時間

**Files:**
- 不改檔。結果寫進 Phase 5 的 review-notes。

1. 依序跑下面四個測試，各自落檔取 RC，四個都要是 0：
   - `plugins/pr-closeout/tests/pr-closeout.test.sh`
   - `pr-watch-guard.test.sh`
   - `pr-watch-docs.test.sh`
   - `plugins/code-audit-rigor/tests/review-pr-triage.test.sh`
2. 拿 scratchpad 的 `diff.mjs` 對新的 hook 跑語料（`replay.json`）。預期 `changed=3`，內容與 design.md「驗證證據」一致，並記下 `max=` 的毫秒數。
3. 不 commit。

# Design: pr-closeout-hooks-fail-closed

## Context

pr-closeout 有兩個 PreToolUse hook 負責擋動作：`pr-merge-gate`（Bash 與 MCP merge）、`pr-watch-guard`（Bash 與 GitHub MCP 寫入）。`hooks.json` 以 `bash "<路徑>"` 執行兩者，用的是 PATH 上第一個 `bash`。Claude Code 的規則（https://code.claude.com/docs/en/hooks）：command hook 逾時、exit code 不是 0 也不是 2、或輸出不合法時，預設照常執行工具呼叫；handler 設 `"onFailure": "block"`（需 v2.1.295 以上）時，這些失敗改為等同 exit 2，也就是擋下。

2026-11-27 量測（Apple `/bin/bash` 3.2.57 與自行從 GNU 原始碼編的 3.2.57 結果一致，`LC_ALL=en_US.UTF-8`）：

| 套件 | 現況 | 只修 `${var}` 之後 |
|---|---|---|
| pr-watch-guard（126 條） | 34 過 | 123 過；剩 2 條 |
| pr-merge-gate（243 條） | 230 過 | 241 過；剩 1 條（加地板檢查共 2 個 FAIL） |

## Goals / Non-Goals

**Goals**
- 兩個 hook 在 bash 3.2 與 UTF-8 locale 下的判定與 bash 5 相同：兩份套件在 3.2 下全綠。
- 兩個 hook 失效（逾時、崩潰、輸出不合法）時擋下動作。
- CI 用真的 bash 3.2 跑兩份套件，同類回歸會讓 CI 變紅。

**Non-Goals**
- 其他 plugin（openspec 的 archive-gate、skip-gate，scope-ledger 的 gate）在 3.2 下的行為：本次 grep 沒找到同型寫法，但沒有實跑它們的套件，列為 follow-up。
- 長命令的長度上限：有 `onFailure: "block"` 後，逾時本身就是擋下。
- 偵測 Claude Code 版本：早於 v2.1.295 的 CLI 忽略 `onFailure`，README 寫明最低版本。

## Approaches

使用者 2026-11-27 在三個方案中選定 B：
- **A 只修崩潰點**：最小，但逾時與日後新的崩潰仍會放行。
- **B 修崩潰＋兩個 hook 都加 `onFailure: "block"`**（採用）：失效一律擋下；代價是 hook 本身出 bug 時會擋住所有 Bash 呼叫，所以必須先在 3.2 下全綠。
- **B′ 只有 merge gate 加 block**：guard 失效仍放行，日常 Bash 不受 guard 的 bug 影響；merge gate 才是高代價的那一個。

防回歸也由使用者選定：CI 編 bash 3.2 跑兩份套件，而不是只做靜態檢查。

## Decisions

### D1 修掉 bash 3.2 下的四類失敗

| # | 寫法 | 3.2 的行為 | 位置 | 改法 | 失效方向 |
|---|---|---|---|---|---|
| a | `$name` 後緊接全形字元（`$active）`、`$sha」`、`$rc）`） | UTF-8 locale 下把全形字元的位元組讀進變數名，`set -u` 報 unbound variable，exit 1 | guard 42、merge gate 494、501 | 改成 `${name}` | 放行（最嚴重：merge gate 在 ready 不就緒時放行） |
| b | 雙引號 `${…}` 裡的 `$'…'`（`"${cmd//$'\\\n'/}"`） | 不展開，續行沒被拿掉 | guard 110 | 先存成變數：`nl=$'\\\n'`，再寫 `"${cmd//"$nl"/}"` | 多擋（續行上的 GET 讀取被擋） |
| c | `set -u` 下展開空陣列（`"${dirs[@]}"`） | unbound variable，exit 1 | guard 33（沒有 `CLAUDE_PROJECT_DIR` 也沒有可用 cwd） | 陣列為空時直接 `exit 0`：沒有目錄可讀，就沒有監看 | 本來放行，方向正確；但加了 `onFailure: "block"` 之後會變成擋下所有 Bash，所以必修 |
| d | 測試 harness：`FAKE_RC=0 gate … "$(mcp_in "{\"…\":\"$SHA\"}")"` | 3.2 對前置賦值加巢狀跳脫引號的解析不同，jq 收到壞 JSON，hook 收到空輸入 | merge gate 測試第 69 行一帶 | 用 `jq -n --arg` 組 MCP 輸入，不手寫跳脫的 JSON 字串 | 不影響 hook；測試誤報 |

merge gate 的 `"${args[@]}"` 至少含 `ready repo num` 三個元素，不會是空陣列，不必改。

### D2 hooks.json：兩個 hook 的每個 handler 加 `"onFailure": "block"`

依官方文件，`onFailure` 是每個 hook handler 的欄位（與 `type`、`command`、`timeout` 同層），不是 matcher 的欄位。兩個 hook 一共 4 個 handler：Bash matcher 下的 merge gate 與 guard、MCP merge matcher 下的 merge gate、GitHub MCP matcher 下的 guard。

測試從 hooks.json 推導，不手寫清單：`command` 含 `pr-merge-gate.sh` 或 `pr-watch-guard.sh` 的每個 handler 都必須是 `onFailure == "block"`；同時斷言至少找到 4 個，避免 jq 路徑寫錯時零個也算通過。

失效時的行為（本次之後）：

| 情況 | CLI ≥ 2.1.295 | 更舊的 CLI |
|---|---|---|
| hook 逾時（guard 10 秒、merge gate 30 秒） | 擋下 | 放行 |
| hook 崩潰（exit 非 0／2）、啟動不了 | 擋下 | 放行 |
| 輸出不是合法 JSON | 擋下 | 放行 |
| 沒有監看、不是 merge（hook 正常 exit 0、無輸出） | 放行 | 放行 |

### D3 便宜的第一道防線：lint

`pr-watch-guard.test.sh` 與 `pr-merge-gate.test.sh` 各加一條靜態檢查：受測的 hook 檔裡不得出現 `$name` 後緊接非 ASCII 位元組（`LC_ALL=C perl -ne '/\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]/'`）。不依賴 3.2，在現有的 bash 5 CI job 也會擋。只擋 D1a 這一型；其他 3.2 語意差異交給 D4。

### D4 CI：用 bash 3.2.57 跑兩份套件

`.github/workflows/validate.yml` 加一個 job（ubuntu-latest）：
1. 下載 `https://ftp.gnu.org/gnu/bash/bash-3.2.57.tar.gz`，比對 sha256 `3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4`，不符就失敗。
2. `./configure --without-bash-malloc`，接著序列化 `make`（不加 `-j`，平行建置會在 `libintl.h` 產生前就編 `mkbuiltins`），`CFLAGS` 與 `CFLAGS_FOR_BUILD` 都加 `-std=gnu89` 和放寬隱式宣告的旗標。ubuntu 上另需 `YACC="bison -y"`（沒有 yacc 就先裝 bison），且 runner 要是 x86_64（2002 年的 `config.guess` 不認 aarch64）。ubuntu amd64 容器實測可建。
3. 建一個目錄，把編出的 `bash` 放進去並加到 PATH 最前，讓套件裡的 `bash "$HOOK"` 用到它。
4. **金絲雀**：證明 PATH 上的 `bash` 真的是 3.2，job 不會什麼都沒測就綠燈。檢查兩個在 glibc 上重現的 3.2 語意，任一不成立就讓 job 失敗：空陣列在 `set -u` 下展開必須報錯；雙引號內 `${…}` 裡的 `$'…'` 必須不展開。D1a 型（`$name` 後接全形字元）是 macOS libc 特有，GNU bash 3.2 在 glibc 下（`C.UTF-8` 與 `C` 都）不重現，所以不拿來當金絲雀，由 D3 的 lint 在每個平台擋。locale 用 `C.UTF-8`，ubuntu 預設就有。
5. 以 `NO_MUTANTS=1` 跑兩份套件，各自以 exit code 判定。突變仍由現有的 bash 5 job 跑，3.2 job 只負責語意差異。

編好的 bash 以 actions/cache 快取，key 含 runner 的 OS 與架構、tarball 的 sha256，以及一個手動遞增的 recipe 標記（`r1`）；改 flags、configure 或 make 那幾行時要遞增它，否則命中快取會沿用舊 binary，而金絲雀分辨不出建置方式的差別。命中快取時跳過步驟 1–2。

### D5 文件與版本

- pr-closeout 1.2.1 → 1.3.0、marketplace 1.23.1 → 1.24.0；plugin CHANGELOG 加 [1.3.0]，兩份根 CHANGELOG 加 [1.24.0]。
- README（中英）：寫明兩個 hook 失效時擋下、需要 Claude Code v2.1.295 以上；hook 壞掉、擋住所有 Bash 時用 `/plugin disable pr-closeout` 脫困。

## Risks / Trade-offs

- **plugin hooks.json 是否讀 `onFailure`**：文件沒寫。證據來自 Claude Code 2.1.332 binary 的程式碼：command hook 一律讀 `hook.onFailure`，而處理帶 `pluginId` 的 hook 的同一段程式也比對 `onFailure!=="block"`。沒有實測：裝一個探針 hook 寫進設定檔，被 auto mode 以 Undermining Oversight 擋下。殘餘風險是欄位被忽略、維持放行，等於沒有比現況更差。
- **hook 有 bug 時擋住所有 Bash**（使用者選 B 時已知的代價）：guard 掛在每一次 Bash 呼叫上。D1c 把唯一已知會在 allow 路徑崩潰的情況修掉，D3 的 lint 與 D4 的 3.2 job 讓兩型 3.2 崩潰在 CI 現形；剩下的出路是停用 plugin。
- **DESIGN-RED-FLAGS #8（手動同步清單）**：「哪些 handler 要 block」若寫死在測試裡，新增 handler 時會漏。D2 的測試從 hooks.json 依 command 推導，並設最少 4 個的地板。
- **CI 建置依賴 ftp.gnu.org**：來源掛掉時 job 失敗（方向正確），有快取時不受影響；以 sha256 鎖定內容。

## Open Questions

- [default] 其他 plugin 的 gate hook 在 3.2 下沒有實跑，不納入本次；列進 follow-ups（使用者可要求併入）。
- [default] 3.2 job 用 `C.UTF-8`；金絲雀證明 PATH 上是 3.2，D1a 型由 lint 負責，不靠 locale。
- [default] 快取命中時跳過 sha256 檢查，binary 的完整性只靠 GitHub 的快取範圍規則；此 job 無 secret、token 唯讀，不另處理。
- [default] 3.2 job 不跑突變，突變由 bash 5 job 負責。
- [default] D1c 在沒有可讀目錄時 `exit 0`，與現有「沒有監看就放行」的語意一致。

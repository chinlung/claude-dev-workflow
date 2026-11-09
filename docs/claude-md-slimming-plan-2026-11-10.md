# 判定類子代理稽核 hook（W4 PR B）實作計畫

> **狀態（2026-11-10 回填）：** 已完成。Task 1–3 在個人設定 repo 完成，隨其 PR #5 合併（main `a7aed16`）；Task 4 的文件部分隨本 repo PR #46 合併（main `e5ad9b4`）。與計畫的偏差：測試最終 28 項，比 Task 2 規劃的多 6 項；Task 3 的無損候選清單寫成一張 12 列的表，不是設計文件的三張表；判定類子代理的「低於 opus」只在 jq 過濾式判斷一次，後面重複的 case 判斷是死碼，已刪。勾選框於收尾後回填。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CLAUDE.md 第 116 行的規則目前只有行程內 mod `subagent-tiers` 承接。補上一個不依賴 mod 的第二承接者：判定類子代理實際跑在 opus 以下時，在它結束的當下點名，讓使用者與主迴圈知道那個結論不算驗證。

**Architecture:**
- 新增一支 SubagentStop classic hook。
- 它讀 hook 輸入的 `agent_transcript_path`、同目錄的 `agent-<id>.meta.json`，以及 transcript 第一則 assistant 的 `message.model`。
- 判定類的認法照抄 mod 與 `subagent-model-floor.sh` 的規則。
- 低於 opus 時，輸出兩樣東西：
  - `systemMessage`，給使用者看；
  - `additionalContext`，請子代理在最後回報的第一行加上警告，由回報帶回主迴圈。
- 第二次結束時 `stop_hook_active` 為 true，hook 不再出聲。

**Tech Stack:** bash、jq；測試是 `scripts/hooks/tests/*.test.sh` 的慣例寫法，由 `run-all.sh` 與 CI 收集。

**Spec:** `docs/claude-md-slimming-design-2026-11-09.md`，「第 116 行：第二承接者」一節與 D13。

## Global Constraints

- 落點是個人設定 repo（`~/.claude`），分支 `feat/subagent-judgment-audit`。這個 repo 的 commit 帶 session trailer。
- 下文的 `<config-repo>` 指個人設定 repo 的絕對路徑，`<this-repo>` 指本 repo 的絕對路徑。執行時代入**字面**絕對路徑：commit 層審查以 shlex 切命令文字，不展開 `~` 與變數。
- 本計畫與設計文件放在公開 repo，不寫 session id、專案名稱、本機絕對路徑。
- 判定類下限是 opus。家族排序：haiku 0、sonnet 1、opus 2、fable 3、mythos 3。
- 不認得的模型家族不判定，比照 mod 的 `belowFloor`。
- 只在工具錯誤時放行（exit 0、無輸出），比照 `subagent-model-floor.sh`。沒有 deny 路徑：SubagentStop 的 hook 不得回 `decision: block`。
- CLAUDE.md 不得變長。lint 上限維持 20,000，第 116 行的改寫不得長於原文的 184 字。
- 所有在 sandbox 外由 harness 執行的腳本都要在 `sandbox.filesystem.denyWrite` 內。新腳本放在 `~/.claude/scripts/hooks/`，已被既有的 `~/.claude/scripts` 項涵蓋，不必另加。
- staging 一律具名，不用 `git add -A`。

## Review Focus

1. **transcript 開頭有非模型的 assistant 行。** 例如錯誤時的 `<synthetic>`。這種行要略過，取第一則 `message.model` 以 `claude-` 開頭的。（Task 2 案例「synthetic 行在前」）
2. **meta 檔不存在或欄位缺漏。** 例如舊 transcript。此時退回 hook 輸入的 `agent_type`；generic 型別又沒有 description 時不判定，靜默。（Task 2 案例「無 meta」）
3. **中文 description。** 例如「安全審查」，不分大小寫的比對也要能命中。（Task 2 案例「generic 中文審查 haiku」）
4. **路徑問題。** `agent_transcript_path` 為空、指向不存在的檔、內容是壞 JSON 時，一律 exit 0、無 stdout、無 stderr。（Task 2 三個案例）
5. **正則與兩個來源漂移。** 這條 hook 的分類必須與 mod 與 floor hook 一致，任何一邊改了另一邊沒改就要紅。（Task 2 的「正則同步」斷言）

---

### Task 1: 先決查證

**Files:**
- Create（暫時，不 commit）：`~/.claude/scripts/hooks/subagent-stop-probe.sh`
- Modify（暫時）：`~/.claude/settings.json`，加入 `hooks.SubagentStop`
- Modify：`~/.claude/refs/claude-code-capability-checks.md`，追加一節記錄結果

**Interfaces:**
- Produces：一行裁決，寫進執行帳本：`Task 1: Ruling: <(i)|(ii)|(iii)> — <觀察> — <cost if wrong>`。Task 2 與 Task 3 依它決定輸出形狀。

- [x] **Step 1：寫探針。** 它把 stdin 整行附加到 `~/.claude/.probe-subagent-stop.jsonl`（`stop_hook_active` 也記下）。
  - `stop_hook_active` 不是 true 時，輸出：
    ```json
    {"systemMessage":"PROBE systemMessage","hookSpecificOutput":{"hookEventName":"SubagentStop","additionalContext":"Begin your final report with the exact line PROBE-OK, then stop."}}
    ```
  - 寫完先確認 `git -C ~/.claude check-ignore -q .probe-subagent-stop.jsonl; echo rc=$?`，結果必須是 `rc=0`。不是 0 就改放 `$TMPDIR`，並記下 hook 端與 session 端的 `$TMPDIR` 可能不同。
- [x] **Step 2：註冊探針。** 用 Edit 工具加入：
  ```json
  "SubagentStop": [{ "hooks": [{ "type": "command", "command": "bash \"$HOME/.claude/scripts/hooks/subagent-stop-probe.sh\"", "timeout": 10 }] }]
  ```
- [x] **Step 3：Agent 派發。** 派一個 general-purpose 子代理（`model: "haiku"`、`effort: "low"`、prompt「只回 OK」）。
  - Expected：探針檔有兩行，第二行 `stop_hook_active: true`；欄位含 `agent_id`、`agent_type`、`agent_transcript_path`。主迴圈收到的回報以 `PROBE-OK` 開頭，終端機顯示 `PROBE systemMessage`。
  - 探針檔為空時，表示 hook 設定要新 session 才生效：請使用者開新 session 重做 Step 3，並記下這個事實。
- [x] **Step 4：Workflow 子代理。** Workflow 需要使用者明示同意，先問使用者，給兩個選項：
  - 授權一個只含一個 `agent()`（只回 OK）的最小 workflow；
  - 或由使用者自己跑一次 `/claude-security` 的 changes scan。
  
  Expected：探針檔出現 `agent_transcript_path` 位於 `subagents/workflows/wf_*/` 的那一筆，`agent_type` 是具名型別。

  若使用者選擇跑 changes scan，請他在 session 模型設為 haiku 的情況下跑。這一次同時驗證 mod 本身（設計文件先決查證第 4 項）：scan-verifier transcript 第一則 assistant 的 `requestedModel` 應為 opus；若仍是 haiku，代表 mod 的 spawn 改寫在 workflow 裡沒有生效，要另行回報使用者。
- [x] **Step 5：裁決。**
  - **(i)** 兩種子代理都觸發，`PROBE-OK` 到達主迴圈：照設計做，同時輸出兩個欄位。
  - **(ii)** 都觸發，但 `PROBE-OK` 沒到主迴圈，或子代理沒有多跑一輪：只輸出 `systemMessage`。Task 2 刪掉 additionalContext 的案例。
  - **(iii)** Workflow 子代理不觸發：停止本計畫。改做設計文件的方案 B（擴充 `mods-switch-check.sh`），第 116 行維持現狀，並回報使用者。
- [x] **Step 6：記錄並清理。** 結果寫進 `refs/claude-code-capability-checks.md` 新的一節，附 binary 版本、日期與觀察到的欄位。從 settings.json 拿掉探針，刪除探針腳本與探針檔，並用 `git -C ~/.claude status --short` 確認只剩 refs 的修改。

### Task 2: 稽核 hook 與測試

**Files:**
- Create：`~/.claude/scripts/hooks/subagent-judgment-audit.sh`
- Test：`~/.claude/scripts/hooks/tests/subagent-judgment-audit.test.sh`

**Interfaces:**
- Consumes：Task 1 的裁決，決定輸出形狀。
- Produces：
  - 輸入：hook stdin JSON，欄位 `hook_event_name`、`stop_hook_active`、`agent_id`、`agent_type`、`agent_transcript_path`。
  - 不出聲時：exit 0，無 stdout。
  - 出聲時：exit 0，stdout 為
    ```json
    {"systemMessage": S, "hookSpecificOutput": {"hookEventName":"SubagentStop","additionalContext": A}}
    ```
    裁決 (ii) 時沒有 `hookSpecificOutput`。
  - `S` 的格式：`subagent-judgment-audit：判定類子代理 <type>（<description>）跑在 <model>，低於 opus；它的結論不算驗證，請以 opus 重跑。`
  - `A` 的格式：`你這次跑在 <model>，低於判定類的下限 opus。請在最後回報的第一行原樣寫：⚠ 本結論跑在 <model>，未達判定類下限 opus，不可當作驗證。然後結束。`

分類規則（照抄，不重新設計）：

| 項目 | 規則 |
|---|---|
| type | `meta.agentType`，沒有時用輸入的 `agent_type` |
| desc | `meta.description`，沒有時為空 |
| generic | type ∈ {`general-purpose`, `workflow-subagent`, `claude`, ``} |
| generic 的判定類 | desc 第一行不符合 `IMPL_RE`，且 desc 符合 `REVIEW_RE`。兩條字面值取自 `subagent-model-floor.sh` 第 50、52 行 |
| 具名型別的判定類 | type 最後一個 `:` 之後的部分符合 `JUDGE_NAME_RE`，取自 `skills/subagent-tiers/hooks/register.tsx` 第 78 行的本體 |

三者都不分大小寫。fork 的 type 是 `fork`，不會命中具名規則。

- [x] **Step 1：寫測試。** 仿 `subagent-model-floor.test.sh`：
  - `mk_case <type> <desc> <model…>` 在 `mktemp -d` 底下建 `agent-x.jsonl` 與 `agent-x.meta.json`；
  - `run <expected: speak|silent> <label> <json>` 比對 stdout 是否為空。
  - 出聲的案例另驗：輸出能被 `jq -e .systemMessage` 解析，而且含模型名。
  - 地板：`speaks_run` 與 `silents_run` 各自在迴圈外計數，下限分別是 6 與 9。

  案例（標籤即名稱）：

  | 標籤 | 輸入 | 預期 |
  |---|---|---|
  | 具名 verifier haiku | `claude-security:scan-verifier`, `panel:C1:v3`, `claude-haiku-5-5` | speak |
  | 具名 verifier sonnet | `code-audit-rigor:finding-verifier`, `x`, `claude-sonnet-5-5` | speak |
  | 具名 researcher haiku | `claude-security:scan-researcher`, `x`, `claude-haiku-5-5` | speak |
  | generic 英文審查 haiku | `general-purpose`, `Security review of PR diff`, `claude-haiku-5-5` | speak |
  | generic 中文審查 haiku | `general-purpose`, `安全審查 PR diff`, `claude-haiku-5-5` | speak |
  | synthetic 行在前 | 具名 verifier；transcript 先 `<synthetic>` 再 `claude-haiku-5-5` | speak |
  | 具名 verifier opus | `claude-opus-5-5` | silent |
  | 具名 verifier fable | `claude-fable-5-1` | silent |
  | generic 實作 haiku | `general-purpose`, `實作 Task 3：註冊寄驗證信`, `claude-haiku-5-5` | silent |
  | 具名非判定 haiku | `claude-security:scan-redactor`, `x`, `claude-haiku-5-5` | silent |
  | fork haiku | `fork`, `Review x`, `claude-haiku-5-5` | silent |
  | 不明家族 | 具名 verifier, `claude-newcheap-6` | silent |
  | stop_hook_active | 具名 verifier haiku，`stop_hook_active: true` | silent |
  | 無 meta | 刪掉 meta 檔，輸入 `agent_type: general-purpose` | silent |
  | 路徑為空 | `agent_transcript_path: ""` | silent，且 stderr 為空 |
  | 路徑不存在 | 指向不存在的檔 | silent，且 stderr 為空 |
  | 壞 JSON | transcript 內容為 `{not json` | silent，且 stderr 為空 |

  「正則同步」斷言：用 perl 從三個檔各自抽出 `IMPL_RE`、`REVIEW_RE`、`JUDGE_NAME_RE` 的字面本體並逐字比對，不同就 FAIL。`IMPL_RE` 只比 floor hook 與新 hook，因為 mod 是 JS 語法（`\s`），bash 版用 `[[:space:]]`。

- [x] **Step 2：確認測試是紅的。**
  - Run：`bash ~/.claude/scripts/hooks/tests/subagent-judgment-audit.test.sh > "$TMPDIR/sja.log" 2>&1; echo rc=$?`
  - Expected：`rc=1`，log 裡的 FAIL 是「hook 不存在」或 speak 案例沒出聲。
- [x] **Step 3：實作 `subagent-judgment-audit.sh`。**
  - 開頭註解比照 floor hook：說明 hook 要守什麼、與 mod 的分工、只在工具錯誤時放行。
  - `trap` 錯誤時 exit 0。
  - 一般路徑用 jq 讀檔：transcript 用 `jq -r 'select(.type=="assistant") | .message.model // empty' | grep -m1 '^claude-'`。注意 Bash 工具裡的 `grep` 是被包過的 ugrep 函式，腳本中改用 `command grep` 或 jq 的 `select(startswith("claude-"))`。
- [x] **Step 4：確認測試是綠的。**
  - Run：同 Step 2。
  - Expected：`rc=0`，最後一行顯示全數通過，且兩個地板都達標。
- [x] **Step 5：突變。** 每個突變單獨套用、跑測試、確認轉紅，再還原。結果記進執行帳本。至少要做這五個：
  1. 拿掉模型比對（一律出聲）；
  2. 拿掉判定類分類（任何型別都出聲）；
  3. opus 也算低於下限；
  4. 不檢查 `stop_hook_active`；
  5. 不略過 `<synthetic>`（取第一則 assistant 不篩前綴）。
- [x] **Step 6：全套。**
  - Run：`bash ~/.claude/scripts/hooks/tests/run-all.sh > "$TMPDIR/runall.log" 2>&1; echo rc=$?`
  - Expected：`rc=0`，log 結尾是 ALL GREEN。
- [x] **Step 7：Commit。**
  ```bash
  git -C <config-repo> add scripts/hooks/subagent-judgment-audit.sh scripts/hooks/tests/subagent-judgment-audit.test.sh
  git -C <config-repo> commit -m "feat(hooks): subagent-judgment-audit names a judgment subagent that ran below opus"
  ```
  commit message 的 body 要寫明裁決結果與突變數。

### Task 3: 註冊、規則與文件

**Files:**
- Modify：`~/.claude/settings.json`，在 `hooks.SubagentStop` 註冊
- Modify：`~/.claude/CLAUDE.md:116`
- Modify：`~/.claude/refs/subagent-model-tiers.md`，新增 §7.2
- Modify：`~/.claude/refs/claude-md-authoring.md`，新增無損候選清單一節

**Interfaces:**
- Consumes：Task 2 的腳本路徑；Task 1 的裁決與觀察。

- [x] **Step 1：註冊 hook。** 用 Edit 工具加入：
  ```json
  "SubagentStop": [{ "hooks": [{ "type": "command", "command": "bash \"$HOME/.claude/scripts/hooks/subagent-judgment-audit.sh\"", "timeout": 10, "statusMessage": "subagent judgment audit" }] }]
  ```
  接著用 `jq '.hooks.SubagentStop' ~/.claude/settings.json` 讀回確認。
- [x] **Step 2：端到端驗證。** 用真實的 haiku 子代理 transcript 餵已安裝的 hook，不用 fixture。
  - 派一個實作類的 haiku 子代理：`model: "haiku"`、`effort: "low"`，description 用「Implement probe: reply OK」，prompt 是「只回 OK」。審查類的 haiku 派發會被 floor hook 擋下，所以這裡要用實作類。
  - 把它的 `agent-<id>.jsonl` 與 `.meta.json` 複製到 `$TMPDIR`，把副本 meta 的 `agentType` 改成 `claude-security:scan-verifier`。
  - 組一份 SubagentStop 輸入，`agent_transcript_path` 指向副本，pipe 給 `<config-repo>/scripts/hooks/subagent-judgment-audit.sh`。
  - Expected：stdout 的 `systemMessage` 含 `claude-haiku-5-5`。原本那個實作類子代理結束時，hook 不出聲。
- [x] **Step 3：CLAUDE.md 第 116 行。** 先讀 `refs/claude-md-authoring.md` 的撰寫 SOP。把「mod 停擺時以 session 設定 ≥ opus 為準」改成：「SubagentStop hook `subagent-judgment-audit.sh` 事後點名跑在 opus 以下的判定，被點名的結論不算驗證、以 opus 重跑」。
  - 全行不得超過 184 字（原長）；粗體仍只有一處；案例句保留。
  - 存檔時 lint hook 會檢查；Expected：不出現「較基線增加」。
- [x] **Step 4：`subagent-model-tiers.md` §7.2。** 寫：
  - mod 的四種停擺情況，與各自有沒有防護（設計文件的表）；
  - 這支 hook 讀什麼、何時出聲；
  - Task 1 的觀察；
  - 測試路徑與突變數；
  - 刻意不管的情況：不明家族、fork。
  
  另把 §7「未實測」那一項的驗法指向本節。
- [x] **Step 5：候選清單。** 在 `claude-md-authoring.md` §3 之後新增一節「被 lint 擋住時的無損候選」，內容照設計文件「無損候選清單」三張表：行主題、承接者、查證命令、預計省字數。
  - 行號一律改寫成條目主題，因為行號會漂移。
  - 開頭註明：取用前重新確認承接者仍在；第 116 行不在清單內。
- [x] **Step 6：全套。** 同 Task 2 Step 6；Expected：ALL GREEN。
- [x] **Step 7：Commit。**
  ```bash
  git -C <config-repo> add settings.json CLAUDE.md refs/subagent-model-tiers.md refs/claude-md-authoring.md refs/claude-code-capability-checks.md
  git -C <config-repo> commit -m "feat: register subagent-judgment-audit; CLAUDE.md names it as the second net; lossless trim candidates"
  ```

### Task 4: 自審與 PR

- [x] **Step 1：簡化。** 對本分支 diff 跑 `/simplify`，只動本次 diff。之後重跑 run-all，Expected：ALL GREEN。
- [x] **Step 2：程式碼審查。**
  - 先背景啟動 `/codex-review-bg`，子殼內先 `cd <config-repo>`。
  - 再跑 `/review-branch main`：repo 是 `<config-repo>`，`plan` 與 `resolve-rules` 帶 `--no-write`。
  - 兩者的 finding 都先進工作範圍帳本 triage，再決定修不修。
- [x] **Step 3：安全審查。** 內建 `/security-review` 不能指向這個 repo，所以改由主迴圈對分支 diff 做 inline 安全審查。重點：
  - hook 讀的路徑來自 hook 輸入，jq 與 perl 有沒有被注入的可能；
  - 輸出 JSON 是否一律由 `jq -n --arg` 組出，不用字串拼接。
- [x] **Step 4：Push 與開 PR。**
  - push 後用 `git rev-parse` 對 `git ls-remote` 比對 SHA；
  - PR body 用 `pr` skill 寫；
  - 跟到 CI 的 `suites` check 綠燈。
- [x] **Step 5：公開 repo。** 在 `<this-repo>` 開分支 `docs/w4-minimal-plan`，commit 設計文件與本計畫，開 PR。commit 不帶 session trailer，PR body 不附 session 連結。
- [x] **Step 6：等使用者說 merge。** 收到後走 pr-closeout。公開 repo 的純文件 PR，`ready` 會是 exit 4，照既有裁定帶 `PR_CLOSEOUT_OK=1`。合併後回填本計畫的勾選框與狀態行。

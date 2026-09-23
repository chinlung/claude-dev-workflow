# 變更日誌

本專案所有重要變更都將記錄在此檔案中。

格式基於 [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)，
並遵循 [語意化版本](https://semver.org/spec/v2.0.0.html)。
## [1.11.0] - 2026-09-23

### Added

- **scope-ledger 1.0.0** — 每個 goal 一份工作範圍帳本、每個 repo 一份 follow-ups backlog、六個 fail-open hook，讓 review 驅動的工作不會擴張超出原始請求，同時不讓真 bug 與安全 finding 被跳過。帳本（`.claude/scope-ledger.local.md`）記使用者原話、`mode`（converge，或 goal 本身是稽核／一批 finding 時的 harvest）、review 輪數與 In scope / Deferred / Log 三段；不綁分支，因為一個 goal 常橫跨 hotfix 與 PR 鏈。PreToolUse 在無帳本時把主代理的首次程式碼寫入 deny 一次——不論走 Edit/Write 還是 Bash 的 `sed -i`／`perl -pi`／heredoc 重導向／`cp`／`mv`／`patch`——並要求 `/scope-ledger:scope init`（子代理放行、不消耗那一次 deny）；UserPromptSubmit 每 session 提醒一次、不阻擋；PostToolUse 在每次 review 入口 skill 或 review 型子代理之後注入該 mode 的 triage 政策（converge：review 的產出是 input 不是工單——採納屬本次變更者、可利用的安全 finding、同缺陷 sibling、MUST 守則、boy-scout，其餘附嚴重度理由去處延後，dismiss 須附反證；harvest：finding 就是工單、依嚴重度分批），只有 allowlist 上的 skill 呼叫計一輪；Stop 在有未勾項時依狀態 block 一次、只要求回報狀態而非催工作；SessionStart 在 compaction 或 resume 後把 In scope 全段與 follow-ups 印回。`done` 把 Deferred 搬進 `.claude/scope-followups.local.md`，HIGH 安全項沒有 issue 或下一個 goal 不准延後。被 git 追蹤的帳本（含經 committed symlink 或 submodule 進入者）是 repo 控制的內容，所有 hook 一律忽略——Codex 跨 vendor pass 抓到初版會把被 commit 的檔案逐字回放進 context，push 前安全審查抓到該檢查的 symlink／submodule 繞過。依量測而非直覺設計：作者全部 session 歷史中 todo 工具零呼叫、一個四天的 session 跑了 23 次安全審查橫跨 17 個 PR、最後使用者在問那些 finding 編號是什麼；另一個有用 task 工具的 session，使用者仍五次問「還剩什麼」，因為 audit 的 backlog 活在任務清單之外。skills.sh 上沒有以 hook 強制的現成方案；最接近的 `piv-fix-review-findings` 是同一政策的 prose 版，本 plugin 採用它的四分類。276 條 fixture 斷言，bash 5 與 macOS bash 3.2（及純 BSD userland）皆綠，二十二個突變在副本上驗證轉紅。兩輪出貨前審查改了十四件事，每一件連同理由記在 plugin 自己的 CHANGELOG：第一輪（五個對抗式驗證子代理、Codex、push 前安全審查）——追蹤中帳本的處理與其 symlink／submodule 繞過、Agent 派發不計輪、以 allowlist 取代關鍵字字根、子代理放行、bump 加鎖、frontmatter 合成；第二輪對照作者自己的 session 歷史——帳本改 per goal 不綁分支、harvest 模式、follow-ups backlog 與「HIGH 須有去處」規則、四類採納例外與 dismiss 須附反證、Bash 寫入閘門與首則提示提醒、Stop 訊息改為依使用者最後指示、stale lock 自動清除；第二輪自己的審查又抓到——Codex 抓到 heredoc 標記後的重導向漏過 Bash 閘門，安全審查抓到追蹤檢查在 APFS 上被大小寫摺疊（`.Claude/…`）繞過、以及 `$TMPDIR` 旗標寫入無 symlink 檢查。設計：`docs/scope-ledger-design-2026-09-23.md`。

## [1.10.13] - 2026-09-19

### Fixed

- **根 README 的 session-learning 段完成去重，也修掉它累積的漂移。** 那一段長到 62 行，描述的 pipeline、層級路由與 hook 行為與 plugin 自己的 README 重複，而其中一份從 2026-08-03 起就是錯的：它把 Stop hook 描述成只有 transcript 長度門檻加一個 once-per-session flag，完全沒提 1.0.1 新增的 already-ran 偵測——那是該版本的主修復，在使用者看得到的文件裡缺了一個多月，直到這個 plugin 有了自己的 README 才被發現。兩份根 README 現在各是一段密實敘述（含該偵測）並連到 plugin README，這正是 `security-audit` 段早就採用的形狀，也落在其他段落 24 到 121 行的範圍內。只存在於根 README 的 Phase 1 候選表則**搬進** plugin README 而非刪掉——去重是搬移、不是刪除——搬之前逐列對照 `commands/save-session.md` 查核過。`session-reflect` 段一併補上指向自己 README 的連結。`CONTRIBUTING.md` §3 現在明訂「plugin 有自己的 README 時就寫摘要＋連結」，並把這次的漂移寫成理由，讓規則自帶依據。


## [1.10.12] - 2026-09-18

### Fixed

- **session-learning 1.0.1 → 1.0.2、session-reflect 1.0.1 → 1.0.2** —— 往既有 plugin 加文件，若不動該 plugin 的版號，已安裝的副本永遠拿不到。plugin cache 以版本為 key（`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`），版號不變就不會重新抓取。這點是實測而非推測：`session-reflect` 的 README 由 `c7c8169` 加入且未 bump，而 cache 的 `1.0.0/` 樹裡**沒有**它——只有 `1.0.1/` 有，因為後來的一次 bump 恰好把它帶了進去。所以那個前例並不是「純文件變更不需 bump」的證據，而是一個沒人發現的未出貨檔案。1.10.11 補的兩份 changelog、以及 session-learning 新加的 README 都處於這個狀態，故兩個 plugin 一併 bump 以交付它們。由 Codex 跨 vendor pass 就 README 提出；cache 的實測把範圍擴大到兩份 changelog。`CONTRIBUTING.md` §4 現在把規則連同機制一起寫明，讓「這只是文件」不再是跳過 bump 的理由。

- **前一個 commit 寫的那份 README 帶著一個活的自我抑制 bug，由自審在出貨前抓到。** 它的流程圖把 Stop hook 用來比對的執行形狀逐字寫了出來。那些形狀不含引號，在 JSONL 字串裡不會被轉義，於是 hook 的 `grep -Eq` 直接從 README 自己的內文命中——任何讀過該檔的 session 都被判定為「已經跑過 `/save-session`」，餘下全程不再提醒。這正是 session-learning 1.0.1 修掉的失敗，透過**使用者最可能打開的那個檔**換一道門重新引入；而同一份 README 還**宣稱**「merely mentioning the command never suppresses the reminder」——一個被它自己上面兩行反證的保證。修在三處，因為一處不夠：hook 的 pattern 綁在開頭的 JSON 界定引號上（真實呼叫有、散文沒有）、README 改成描述而不逐字寫、新增一條斷言把**實際的 README 檔**餵進 hook，讓未來的文件編輯若又寫進會命中的形狀會讓測試轉紅、而不是無聲解除提醒。同一份 README 還斷言兩個 session plugin「are not merged on purpose」，而這個意圖在本 repo 的任何 commit 或文件裡都沒有記錄——與本次要更正的「刻意不帶」是同一種形狀。現在它只說程式碼證明得了的事。
- **新閘門的收集與接線完全沒有 canary——四個針對它們的突變全部存活。** 把 symlink 清單 stub 成 `[]`、把 `isSymbolicLink()` 換成 `isFIFO()`、把 `readme` 寫死 `true`、以及在呼叫處丟掉第二個參數，四者都停在 203 passed / 0 failed，因為 canary 是把寫好的 map 餵給 `pluginDirProblems`：判斷被覆蓋了、收集沒有，而乾淨的 repo 兩種情況都不報。現在收集、地板與判斷都收進 `pluginDirGateProblems()` 一個呼叫之後，並由一棵 `mkdtemp` fixture 樹覆蓋（一個完整 plugin、一個缺 README、一個 README.md 是**目錄**、一個半成品、一個 symlink、一個斷鏈 symlink、一個普通檔案），斷言 inventory 與端到端的 problem 清單。六個突變全死。同一份工作順便揪出兩個真缺陷：`existsSync` 會接受名為 README.md 的**目錄**——而 README.md 正是三個必須檔案中唯一沒有下游讀者會撞到的那個——以及在大小寫不敏感的 APFS 上它會接受 `readme.md`，而 CI 的大小寫敏感檔案系統會拒絕（本機綠、CI 紅）。兩者現在都走 `statSync().isFile()` 加一次 readdir 檔名比對。
- 同一輪一併更正：「對五個 repo 結構閘門全部隱形」是錯的——版本閘門走的是 marketplace **entries**、用會跟隨 symlink 的 API 解析，所以它看得見 symlink plugin；只有走 `pluginDirs` 的那四個會跳過（閘門自己的訊息寫對了，是周邊散文誇大）。`CONTRIBUTING.md` §1 的範本現在把 `README.md` 與 `CHANGELOG.md` 標為必須，並列出 `commands/`、`hooks/`、`agents/`、`tests/`——閘門的錯誤訊息把貢獻者指向這份範本當權威，而它原本並不承載被引用的那條規則。另外還有：README 的 Phase 3（原本列了五個去重來源中的三個，漏掉的正是它自己表格列為目的地的兩個 `commands/` 目錄）、一句已涵蓋三條規則卻還寫「兩條」的註解、一份對「README 是否必須」自相矛盾的 docblock、實際上會 block 一次卻寫成「one-line nudge」、`$TMPDIR` → `${TMPDIR:-/tmp}`、缺少的 Testing 段，以及一句對 repo 內部 symlink 宣稱其目標「不在 denyWrite 涵蓋範圍」而實際上字面規則已涵蓋的訊息。

## [1.10.11] - 2026-09-18

### Added

- **code-audit-rigor 2.0.3 → 2.0.4、multi-agent-debate 1.2.0 → 1.2.1** —— `/review-branch`、`/review-pr`、`/debate` 現在都會在繼續前機器檢查自己的輸出產物是否已被 git ignore：`git check-ignore -q -- <產物>; echo "check-ignore rc=$?"`，三種 exit code 各有處置——`0` 已 ignore → 繼續；`1` 未 ignore → 先用 `git ls-files --error-unmatch` 問「是否已被**追蹤**」，因為對已追蹤的檔案加 `.gitignore` 一行是無效的、得先 `git rm --cached`；`128` 不在 git repo 或 git 本身失敗（bare repo、路徑在 worktree 外、`GIT_DIR` 壞掉）→ 跳過、不視為錯誤。`rc` 刻意用 `echo` 印出：`-q` 不印任何東西，而結尾的 `; RC=$?` 賦值本身 exit 0，會讓三種狀態都以一模一樣的「exit 0、無輸出」抵達 agent、於是預設放行——本次變更的第一版正是這樣寫的，交付的步驟其實是個靜默 no-op，由自審抓出。三個命令都不會自行修改 `.gitignore`——那是專案自己的設定。先前三者都把這件事外包給「每個專案加一行」，也就是外包給記性，而本 repo 正是它撐不住的證據：`review-branch-results.json` 直到 1.10.10 才補上那一行，`review-pr-comments.json` 與 `debate-output.json` 則從未被 ignore 過——本次第一輪只修了三者中的兩個，漏掉的那個由覆蓋核對掃出。現在三者全部涵蓋；`prior-debate.json` 刻意排除，它是下一輪 `/debate` 的輸入、不是一次性產物。由本次 session 的 `/session-reflect:reflect` 發現，其對抗式驗證者並駁回了原本「把產物搬到別處」的提案：`.gitignore` 沒有前導斜線的條目在任意深度都 match，故既有那一行已經涵蓋搬家後的副本——搬家並不能擺脫對 `.gitignore` 設定的依賴，而唯一免設定的位置在 worktree 之外，那裡 `$TMPDIR` 在 sandbox 內外是不同目錄。細節見各 plugin 的 CHANGELOG。

### Fixed

- 兩份根 README 都列著可直接複製執行的 `node plugins/high-precision-dev/validators/validate-high-precision-output.cjs …`。該 validator 在 high-precision-dev 1.1.0 已作為死碼移除（原因見該 plugin 自己的 CHANGELOG：它驗的 JSON 形狀從來沒有任何 agent 產出過），但移除沒同步到根 README，照著做就撞到檔案不存在。與 1.10.9 修掉的 codegraph npm 連結是同一種形狀：plugin 層的修復留下根文件指向已不存在的東西。現在根文件與 `CONTRIBUTING.md` 提到的每一個 `plugins/**.cjs` 路徑都在磁碟上存在（整批掃過，非抽樣）。
- **本次發布對兩個 plugin 下的一個斷言從未查證，而且是錯的。** changelog 閘門會跳過沒有 `CHANGELOG.md` 的 plugin，而程式碼註解與 `CONTRIBUTING.md` 把 session-learning、session-reflect 描述成**刻意**不帶。沒有任何證據支持這個讀法：`CONTRIBUTING.md` 自己的目錄範本就列著 `CHANGELOG.md`、§4 把 plugin changelog 列為版號落腳的三處之一、沒有任何 commit 記錄過這種決定，而且 repo 的前例正好相反——`e4a2729` 一發現 high-precision-dev 與 multi-agent-debate 沒有 CHANGELOG，當下就補了 1.0.0 條目。這兩個 plugin 只是被漏掉，而那句斷言把疏漏寫成了制度。兩份 changelog 已依根 CHANGELOG 與 git 歷史補齊（並標明是事後補寫），第五個 repo 結構閘門則強制目錄完整性：有 `plugin.json` 的目錄一律要有 `CHANGELOG.md`，而帶著 `CHANGELOG.md`／`commands/`／`skills/` 卻沒有 `plugin.json` 的目錄判為未完成。這關掉了 reflect backlog 擱置的兩個盲區——刪掉 plugin changelog 會無聲解除 changelog 閘門（`rm` 走 Bash，而 PostToolUse hook 只看 Edit／Write／MultiEdit），以及半成品 plugin 目錄對所有閘門都隱形（版本閘門走 marketplace entries、註冊閘門只收已有 manifest 的目錄）。兩個方向都對真實 repo 的副本做過突變驗證：移走 `plugins/codegraph/CHANGELOG.md`、以及植入沒有 manifest 的 `plugins/zztest/`，都會讓新閘門轉紅，而四個既有閘門維持綠。測試 176 → 185（8 個 canary + 1 個 live check），red-first。補 changelog 與新閘門都不改變任何 plugin 的行為，故不動版號。
- **那個閘門的 canary 同樣撐不住它 —— 15 個突變、10 個存活。** 自審對 `pluginDirProblems` 做了十五種突變並每次在副本上實跑：半成品分支 push 後 `break`、「已有問題就跳過」、提早 return、`parts.join(' + ')` 退化成 `parts[0]`、半成品訊息換成**完全相反的失敗模式**、拿掉目錄名前綴、以及刪掉覆蓋地板或讓它恆偽——全都停在 185 passed / 0 failed。三個成因現已各自關閉：名為「one broken dir does not mask another」的 case 只放了一個壞目錄，期望值 1 不論能不能報出第二個都成立（而且每種各一個仍不夠——半成品分支的 `break` 要有**兩個**目錄走到它才看得出來，故該 case 現在每種壞法各兩個再加一個乾淨的）；兩個分支只有一個有整句訊息斷言，所以意思相反的訊息照樣綠燈；地板是個 inline `if`，沒有人守衛守衛本身——現已抽成 `shapedCountProblems()` 並配四個自己的 canary。`parts` 也只列了本 repo 實際出貨的八種 component 中的三種，讓 `agents/`、`hooks/`、`README.md` 與「有 `.claude-plugin/` 卻沒有 `plugin.json`」四種全部隱形；其中 `hooks/` 影響最大，因為 `plugins/<p>/hooks/*` 正是 denyWrite 閘門列舉為**會被執行**的集合，沒有 manifest 的 hooks 目錄會被執行、卻被算成「不是 plugin」。測試 185 → 194。boy-scout（既有問題）：名為 `commands` 的**檔案**能通過 `existsSync`，使 collision 閘門的 `readdirSync` 拋出 ENOTDIR，整輪中止且沒有 Summary、沒有失敗清單——兩處呼叫改用 stat 語意。`dirShapes` 改為 `Object.create(null)`，`plugins/__proto__/` 目錄因此是一個 key 而非一次原型寫入。
- **reflect backlog 剩下的兩個盲區已關閉，且當初關閉它們的那套論證現在被一致地套用。** 身為 *symlink* 的 plugin 目錄對**走 `pluginDirs` 的那四個**閘門隱形——`Dirent.isDirectory()` 是 lstat 語意、對 symlink 回 false，所以 collision、目錄完整性、plugin changelog、註冊四個閘門都直接跳過這種 plugin。（不是五個：版本閘門走的是 marketplace **entries**，並用 `path.resolve` + `existsSync`／`readFileSync` 解析，這些 API 會跟隨 symlink，所以它看得見。閘門自己的訊息與 docblock 寫的是「every gate that walks pluginDirs」、本來就精確；只有周邊散文誇大成「五個」，由自審實測抓出。）symlink 形式的 plugin 目錄現在是**拒絕**而非支援：本機 hook 執行 `plugins/<p>/tests/*.test.sh` 時會跟隨 symlink，接受它等於為本 repo 根本沒有的用例擴大執行面。（自審也糾正了 backlog 自己的描述：pre-existing 的 denyWrite 閘門其實早就會抓到這種目錄，只是換了個名字——現在兩者都會報，訊息互補。）另外 `README.md` 現在對每個 plugin 都是必須，理由與前一個 commit 要求 `CHANGELOG.md` 的完全相同——CONTRIBUTING §1 的範本兩者並列，只把 `.mcp.json`／`reference.md` 標為選用——所以唯一缺 README 的 session-learning 補上了一份，內容取自它自己的 manifest、command 與 hook，不是憑印象寫的。只用一半的推理，正是「刻意不帶」那個斷言最初的成因。兩條規則都對副本做過突變驗證：symlink 的 `plugins/ghost` 與移走的 `plugins/codegraph/README.md` 都會讓閘門轉紅並點名該目錄。測試 194 → 203；每個新分支都配兩個 canary 輸入（一個抓不到 `break`）外加一個整句訊息斷言。

## [1.10.10] - 2026-09-18

### Fixed

- **code-audit-rigor 2.0.2 → 2.0.3** — 調用鏈追蹤在三處把 `codegraph_callers`／`codegraph_impact` 寫成 MCP 工具（skill 的工具選擇註記、`/review-branch` Phase 2 第 3 步、`STEEL_MANNING.md` 的 OC-1 檢查）。codegraph 預設只把 `codegraph_explore` 列為 MCP 工具，那些呼叫會回 "not found"；三處改為指名 CLI 指令，並說明 "not found" 代表未列出、不是壞掉。`/review-branch` 的恢復條件一併修正——原本把 grep fallback 綁在「無索引」，但這個失敗發生在索引健康的情況下。此問題自 2026-06-08 起存在、且出貨當天就與同 repo 的 codegraph 文件自相矛盾；由 1.10.9 的 codegraph 基準更新才浮現。細節見 `plugins/code-audit-rigor/CHANGELOG.md`。

### Notes

- Marketplace patch 版號 1.10.9 → 1.10.10。
- `.gitignore` 新增涵蓋 `/review-branch` 的輸出產物 `review-branch-results.json`。
- Repo 基礎設施（不改任何 plugin 的出貨行為，故不再 bump）：第四個 repo 結構閘門，**plugin changelog 記帳** —— 每個存在的 `plugins/<p>/CHANGELOG.md` 最上面的 `## [x.y.z]` 須等於該 plugin 自己的 `plugin.json` 版號，並適用與根 CHANGELOG 相同的 semver／不重複／嚴格遞減規則；當時不帶 changelog 的 plugin（session-learning、session-reflect）跳過、不強制（該前提已於 1.10.11 推翻，見上）。原版本閘門結構上無法涵蓋這件事——它把收到的每份 changelog 都拿 `metadata.version`（marketplace 的版號，不是 plugin 的）比對——所以 `plugins/<p>/CHANGELOG.md` 從不被任何閘門或 hook 讀取，`CONTRIBUTING.md` 把這點記為已知範圍限制。它已經付過兩次代價：dev-workflow 先後出貨 1.1.0 與 1.1.1，而 CHANGELOG 頂部還是 `[1.0.1]`（dfe8c1b／c920bd9，2026-03-07），5 天後才由 35c0a9c 人工發現，其修法是把版號**往下** revert 去對齊——而那次 revert 又把 description 一起 revert 錯，再過一個月才被 0631b24 抓到。現在兩份根 CHANGELOG 與每個 plugin 的都共用同一個 heading 規則函式，兩套規則不會再各自漂移。測試 167 → 175（7 個 canary + 1 個 live check），red-first，並對真實 repo 做突變驗證：只把 `plugins/codegraph/CHANGELOG.md` 的頂部標題改成 `[1.0.2]`，新閘門會點名該檔轉紅，而舊版本閘門維持綠——這個漂移對它是隱形的。本機 PostToolUse hook 現在也會在 `plugins/<p>/CHANGELOG.md` 觸發（斷言 22 → 23，red-first；`docs/CHANGELOG.md` 與 plugin 內部的 `marketplace.json` 仍為 no-op）。 閘門自身的保護力也經機器檢查：canary 是用手寫 map 驅動純函式的，所以當收集迴圈被突變成「什麼都收不到」時它們全部仍綠（175 passed、0 failed——一個已經悄悄停止讀取任何東西的閘門）。現在有一道**獨立於該迴圈**計算的覆蓋率地板，會逐一點名磁碟上它沒讀到的 changelog，同一個突變因此轉紅；另有一個 canary 斷言完整訊息而非只數數量，因為指錯檔案、或把權威寫成 `metadata.version` 而非 `plugin.json`，回傳的問題數同樣是 1。非字串的 `version` 改為回報而非跳過：版本閘門用 `!==` 比對 entry 與 manifest，一次正則換版若把兩邊的引號都吃掉，兩者會比對相等而放行，該 plugin 的 changelog 就沒有任何人在檢查了。

## [1.10.9] - 2026-09-18

### Changed

- **codegraph 1.0.1 → 1.1.0** — skill 改以 codegraph CLI 1.6.0 為基準（原為 0.9.7）。上游 MCP server 現在預設只列出 `codegraph_explore`；`codegraph_trace`／`codegraph_context` 已移除，`explore`／`node` 多了 CLI 指令。skill 的入口對照表有四格錯誤，動作觸發段點名的三個 MCP 工具在預設的 1.6.0 server 上叫不到。全段以「一個 MCP 工具、其餘走 CLI」為骨架重寫。可靠性 fallback 不再於工具回 "not found" 時叫 agent 重試或跑 `codegraph init`（該工具是未列出或已移除、不是壞掉；建索引是使用者的決定）。`reference.md`：`init` 取代已 deprecated 的 `init -i`、allowlist 刪到只剩解析得到的項目、新增 `CODEGRAPH_MCP_TOOLS` 一節、新增 gotcha（`<未知子命令> --help` 回 exit 0）。細節與**未**重驗的項目見 `plugins/codegraph/CHANGELOG.md`。

### Fixed

- 根 README（中英文）：所有 codegraph npm 連結與前置需求改為指名帶 scope 的 `@colbymchenry/codegraph`。原有三個連結（英文兩處、中文一處）仍指向未加 scope 的 `codegraph` npm 套件——正是 codegraph 1.0.1 從 plugin 自身文件移除的那個不相干佔位套件；當時改了 plugin 內四處，沒改到根 README。

### Notes

- Marketplace patch 版號 1.10.8 → 1.10.9。
- 根 README（中英文）與 plugin README 同步新的入口對照表與動作觸發。

## [1.10.8] - 2026-09-17

### Fixed

- **session-reflect 1.0.0 → 1.0.1** — 回顧 playbook 現在真的會被載入。plugin 同時附了 `commands/reflect.md` 與 `skills/reflect/SKILL.md`，兩者解析成同一個限定名稱 `session-reflect:reflect`；command 遮蔽了 skill（skill 清單只出現一條、描述是 command 的），於是以 Skill 工具呼叫時拿到的是 command 內文——而它唯一的內容就是「去呼叫 `session-reflect:reflect` skill」——playbook 從未載入。手動路徑與 Stop hook 路徑（`reflect-gate.sh` 要求的正是同一個 skill 名稱）都撞上這個自我指涉，模型只能自行找出 `SKILL.md` 手動 Read。移除多餘的 command：skill 預設即可由使用者呼叫（`/session-reflect:reflect`），且 `skills/` 是文件記載的新 plugin 標準結構。限定名稱不變，故閘門的已回顧偵測 pattern（`"skill":"session-reflect:reflect"`）與 `tests/gate.test.sh` 皆無須更動。

### Notes

- Marketplace patch 版號 1.10.7 → 1.10.8。
- README（根目錄中英文與 plugin 自身）的手動觸發指令改寫為限定名稱 `/session-reflect:reflect`，不再使用裸 `/reflect`。
- 已端到端驗證（2026-09-17）：安裝 1.0.1 並重載 plugin 後，以 Skill 工具呼叫 `session-reflect:reflect` 回傳的是 playbook 本體（base directory 為 `…/session-reflect/1.0.1/skills/reflect`），skill 清單的描述也換成 SKILL.md 的。同一個 session 一小時前才在 1.0.0 上重現過此 bug——同一個呼叫只回傳 command 那兩行自我指涉——所以前後是同條件對照。尚未實跑：1.0.1 下由 Stop hook 觸發的路徑（閘門每 session 只觸發一次、當時已用掉）；它要求的是同一個限定名稱，解析結果相同。
- Repo 基礎設施（無任何 plugin 的出貨行為改變，故不另 bump）：`scripts/validate-fixtures.cjs` 新增兩道 repo 結構閘門，皆由本次發版過程暴露。**command／skill 同名碰撞**——plugin 內 `commands/<X>.md` 與有效名稱（frontmatter `name`，缺省為目錄名）為 `<X>` 的 skill 並存即失敗；`claude plugin validate` 對這種結構回 passed，1.0.0 的 bug 正是這樣出貨的。**版本記帳**——每個 marketplace entry 須等於其 `plugin.json`、`metadata.version` 須等於兩份根 CHANGELOG 的頂端標題、標題須為 x.y.z 且不重複、嚴格遞減。本次發版最初做在落後 3 個 commit 的基底上，宣稱的 1.10.7 已被遠端用掉；整合時 `marketplace.json` 因兩邊都做了相同的 `1.10.6→1.10.7` 編輯而被 git **靜默**自動合併、停在錯的版號。「不重複」規則之所以存在：只比頂端標題會漏掉「保留兩個 `[1.10.7]` 段落」的解法。suite 130 → 139（7 條餵植入缺陷的 canary＋2 條 live 檢查）；每道閘門另對真實 repo 做突變驗證（放回遮蔽 command、退回 metadata、重複標題、只 bump `plugin.json`——全紅、還原後全綠）。已知殘餘：兩個 release 被併進同一段落，靜態檢查抓不到。
- 第三道閘門，**marketplace 註冊**：每個有 `plugin.json` 的 `plugins/<p>/` 都必須被某個 marketplace entry 的 `source` 指到，且該 entry 的 `name` 須等於 manifest 的 `name`。版本閘門走的是 *entries*，沒人註冊的 plugin 它根本看不到（自審時判為範圍擴充、先記入 reflect backlog，同日完成）。`marketplace.json` 讀不了時只回報一筆「cannot evaluate」，不會連鎖噴出九個假孤兒。「讀不了」與「讀得了但沒有 name」刻意分開表示（只有前者跳過，且名稱比對用顯式 `typeof`——用裸 `!==` 的話，entry 與 manifest 同時缺 name 會被當成相等），marketplace 的形狀也為兩道閘門統一正規化一次，讓「JSON 合法但形狀錯」（`plugins` 是物件、含 `null` 元素、manifest 內容為 `null`）變成一筆具名的 ✗，而不是丟掉 Summary 的 `TypeError`；形狀不對的元素一律回報、絕不靜默濾掉。suite 139 → 146（6 條 canary＋1 條 live 檢查），兩度紅燈先行——兩次紅燈都是剛擴充的本地 hook 自己送達；並對真實 repo 做突變驗證（孤兒目錄、manifest 壞掉的孤兒、manifest 改名、manifest 缺 `name`／key 打錯、marketplace 壞掉／`plugins` 為物件／含 `null` 元素、manifest 為 `null`）。
- 本地 PostToolUse 閘門現亦於上述閘門**實際讀取**的檔案被編輯時觸發（`plugins/<p>/commands/*.md`、`plugins/<p>/skills/<s>/SKILL.md`、`plugins/<p>/.claude-plugin/plugin.json`、根 `marketplace.json`、兩份根 CHANGELOG）；先前這類編輯只有 CI 會擋。比對採 root-relative 全錨定：初版是子字串比對，自審實測它會對 `~/.claude/commands/*.md` 白跑一整輪約 5 秒的 suite——而即使改成 `/plugins/<p>/commands/` 子字串錨定，仍會匹配到 `~/.claude/plugins/marketplaces/` 下的 marketplace 快取 clone。其測試 9 → 22 條斷言，紅燈先行（四條負向案例已確認對未錨定版本為紅）。
- 版本閘門載入 manifest／CHANGELOG 失敗時，改為回報一筆指名檔案的 ✗ 並繼續跑——該區塊排在所有 fixture 檢查之前，且 hook 現在會在編輯 manifest 時觸發它；未捕捉的 `SyntaxError` 會丟掉 Summary 與其後約 120 條檢查，還看不出九個 `plugin.json` 是哪一個壞。entry 的 manifest 改依各 entry 自己的 `source` 解析。
- 四個 bash suite 的暫存目錄改用帶模板的 `mktemp -d "${TMPDIR%/}/<name>.XXXXXX"`。macOS 上無模板的 `mktemp -d` 不理會 `$TMPDIR`、落到 `/var/folders/…/T/`，被 Claude Code sandbox 拒寫——每個 suite 在第一條斷言之前就 exit 1，而假紅發生的路徑（agent 於 commit 前自跑驗證）正是 exit code 即判決之處。斷言內容零變更。
- `.claude/settings.json` 現以 `sandbox.filesystem.denyWrite` 列出本地 hook 的完整「被執行閉包」（`scripts`、`plugins/*/tests`、`plugins/*/hooks`、`plugins/*/validators`，外加兩個放在 `skills/` 底下的 validator）。該 hook 由 harness 在 agent 的 Bash sandbox **之外**、以開發者權限執行，而它跑的一切原本都能從 sandbox **之內**寫入——一次自動放行的 sandbox 內寫入，可以換到 sandbox 外的執行。由註冊閘門那次安全審查指出（屬既有問題、非該次引入）；使用者層設定早已對 `~/.claude/scripts` 套用同一條規則。這些檔案的修改自此走 Edit／Write 工具及其權限確認。已實測：字面、glob、深層條目皆擋下（含新建檔案），對照路徑（README、SKILL.md、CHANGELOG）仍可寫，且各 suite 只寫 `$TMPDIR`、全數仍通過。已實測的代價：git 同樣是 sandbox 內的行程，`pull`／`merge`／`checkout`／`stash pop` 若需改寫這些檔案會半途失敗（`unable to unlink old …: Operation not permitted`），工作樹未變但 index 已更新——這類操作須在 sandbox 外跑，復原用 `git reset HEAD -- <path>`。同日已機器化：runner 的最後一項檢查蒐集 hook 最終會執行到的每個檔案——settings 裡各 command hook 指到的腳本、runner 自己、runner **實際 spawn 過**的每個 validator（在兩個 spawn 點記錄，而非掃自己的原始碼）、以及 `plugins/*/{tests,hooks}` 下的測試套件與 hook 腳本（枚舉方式與 hook 一致：依名稱、會穿過 symlink）——並要求每一個都被某條 `denyWrite` 涵蓋。凡是驗不了的一律 fail-closed、不猜：pattern 只認得 root-relative 字面路徑與單一路徑層級的 `*`；hook 指令只認得 `node "$CLAUDE_PROJECT_DIR/<path>"` 這一種形狀（獨立的對抗式審查指出初版的問題：它從指令字串擷取「長得像腳本」的 token 並丟掉不存在的，於是對串接 `&& node …/typo-missing.cjs` 的指令照樣綠燈——而在這個威脅模型下，「**還**不存在」的路徑是最糟的情況，不是無害的）；symlink 形式的 plugin 目錄、`tests/` 目錄或 suite 檔會被回報，因為 hook 會穿過它。suite 146 → 167（20 條 canary＋1 條 live 檢查），全程紅燈先行；突變驗證對的是 settings 的**副本**，live 保護從未被鬆開。hook 現在也會在 `.claude/settings.json` 被編輯時觸發（其測試 22 → 23）。**綠燈不代表什麼**——以下來自閱讀 2.1.274 binary 內 sandbox runtime 的規則產生器：(1) 它驗的是設定、不是實際強制，CI 沒有 sandbox；(2) 在 Linux／WSL 上 runtime 會**丟掉所有帶 glob 的寫入條目**，那三條 `plugins/*/…` 在那裡什麼都沒保護；(3) glob 條目只擋匹配其 regex 的路徑，所以把一個已含 `tests/` 的目錄改名搬**進** `plugins/` 不會被擋，只靠 glob 保護的 plugin 目錄本身也能被改名移走——此為**讀規則所得、未經執行**（sandbox 內的探測兩度被權限分類器拒絕）。字面條目沒有上述任何一個洞。同日已解決——見下一條。
- `sandbox.filesystem.denyWrite` 改為兩條字面路徑——`scripts`、`plugins`——且閘門對任何含 `*` 的條目判紅。改法是被實測逼出來的，不是憑感覺：在三條 glob 生效時，於 sandbox 內 `mv <已含 tests/ 的目錄> plugins/zzp` **成功**（rename 只檢查目的路徑，沒有任何三層 regex 匹配到它，整棵子樹未經檢查跟著進來）。改完後同一個 `mv` 得到 `Operation not permitted`；在 `plugins/` 下建 symlink、寫 `plugins/<p>/README.md`／`plugin.json`／`SKILL.md`亦皆被擋。寫 `.git/hooks/pre-commit` 同樣被擋，但那是 runtime 自己的強制規則（`**/.git/hooks/**`，連同 `.git/config`），不是這裡的條目——曾短暫列入 `.git/hooks` 一條，安全審查指出它多餘、且「探測被擋」證明不了它有作用，故移除。根目錄檔案（`README.md`、`CHANGELOG.md`、`marketplace.json`）仍可寫。字面條目在 Linux／WSL 上也不會被 runtime 丟掉。紅燈先行：收緊後的閘門在設定尚未改時對舊設定轉紅（三條 glob 被拒、12 個檔被點名未涵蓋），設定改後轉綠；把 glob 加回去的副本突變為紅。suite 維持 167。已接受的代價：`plugins/` 下所有檔案對 agent 只能用 Edit／Write；sandbox 內的 git 若需改寫 `scripts/`、`plugins/` 下任何檔案會半途失敗（復原法見 CONTRIBUTING §6.5）；對 manifest 的突變驗證改用 `$TMPDIR` 副本。

## [1.10.7] - 2026-09-14

### Changed

- **openspec-superpowers-workflow 1.4.2 → 1.5.0** — `review-notes.md` 不再建空檔，改預填語意標頭（條目格式、tag 集合、「Y = Phase 6 須更新某 OpenSpec artifact，絕非『已處理』」）；Phase 5 被明確要求「現在改 spec」時必須明講拒絕，不得默默改道；`[CODE] Y` 宣告不存在、`[CONSTITUTION]` 限用於新增跨功能規則；「tag 看修改落點」提升到 SKILL.md 硬規則 1。依據：兩專案 62 份真實歸檔 change（54 條 `[CODE] Y`，其中 30 條在 1.3.1 規則之後）＋本機 eval suite 在 1.4.2 重現兩種失敗（誤導標頭題載入 plugin 仍 3/3 中招；默默改道 1/3）。

### Notes

- Marketplace patch bump 1.10.6 → 1.10.7。

## [1.10.6] - 2026-09-02

### Fixed

- **code-audit-rigor 2.0.0 → 2.0.1** — `/review-branch` 的審查範圍納入工作樹。前置清單原本只取已 commit 的 `merge-base...HEAD` diff，commit 前自審時最新的未 commit 工作被沉默略過、覆蓋核對表卻仍全綠（表只跟餵它的機械清單一樣完整，清單漏一個來源就一起錯）。範圍改為已 commit diff ∪ `git diff --name-only HEAD` ∪ untracked（`--focus` 三者皆套用）；被刪除的檔案維持 reviewed、不自動 skipped；每個檔案記錄**必填**的 `source`（`committed`／`working-tree`／`untracked`——缺值即 validator 拒收，schema↔validator 一致性閘門釘住 enum）。skill 的 Phase 1 同步對齊三個來源。suite 125 → 130 條，紅燈先行確認。

## [1.10.5] - 2026-08-13

### Changed

- **openspec-superpowers-workflow 1.4.1 → 1.4.2** — 批次窗在非 BSD `stat` 下存活。BSD 優先的 `stat -f %m` 在 GNU/uutils（Ubuntu CI；macOS 上被 nix devshell 遮蔽的 `stat`）會「成功」輸出非數字（`-f` 是 filesystem 模式），fallback 被跳過、非數字進入算術展開——`set -u` 下展開錯誤不走 ERR trap，hook 以 exit 1 崩潰（harness 視為 non-blocking 放行編輯，批次窗在這類機器上實質失效）。一小時內被兩層機器閘門逮到：CI 紅（斷言 3a）＋首次 live 實測（`列 64: File: 未綁定的變數`）。修法：改 `-c %Y` 優先、`-f %m` fallback，兩運算元過純數字白名單——非數字一律優雅降級放行而非崩潰。測試增至 24 條斷言，fake-stat 案例釘死雙向契約。

### Notes

- Marketplace patch bump 1.10.4 → 1.10.5。

## [1.10.4] - 2026-08-13

### Changed

- **openspec-superpowers-workflow 1.4.0 → 1.4.1** — frontmatter 改為 strict-YAML 合法（description 以雙引號包裹；unquoted scalar 內 "touches none of: public API" 的 colon+space 自 1.3.0 起即令 `claude plugin validate --strict` 失敗，而寬鬆的 runtime 實際載入正常）。引號安全性由 live 前例證實（superpowers 的 brainstorming 磁碟帶引號、清單顯示無引號）；`--strict` 現通過，內容 byte-identical。

### Notes

- Marketplace patch bump 1.10.3 → 1.10.4。
- Repo 基礎設施：本地 PostToolUse 閘門（`scripts/hooks/validate-on-plugin-edit.cjs`）現亦於 `hooks/` 編輯時觸發，並在 node runner 之外執行所有 `plugins/*/tests/*.test.sh` bash suite——先前 bash hook 邏輯僅在 CI 有機器閘門，hook 壞掉要到 push 才現形。自帶 9 條斷言測試（`scripts/hooks/validate-on-plugin-edit.test.sh`）接入 CI。

## [1.10.3] - 2026-08-13

### Changed

- **openspec-superpowers-workflow 1.3.1 → 1.4.0** — skip-gate PreToolUse hook＋SKIP 條款程序化。一次真實 session 憑 CLAUDE.md 一行摘要句自由心證「無契約面」而繞過六階段 workflow——變更實際觸碰正典 spec 明載的跨模組行為，且落在已 spec 化能力域。根因：SKIP 是「以不動作達成」的隱式決策，沒有任何 artifact 逼八項契約面核對真的發生。plugin 現出貨 PreToolUse hook：openspec 專案無 active change 時，deny 本 session 首次程式碼編輯並要求逐項明示結論後重試，附 5 秒批次窗讓同一並行批次的手足編輯一併被攔（所有錯誤路徑 fail-open；`openspec/`、`.claude/` 與專案外路徑豁免；20 條斷言測試接 CI，關鍵保護經 mutation 驗證）。SKIP 條款同步宣告「未明示核對的跳過＝流程違規」，並補上「行為落在 `openspec/specs/` 已涵蓋能力域」訊號——可查證的環境事實，優先於自由心證。

### Notes

- Marketplace patch bump 1.10.2 → 1.10.3。

## [1.10.2] - 2026-08-08

### Changed

- **openspec-superpowers-workflow 1.3.0 → 1.3.1** — review-notes 標籤判準明確化：**以修正落點的 artifact 歸類，而非問題的性質**。與 spec scenario 字面敘述衝突的設計決策應標 `[REQUIREMENT]`（spec 才是要被改的檔案）——C1 閘門嚴格依標籤路由且禁止 `[DESIGN]` 更新 `specs/`。判準寫在 `phases.md` 的標籤書寫現場（Phase 4/5，context 最新鮮處），並在 C1 新增「修正路徑」段落，把「reconcile 時發現誤標 → 修正標籤附註記再處理」制度化（危險的替代路徑——遷就誤標而跳過 spec 更新——會把 spec 與實作的分歧歸檔成 `openspec/specs/` 裡永久的錯誤真相來源）。源自一次真實 Phase 6 執行中的兩筆現場重新歸類。

### Notes

- Marketplace patch bump 1.10.1 → 1.10.2。

## [1.10.1] - 2026-08-03

### 變更

- **session-learning 1.0.0 → 1.0.1** — save-session 提醒強化，回移植 session-reflect 於 1.10.0 出貨時的同類修復。原「已執行過 /save-session」的 grep 會匹配任何**提及**該字串的內容（討論、CLAUDE.md 注入、Read 本 plugin 檔案的輸出——實測某 session 62 次命中、零次實際執行），導致提醒被永久抑制；pattern 現只匹配真實執行形狀（`<command-name>/save-session</command-name>`、namespaced 變體、`"skill":"session-learning:save-session"` 呼叫形——皆經真實 transcript 驗證）。同時移除 Stop hook 的無效 `matcher` 欄位，新增 11 條斷言的 fixture 測試（`tests/reminder.test.sh`）並接入 CI。此問題由 session-reflect plugin 自身回顧流程的首次（手動）試跑發現。

### 備註

- Marketplace patch bump 1.10.0 → 1.10.1。

## [1.10.0] - 2026-08-03

### 新增

- **session-reflect 1.0.0**（新 plugin）— session 收尾回顧建議系統。fail-open 的 bash Stop hook 閘門（`stop_hook_active` 防迴圈、一 session 一次 flag file、<10 行實質性門檻、互動中偵測——讓路且不消耗唯一一次觸發權）交棒給兩段式 skill：快速 triage（routine session 一句「無需回顧」退出），再以四視角掃描（範圍外發現/既有問題/延伸優化/知識缺口）。候選建議必須先通過驗證層才會呈現給使用者：inline 四濾鏡自我反思（錨點親自 Read、已有防護、刻意設計、價值實在）+ 一個對抗式 verifier 子代理（繼承主迴圈模型、不降級），任務框架是反駁而非確認。最多 5 個存活建議以 multi-select 問卷呈現——選中即於本 session 執行，未選寫入 `.claude/reflect-backlog.md`（`[rejected]` 項永久保留作去重依據；plugin 永不自行 commit backlog）。閘門由 18 條 fixture 斷言覆蓋並接入 CI（`tests/gate.test.sh`）。設計文件：`docs/session-reflect-design-2026-08-03.md`。

### 備註

- Marketplace minor bump 1.9.1 → 1.10.0（新增 plugin）。

## [1.9.1] - 2026-07-26

### 變更

- **openspec-superpowers-workflow 1.2.2 → 1.3.0** — SKIP 條款自「small bug fixes with no spec impact」銳化為明確的契約風險 rubric（public API / data contract / schema / migration / 向後相容 / 安全權限邊界 / 並行一致性 / 跨模組行為；以契約風險判斷，LOC / 檔案數非判準）。放在 skill 描述是因為 auto-trigger 的跳過判斷就發生在那裡——對所有安裝者自包含。`PHASE-IDENTIFICATION.md` 與根 README 同步為相同語言。

## [1.9.0] - 2026-07-26

### 變更

- **code-audit-rigor 1.5.0 → 2.0.0**（BREAKING）— `/audit-review-fix` 及其整組實作（workflow script、command、schema、validator、14 個 fixture）退役移除。理由是與 `claude-security` plugin 的 *suggest-patches* 功能重疊，而後者風險模型嚴格更優：產出 patch 檔由使用者自行審閱套用（不套用等於沒發生），而非一次 ~86 sub-agents（~400k tokens）直接改寫原始碼（回退需 `git revert`）。`/review-branch`、`/review-pr` 與 rigor skill 保留——它們以「正確性」為判準（邏輯錯誤、可維護性、測試覆蓋），這一層是以「可利用性」為判準的安全工具不涵蓋的。`scripts/validate-fixtures.cjs` 同步更新，套件全綠（125 passed, 0 failed）。遷移路徑見該 plugin 的 CHANGELOG [2.0.0]。

## [1.8.11] - 2026-07-02

### 變更

- **security-audit 1.0.0 → 1.0.1** — 為 vendored validator 加上本地 drift 防護：新增 `valid-basic.json` fixture（confirmed + rejected 兩種 finding）與單欄位 mutation，接進 `scripts/validate-fixtures.cjs`，使 repo 根 suite + CI + PostToolUse hook 現在都守護 `validate-findings.cjs`（含其兩條語意約束：trace 首步須 `entrypoint`、末步須 `sink`）。記錄 re-vendor drift 檢查：pin 的 `4de1ac8` 對 upstream HEAD `f75f9a0` 為純目錄搬移、內容零漂移。未修改任何 vendored 檔。
- **openspec-superpowers-workflow 1.2.1 → 1.2.2** — Phase 1 pre-check 路徑統一為 `${CLAUDE_PLUGIN_ROOT}`（原為 repo 相對路徑 + 「從安裝根解析」的 prose 說明），對齊其他 plugin skills/commands 的慣例。

### 備註
- 另（非 plugin）：在個人 `~/.claude/CLAUDE.md` 的 plugin 決策樹加入 `security-audit` 入口（主動獵漏 → `/security-audit`；diff/PR 治理 → `code-audit-rigor`），並將 `docs/loop-design-review-2026-07-01.md` 兩個懸空的 Tier-3 judgment call 以明確 won't-do 處置 + re-open 觸發條件收尾。Marketplace patch bump 1.8.10 → 1.8.11。

## [1.8.10] - 2026-07-01

### 變更

- **high-precision-dev 1.4.0 → 1.5.0** — 跨家族 model 指派，打破共用 base-model 的相關性地板：`implementer-a`/`adversary`/`verifier` 用 `opus`，`implementer-b`/`critic`/`disproof-agent` 用 `sonnet`，讓 builder 與 checker 橫跨兩個 model 家族。`model` frontmatter 是家族層級（配 Opus 4.8 × Sonnet 5；選不到特定舊版、同家族配對幾乎不去相關）；per-agent effort 不可 frontmatter 設定，跟隨 session `/effort`。

### 備註
- Marketplace patch bump 1.8.9 → 1.8.10。

## [1.8.9] - 2026-07-01

### 變更

- **high-precision-dev 1.3.0 → 1.4.0** — `p→p⁴` 誠實化 reframe + implementer 去相關。乘法式 `p⁴` 宣稱在所有出現處（`plugin.json` / `marketplace.json` / `README` / `start.md` / `ANTI-PATTERNS.md`）從頭條保證降級為「理想化模型 + 明確的共用 model 相關性地板 caveat」（同一 base model 的兩個 identical-prompt 實例，對系統性誤讀會同向出錯）。`implementer-a` 與 `implementer-b` 原本逐字元相同，現改為真正不同路徑（A 規格優先/由上而下、B 測試優先/行為驅動；同完整度、不同路徑），讓最弱的獨立性那條腿真正去相關。

### 備註
- Marketplace patch bump 1.8.8 → 1.8.9。

## [1.8.8] - 2026-07-01

### 新增

- **high-precision-dev 1.2.1 → 1.3.0** — Phase 4 完成前的 controller 親跑環境測試閘門。verifier 合併後，controller 自己跑 SPEC 測試套件並捕捉 exit code（`WF_TEST_EXIT=$?`），把「測試通過」從 agent prose 宣稱升級為環境事實，接進既有 capped fix-loop 的退出條件。刻意不重新引入結構化輸出合約——它是唯一通過元規則的機器閘門：*閘門有資格存在 iff (a) 讀環境事實而非 agent 斷言，且 (b) 有下游消費者據其結果行動。*

### 備註
- Marketplace patch bump 1.8.7 → 1.8.8。

## [1.8.7] - 2026-07-01

### 變更

- **code-audit-rigor 1.4.0 → 1.5.0** — `/review-branch` 新增 `--focus <pathspec>` 與 Phase 2 confidence 欄位（0-100，<67% 標記 borderline）；`/review-pr` Phase 3 回歸檢查硬化為 `/audit-review-fix` 已審過的 baseline + exit-code sentinel 紀律（捕捉修前 baseline、只數 new-vs-preexisting failure、信任 `WF_TEST_EXIT=0`、build 新壞算回歸、無法解析則 fail closed）。
- **openspec-superpowers-workflow 1.2.0 → 1.2.1** — Phase 1 新增選用的寬鬆本地 pre-check，在權威的 `openspec validate --strict` 前先跑自帶 `.cjs`（讓 plugin 自己原本只在 CI 的 validator 出現在 live workflow）。
- **high-precision-dev 1.2.0 → 1.2.1** — 移除 `start.md` 從未實作的 `--phase N` arg hint；查清 `disproof-agent` 未註冊非缺陷（frontmatter 與會註冊的 sibling 相同，是 under-versioned PR #4 的 reload 殘留，1.2.0 bump + reload 即解）。

### 備註
- loop-design review 的 follow-on 項目。Marketplace patch bump 1.8.6 → 1.8.7。

## [1.8.6] - 2026-07-01

### 變更

- **選擇性 L2 收斂**（源自 `docs/loop-design-review-2026-07-01.md`）——把 PR #4「四個 plugin 一律加 schema + validator」縮減到只保留「真的有機器消費者讀取合約」之處，而非全盤 revert（全 revert 會連帶砍掉 code-audit-rigor 真正在運作的 live validator、CI、hook 與 STEEL_MANNING）。
  - **multi-agent-debate 1.1.0 → 1.2.0** — 完成 L2：`/debate` Phase 6 現在 emit `debate-output.json` 並跑 `validate-debate-output.cjs` 當 live 結構閘門；新增跨欄位參照完整性（`selectedProposal`/`agreedProposals` 必須指向真實 `proposals[].id`）與必填、機器可檢的 `coverage` 欄位；對齊 Phase 4 收斂判準（分數差 ≥8）與 `orchestrator.md`。
  - **high-precision-dev 1.1.0 → 1.2.0** — 移除死碼 L2：六個 agent 全產 prose 報告，schema 驗的是沒 agent 會產出的 JSON 形狀。刪除 `schema/`、validators、fixtures + runner wiring；清 `README`/`start.md` 的 dangling ref。
- 移除誤留的 `t.json`（PR #4 誤入 repo 根目錄的 prior-debate 測試殘檔）。

### 備註
- 套件 148 → 133 checks（−21 移除的 high-precision checks、+6 新增 debate mutation）。Marketplace patch bump 1.8.5 → 1.8.6。

## [1.8.5] - 2026-07-01

### 修正

- **回補 PR #4 的版本 bump + changelog**（commit `893821c`）——該 PR 在四個 plugin 一律加上「結構化輸出 + zero-dependency validator + fixtures + CI + PostToolUse hook」的 L2 層，卻**沒有任何版本 bump**，使每個 `plugin.json` 在功能變更前後都停在同一個 pre-merge 版號，且兩個 plugin 根本沒有 `CHANGELOG.md`。這種歧義正是 registry 版本快取失效（新 agent/能力靜默不載入）的病灶。
  - **code-audit-rigor 1.3.4 → 1.4.0**、**openspec-superpowers-workflow 1.1.0 → 1.2.0** — 為 L2 變更回補版本 + changelog。
  - **multi-agent-debate 1.0.0 → 1.1.0**、**high-precision-dev 1.0.0 → 1.1.0** — 建立 `CHANGELOG.md`（回補 1.0.0 initial-release + 1.1.0 L2 變更）。

### 備註
- 本次無功能性程式碼變更——僅版本/changelog 衛生。Marketplace 1.8.4 → 1.8.5。

## [1.8.4] - 2026-06-29

### 修正

- **code-audit-rigor 1.3.3 → 1.3.4** — `/audit-review-fix` Verify-Fix 不再把「baseline 與 verify 兩端都壞掉」的 build 回報為 `testsPass`/`READY_FOR_COMMIT`（run-2 review 的「2b」殘留）。新增正交的 `currentlyBroken` 判斷（`errored` + 明確非零 exit），不論 baseline 如何一律 fail-closed——commit 一棵無法 build 的樹永遠不該被放行。要求明確非零 exit，故「通過但輸出含 error 字樣」不會被誤殺；純 assertion 失敗的 dirty baseline 不受影響。單元 harness 現 76 條斷言。

### 備註
- Marketplace patch bump 1.8.3 → 1.8.4。

## [1.8.3] - 2026-06-29

### 修正

- **code-audit-rigor 1.3.2 → 1.3.3** — run-2 自我稽核中 `/audit-review-fix` workflow 剩餘的 LOW/NOTE 健壯性項目（單元 harness 現 71 條斷言）：
  - `status` 不再把單獨的 `DEFER_OUT_OF_SCOPE` finding 誤報為 `CLEAN`——新增 `REQUIRES_FOLLOW_UP` status（文件已更新）。
  - fix agent 改了檔卻回 `applied=false` 時，浮出留在 tree 的未測檔案（不再被靜默標為「declined」）。
  - 組報告路徑前消毒 `today`（不可 `../` 穿越）。
  - Scope-abort 強化：「no changes」判斷加上 real-diff 守衛；bad `--focus` pathspec 現會明確中止，而非靜默審查空 diff。
  - Fix-agent prompt 強化抗 indirect prompt injection（把 diff/finding 文字當資料）。
  - EV 67% 損益平衡點經審查後刻意保留不變（忠實實作 skill 文件化的 Framework 2）。

### 備註
- Marketplace patch bump 1.8.2 → 1.8.3。

## [1.8.2] - 2026-06-29

### 修正

- **code-audit-rigor 1.3.1 → 1.3.2** — `/audit-review-fix` workflow 三個安全閘修復（fail-open → fail-closed），由自我 `security-audit` 稽核（run-2）發現並經對抗式 review，以 56 條斷言的單元測試 harness 覆蓋：
  - （HIGH）Verify-Fix 對「build 壞掉」的 compile/collection/fatal 狀態（無 `failed`/`FAIL ` token）誤報 `testsPass=true` → 無法編譯的程式樹被回報 `READY_FOR_COMMIT`。現偵測 error/no-run 狀態 + exit-code 哨符，並 fail-closed。
  - （MEDIUM）clean baseline 使 count 回歸後備失效（`baselineFailCount=null`）；現歸零為 `0`。
  - （MEDIUM）非數值／非物件 args 被 coerce 成 NaN 或讓 flag 退回 → 靜默丟棄 finding／不跑 review／移除 LOC 上限／假 `CLEAN`；現以 finiteness／object-shape 守衛驗證。

### 備註
- Marketplace patch bump 1.8.1 → 1.8.2（一個 plugin patch release）。

## [1.8.1] - 2026-06-29

### 安全性

- **codegraph 1.0.0 → 1.0.1** — 修正前置 npm 套件名：從無人擁有的 unscoped `codegraph`（第三方的 469-byte 空殼、無 `bin`）改為真正的 scoped `@colbymchenry/codegraph`。消除 dependency-confusion 風險與功能性損壞（照舊文件安裝的人，bundled MCP server 從未啟動）。由 `security-audit` 稽核發現，並以維護者實際安裝環境實證確認。
- **code-audit-rigor 1.3.0 → 1.3.1** — `/review-pr` 現在將抓取的 PR 評論（公開 PR 上任何人皆可張貼）標示為不可信資料，僅供分析、不可當指令執行，且 Phase 4 推送前要求檢視實際 diff。Defense-in-depth（`security-audit` Finding 2，LOW）。

### 修正

- 對齊 `repository`/`homepage`：`multi-agent-debate`（原指向不存在的 `chinlung/multi-agent-debate`）與 `session-learning`（原缺漏）皆改為 `chinlung/claude-dev-workflow`。純 metadata，未變動 plugin 版本。
- 新增根目錄 `.gitignore`（`node_modules/`、`.env*`、`*.pem`/`*.key`、`*.local.md`、`*.log`、OS 垃圾檔），避免貢獻者／fork 者誤提交本地設定或機密。

### 備註
- Marketplace patch bump 1.8.0 → 1.8.1（兩個 plugin patch release + repo 衛生）。

## [1.8.0] - 2026-06-29

### 新增
- **新 plugin：security-audit 1.0.0**。Vendored `security-audit` skill，源自 [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill)（MIT，© Cloudflare, Inc.），upstream commit `4de1ac8`。六階段多代理流程（recon → hunt → validate → report → structured output → independent verification），主動獵捕可被利用、有實際影響的漏洞，與 `code-audit-rigor` 的審查紀律框架互補。Vendored 檔案逐字複製；wrapper 僅加 `plugin.json` + `README.md`，記錄 Claude Code 平台對應（research → `Explore`、general → `general-purpose`）與上游同步程序（見 CONTRIBUTING §7）。

### 備註
- Marketplace minor bump 1.7.5 → 1.8.0（新增 plugin）。

## [1.7.5] - 2026-06-24

### 新增
- **code-audit-rigor 1.2.1 → 1.3.0**：新增 `/audit-review-fix`——自動化對抗式批次審查自動修 Workflow，作為 plugin 第三層併入（從使用者層 `~/.claude/` 遷入，與 1.2.0 command 遷移同一可攜性模式）。command 透過 `${CLAUDE_PLUGIN_ROOT}/workflow/audit-review-fix-workflow.js` 讀取腳本（無硬編碼 home 路徑）：9-angle review + EV triage + 安全閘門自動修 + 測試驗證 + 報告。「排除 auto-fix」的定位現在僅限量化框架 skill 本身——auto-fix 由獨立的 `/audit-review-fix` 在安全閘門 + 對抗式驗證下提供。

### 備註
- Marketplace patch bump 1.7.4 → 1.7.5。

## [1.7.4] - 2026-06-17

### 變更
- **openspec-superpowers-workflow 1.0.1 → 1.1.0**：Phase 4 對齊 superpowers v6.0.0。superpowers 6.0.0 重寫了 subagent-driven-development 的 per-task review：雙階段 review（spec / quality 兩個 reviewer）→ 單一 `task-reviewer` 一次回兩個 verdict + 結尾一次 whole-branch review（用最強 model）。新增 worktree 落點說明：v6 移除全域 `~/.config/superpowers/worktrees/`，改落專案內 `.worktrees/` root（需 git-ignore）。新增 reviewer-integrity 紀律（禁止壓制 finding、禁止預設 severity），並標註相依 superpowers >= 6.0.0。

### 備註
- Marketplace patch bump 1.7.3 → 1.7.4。

## [1.7.3] - 2026-06-08

### 變更
- **code-audit-rigor 1.2.0 → 1.2.1**：調用鏈追蹤改為 codegraph-aware。Review 子代理只看派發 prompt，而 prompt 原本硬寫「使用 Grep」——即使專案有 codegraph 索引也不會用，漏掉 dynamic-dispatch 呼叫點（callback、DI、event handler）。`/review-branch` Phase 2 與 `SKILL.md` Principle 3 現在在 `.codegraph/` 存在時優先用 `codegraph_callers`/`codegraph_impact`，無索引 fallback Grep。quotedCode 錨定刻意維持 Grep（逐字文字比對，非結構查詢）。無硬依賴——沒裝 codegraph 行為不變。

### 備註
- Marketplace patch bump 1.7.2 → 1.7.3。

## [1.7.2] - 2026-06-08

### 變更
- **code-audit-rigor 1.1.0 → 1.2.0**：把 `/review-branch` 與 `/review-pr` 從使用者層 `~/.claude/commands/` 遷入 plugin。動機：`/review-branch` 的內建規則層原本 fallback 到只在單一機器有效的硬編碼絕對路徑；進 plugin 後改用 `${CLAUDE_PLUGIN_ROOT}/rules/manifest.json`——機器無關、隨安裝出貨。Plugin 定位擴為「審查工具箱」（routine 指令 + rigor skill 共用同一套規則包）。

### 備註
- Marketplace patch bump 1.7.1 → 1.7.2。

## [1.7.1] - 2026-06-07

### 變更
- **code-audit-rigor 1.0.1 → 1.1.0**：新增三項決定性工程化保證，改編自 [alibaba/open-code-review](https://github.com/alibaba/open-code-review) 的「決定性工程 + LLM」混合設計（Apache-2.0）。差距分析：本 skill 強在深度嚴謹（EV 數學、steel-manning、STRIDE+CWE），但覆蓋率、規則特化、引用準確性原本依賴 LLM 自律——正是 OCR 用工程邏輯解決的三件事。
  - **Phase 1b 路徑匹配規則包**：新增 `rules/manifest.json`（glob → doc、first-match）+ 8 份 `rule_docs/*.md`（TS/JS/React、PHP/Laravel、Python、Go、SQL/mapper、YAML/IaC/Dockerfile、package.json、default），每份含 Review-focus 獵取清單 + 檔案類型限定的「不要報」suppression list。分層覆寫：專案 `.reviewrules/` → 使用者 `~/.claude/review-rules/` → plugin 內建。
  - **機械化 scope + coverage 核銷**：Phase 1 scope 必須來自 `git diff --name-only` / `git show` / Glob 輸出；Phase 5 將每個 scope 檔案核銷進 Read 或 Skipped，新增強制 `Unaccounted` 欄——非空即審查無效。
  - **引用程式碼 grep 錨定**：Framework 4 crossReferences 新增必填逐字 `quotedCode` 欄位；Phase 4 Step 1 在 steel-manning 前先機械 grep（宣稱行號 ±10 內找到 → 錨定；別處找到 → re-locate；整檔不存在 → 標 `UNVERIFIED_REFERENCE`、confidence −30）。
  - 文件化刻意排除：不採三區記憶體壓縮（harness 原生 compact）；suppression list 為檔案類型限定，非本 skill 拒絕的全域 hard-exclusion 清單。

### 備註
- Marketplace patch bump 1.7.0 → 1.7.1，反映既有 plugin 內容變更。

## [1.7.0] - 2026-05-30

### 新增
- **CodeGraph Plugin**（1.0.0）：單一 skill plugin，教 Claude 在有 `.codegraph/` 索引的專案裡，結構性查詢「先 codegraph 再 grep」。
  - **夾帶 MCP server**（`.mcp.json` → `codegraph serve --mcp`）：裝一次，MCP 工具在所有專案都可用——新專案只需 `codegraph init -i`，不必逐專案 `codegraph install` 或寫 `.mcp.json`。plugin 提供的工具前綴為 `mcp__plugin_codegraph_codegraph__<tool>`；需 `codegraph` CLI 在全域 PATH。
  - **兩條入口邊界**：記錄一個不直觀的事實——`codegraph serve --mcp` 只把 `trace`/`node`/`explore`/`search`/`context` 導出成 `codegraph_*` MCP 工具，而 `impact`/`callers`/`callees`/`affected`/`status`/`files` 只在 Bash CLI（實測 codegraph 0.9.7）。誰都不是超集——把 `codegraph_impact` 當 MCP 工具呼叫會失敗。
  - **動作觸發**：綁定到動作（edit/rename/remove → `impact`；改 method → `callers`/`node`；接手不熟程式碼 → `context`；追流程 → `trace`），而非只在被問問句時才用。
  - **可靠性 fallback**：某能力不是 MCP 工具時改用 CLI，絕不默默退回會漏掉動態 dispatch 呼叫點的半套 grep。
  - 漸進揭露的 `reference.md`：新專案 4 步啟用、唯讀 `settings.json` allowlist、已知坑（工具管理的 `CODEGRAPH_START/END` 區塊重新同步會覆寫、該區塊表格把 CLI 命令誤列為 MCP 工具、`daemon.pid` 不在預設 gitignore）。

### 備註
- Marketplace minor bump 1.6.1 → 1.7.0，反映新增 plugin。

## [1.6.1] - 2026-05-09

### 變更
- **code-audit-rigor 1.0.0 → 1.0.1**：`SKILL.md` 新增 Phase 5b「零確認 finding」處理指引。在 `bin/tg-fallback-send.sh` 首次實戰測試（8 個 candidate → 0 confirmed）時暴露此空缺——原 workflow 沒有明確指示「乾淨 audit 該怎麼產出 report」。新 Phase 5b 強制：(1) 即便 0 confirmed 仍須產出完整 report；(2) executive summary 必須明確說明 negative result 是 valuable 而非 absence of work；(3) dismissed findings 區塊必須含「原始 vs 重新評估 confidence」+「steel-manning 論述」+「未來條件下何時 re-escalate」的 future note；(4) 「Total dismissed prior score」健全性檢查（如果每個 dismissal 都錯了，整體成本會是多少）；(5) 鼓勵附 skill 自評段落，回饋 friction points。Phase 5 明確要求 audit report 必須存檔到磁碟（不可只在 chat 顯示）。新增一條 anti-pattern。

### 備註
- Marketplace patch bump 1.6.0 → 1.6.1 反映 `SKILL.md` 內容變更。1.6.0 的使用者仍有四個量化框架，但缺最常見結果（0 confirmed findings）的處理指引——建議更新。

## [1.6.0] - 2026-05-09

### 新增
- **Code Audit Rigor 插件**：單一 skill 插件，為「直覺不足以判斷」的高風險程式碼審查提供量化紀律（安全、密碼學、金流、IaC、不可信輸入解析器）。
  - **五項核心審查紀律原則**：(1) 先讀完再評分；(2)「我真的讀了嗎，還是用猜的？」自我提問；(3) 驗證原始碼而非依賴 diff；(4) 多 agent 共識 ≠ 驗證；(5) 漏抓真 bug 比誤判昂貴 2 倍
  - **四個量化框架**：
    1. 評分校準（+10 / +5 / +3 / +1 vs −3 false-positive 懲罰）
    2. 期望值（EV）決策閾值：`EV = confidence% × points − (100 − confidence%) × 2 × points`，≥67% confidence 才動手
    3. STRIDE + CWE 分類，內附 16 個常用 CWE 速查表
    4. 強制 crossReferences 契約（每個 finding 必含 `file:line` 證據，空陣列直接拒絕）
  - **端到端審查流程**：5 個 phase（scope / 完整閱讀 / findings 草稿 / 對抗式掃描 / 彙整報告），其中 Phase 4 對抗式掃描刻意 steel-man 反方位置，防止多 agent 共識變成 false-confidence 放大器
  - **自包含設計**：所有規則與 reference 表都在 `SKILL.md` 內，在任何電腦 install 都完整運作，不依賴 host 專案的 CLAUDE.md
  - **靈感來源** 是 `codexstar69/bug-hunter` 的對抗式 Hunter / Skeptic / Referee 流程，但**刻意排除** auto-fix with canary rollout（對 production code 太激進）、hard-exclusion lists for "settled false-positive classes"（會造成盲點）、以及 `SKILL.md` 之外的 LLM-readable 指令檔（最小化 prompt-injection 攻擊面）
- 更新 marketplace 版本至 1.6.0

## [1.5.1] - 2026-04-10

### 變更
- **openspec-superpowers-workflow 1.0.0 → 1.0.1**：強化自動觸發機制。重寫 `SKILL.md` frontmatter `description`，改用 imperative「MUST use」語氣、擴充 trigger 清單（現在也比對 `openspec` CLI 指令與 `openspec/changes/<name>/` 資料夾的存在），並明列四條禁止行為。在 `SKILL.md` 本體頂部新增「Activation reminder」段落，在 Claude 採取任何行動前錨定不可妥協的規則。這樣使用者就不需要在自己的 `~/.claude/CLAUDE.md` 維護獨立的「必須呼叫此 skill」提醒 — 同樣的 meta 指令現在隨 plugin 一併發佈。`phases.md` 不變。

### 修正
- **dev-workflow 1.0.1 → 1.0.2**：修正 `plugin.json` description 從「6 specialized agents」改為「7 specialized agents: ..., quality assurance, and documentation」。這個不一致是 2026-03-12 `35c0a9c` refactor commit 的遺漏 — 當時把版本號 revert 成對應 `CHANGELOG [1.0.1]`，卻也把 description 一併降回 1.0.0 時代的寫法，儘管 `documentation-specialist` agent 檔案從未被移除。僅 metadata 修正，無程式碼變更。

### 文件
- `README.md` / `README.zh-TW.md`：新增 `Session 經驗學習插件` 表格列、安裝指令、完整章節（自 1.4.0 起就應該要有但先前遺漏）
- `CHANGELOG.zh-TW.md`：翻譯英文版的 `[1.5.0]` 和 `[1.4.0]` entry（中文 changelog 先前停在 `[1.3.0]`）
- `marketplace.json`：將 `dev-workflow` entry 的版本從 `1.0.0` → `1.0.1` → `1.0.2` 對齊到 `plugins/dev-workflow/plugin.json`（先前版本對齊 refactor 的漂移修正）

### 備註
- Marketplace 版本從 1.5.0 → 1.5.1 反映 `HEAD` 相對於初始 1.5.0 commit 多了數個 plugin 內容變更。停留在 1.5.0 的使用者若不更新，會錯過較強的自動觸發機制和 dev-workflow description 修正。

## [1.5.0] - 2026-04-10

### 新增
- **OpenSpec + Superpowers 工作流程插件**：六階段功能開發工作流程，強制執行 OpenSpec（規格生命週期，WHAT）與 Superpowers（開發紀律，HOW）嚴格角色分離
  - 單一 skill，採用 progressive disclosure：`SKILL.md`（58 行，常駐載入）+ `phases.md`（290+ 行，需要時才載入）
  - **Phase 1 — 規格定義**（OpenSpec 主導）：proposal + specs 為使用者審核產物；design / tasks 為草稿佔位
  - **Phase 2 — 設計精煉**（Superpowers `brainstorming` → 原位覆寫 `design.md`）
  - **Phase 3 — 任務規劃**（Superpowers `writing-plans` → 原位覆寫 `tasks.md`）
  - **Phase 4 — 實作**（Superpowers `subagent-driven-development` + 強制 TDD）
  - **Phase 5 — 審查與回饋**：`[REQUIREMENT|DESIGN|CODE|CONSTITUTION]` tag 分類 + Y/N 標記，記錄到 `review-notes.md`；審查期間絕不修改 spec 檔
  - **Phase 6 — 調和與歸檔**（OpenSpec）：Clean rewrite 紀律（非增量 patch）、`tasks.md` 凍結為執行歷史、`[CONSTITUTION]` 項目改寫入 `openspec/config.yaml` 而非 feature spec
  - 前置需求段落記錄 OpenSpec CLI vs `/opsx:*` slash command 的替代選項，以及 `openspec init .`（無 `--here` flag）的 gotcha
  - Validator 嚴格性 gotcha：每個 `### Requirement:` 區塊必須在第一段出現 `SHALL` / `MUST`
  - Archive 資料夾日期前綴行為：`openspec/changes/archive/<YYYY-MM-DD>-<name>/`
  - 決策速查表（13 種情境）和 8 條反模式清單
- 更新 marketplace 版本至 1.5.0

## [1.4.0] - 2026-03-12

### 新增
- **Session 經驗學習插件**：漸進式保存對話中的有價值模式為 memory 或 skill
  - `/save-session` 命令：分析對話並保存有價值的模式為 memory 或 skill
    - 5 Phase 分析流程：掃描 → 層級判斷 → 去重合併 → 執行 → 報告
    - 自動區分全域 vs 專案層級保存位置
    - 更新優先於新建，避免記憶膨脹
    - 每次最多 1-2 項變更，精簡克制
  - Stop hook：在實質工作階段結束時輕量提醒執行 `/save-session`
    - Command 類型（非 prompt），不觸發額外 LLM 呼叫
    - Flag file 機制防止同一 session 重複提醒
    - 自動跳過短工作階段（< 10 行 transcript）
- 更新 marketplace 版本至 1.4.0

## [1.3.0] - 2026-03-06

### 新增
- **高精確度開發插件**：針對安全關鍵程式碼的多 Agent 開發模式
  - `/high-precision-dev:init` 指令用於建立 SPEC.md 和 CONSENSUS.md 模板
  - `/high-precision-dev:start` 指令用於執行 4 Phase 驗證工作流程
  - 5 個專門代理人：
    - 實作者 A/B：在隔離 worktree 中獨立進行防禦性實作
    - 批評者：使用 severity 1-5 分級系統性找出問題
    - 攻擊者：三輪紅隊攻擊（邊界、語意、假設）
    - 驗證者：最終整合，100% SPEC.md 需求覆蓋驗證
  - 透過認識論分工將錯誤率從 p 壓縮至 p^4
  - Phase 3 修復循環上限（最多 3 次），含 adversary 重新攻擊
  - 驗證者步驟零：整合前檢查 CRITIQUE.md/ATTACKS.md
  - 三級強度光譜文件（單一 Agent → /debate → /start）
- 更新 marketplace 版本至 1.1.0
- 更新 README 加入高精確度開發插件文件（中英文）

## [1.2.0] - 2025-12-19

### 新增
- **多代理辯證系統插件**：用於多角度決策的辯證系統
  - `/debate` 指令用於啟動辯論
  - 5 個專門代理人：
    - 協調者 (Orchestrator)：分析需求並配置角度
    - 角度 A/B/C (Perspective A/B/C)：從不同角度提出解決方案
    - 批判者 (Critic)：審查方案並提供量化評分
  - 根據需求類型智能配置角度
  - 量化評分系統（30分制）
  - 共識驅動決策（需≥2個代理人同意）
  - 透過多輪辯論迭代優化
  - 在關鍵決策點納入使用者參與
- 更新 README 以記錄插件集合中的兩個插件
- 新增多代理辯證系統的繁體中文文件

## [1.1.0] - 2025-12-11

### 新增
- **文件專家**代理人（步驟 7）：負責文件更新、CHANGELOG 維護和 PR 描述生成
- **handoff.md 機制**：中央狀態管理文件，用於代理人之間的無縫上下文傳遞
- 語言無關設計：適用於任何程式語言
- 繁體中文文件（README.zh-TW.md、CHANGELOG.zh-TW.md）

### 變更
- 泛化所有代理人，使其與語言/框架無關
- 改進實作專家的程式碼模式識別能力
- 強化品質保證的檢查項目
- 更新解決方案架構師的技術考量範圍
- 優化測試工程師對多語言測試框架的支援

### 修復
- package.json 中 repository 欄位格式（應為字串而非物件）
- 修正 GitHub 儲存庫 URL

### 文件
- 新增 Pahud Hsieh 的教學影片連結
- 新增貢獻者名單
- 重新編號開發流程文件以維持序列一致性

## [1.0.0] - 2024-12-11

### 新增
- dev-workflow 插件首次發布
- 6 個專門代理人：
  - 議題分析師：需求分析與使用者故事
  - 程式碼考古學家：程式碼庫探索與模式識別
  - 解決方案架構師：架構設計與方案比較
  - 實作專家：依循最佳實踐的程式碼實作
  - 測試工程師：測試規劃與執行
  - 品質保證：程式碼品質驗證與建置驗證
- 主要指令 `/dev-workflow` 支援：
  - 完整工作流程執行
  - 單一步驟執行（`--step`）
  - 從檢查點繼續（`--resume`）
- 使用 TodoWrite 進行進度追蹤
- 架構設計後的暫停點，等待使用者確認
- 完整的文件輸出至 `docs/task-{timestamp}/` 目錄

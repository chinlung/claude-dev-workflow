# pstack 三個驗證類 skill 是否納入開發流程（2026-11-11）

> 對象：`cursor/plugins` 的 `harness/pstack/claude-code/skills/` 底下 `blast-radius`、`create-verification-skill`、`create-formal-verification-skill`，連同它們的另一半 `maintain-verification-skill`、`maintain-formal-verification-skill`，以及 `docs/harness/claude-code.md`（adapter）。
> 版本：上游 HEAD `5866df5`（2026-11-11）。這五個檔最後一次變更是 10-27（`34b1b7c`），早於前次分析所用的 `6b03002`，**兩次讀到的是同一份原文**。
> 與前次的關係：`docs/pstack-porting-candidates-2026-11-09.md`（下稱「前次」）已把三者分別判為 P1 2.1（證據階梯）、P2 3.6、不移植；roadmap 排為 W5-1、W5-5。本文件只寫**前次沒查到、而會改變判定的事實**，不重複前次內容。
> 更新（同日，PR #55 合併後，main `38f95d7`）：§3 的行號、commit 數與 tokenizer 份數改為合併後的事實；初版寫「同一支 tokenizer」時兩份其實已分岔，PR #55 才發現並修正；§3 的回歸集由 2 個舊 bug 擴充為 4 個；CI 落點更正（本 repo 沒有 `run-all.sh`）。

## 0. 結論

| skill | 前次判定 | 本次判定 | 改變的原因 |
|---|---|---|---|
| `blast-radius` | 只取證據階梯（W5-1） | **借概念，範圍擴大**：證據階梯＋「安全支點事實」＋「grep 停下的地方」清單 | 前次只取了階梯；另外兩塊正好補我方「零 finding 時沒有任何正面論證」與「codegraph 只看符號邊」兩個缺口 |
| `create-verification-skill`（＋maintain） | 移植產生器（W5-5，成本 M） | **改用內建 `/run-skill-generator`，只借 pstack 的差額** | Claude Code 2.1.322 已內建同功能的產生器，以及讀取它產出的 `run`；再移植一個產生器會造成兩種形狀互搶 |
| `create-formal-verification-skill`（＋maintain） | 不移植（「少有並行狀態機」） | **不裝 skill，但採用它的方法做一次試點**：對 gate 的 shell tokenizer 做 differential 測試 | 前次漏看：本 repo 有三份手寫的 shell 命令解析（兩支 gate 內同源的 Perl tokenizer，加上 scope-ledger 的 awk 剝除），修過多輪，且 #51 證實曾有 production 繞過 |

三者都**不建議整包安裝 pstack plugin**，理由同前次 §5：會多一個 lifecycle owner（poteto-mode），而且 skill 之間互相引用 `why`、`arena`、`unslop`、`statechart` 等 pstack 內部 skill。

## 1. blast-radius

### 它做什麼

- 開宗明義：「Listing the callers is not the job. … The job is the breakage grep won't show you.」（`blast-radius/SKILL.md:13`）
- 不信自己的分析報告，把變更「之所以安全」所依賴的事實分五階證明：說的、指到 `file:line`、走過失敗路徑、跑了會大聲失敗的腳本、在 app 重現（`:21-29`）。
- 第 2 步「Find the one fact it's safe because of」：多數看似危險的變更，安全性取決於單一事實，時間應該花在這裡，而不是列一長串可能性（`:34`）。
- 第 3 步「Look where grep stops」：library 原始碼與 pinned 版本、執行時機（microtask、teardown）、API 回的 JSON、DB 欄位、wire format、其他語言讀同一份 bytes、feature flag、三跳之外的下游（`:35`）。
- 只能由使用者叫用（`disable-model-invocation: true`，`:4`）。依賴 `why`、`arena`、`unslop`（`:33,38,48`），在 Claude Code 裡會變成懸空引用。

### 對照我方

| 它的部分 | 我方現況 | 缺口 |
|---|---|---|
| 列出呼叫者／遞移影響 | codegraph `impact`，自稱提供「structural facts」（`plugins/codegraph/skills/codegraph/SKILL.md:10,37`） | 無，已覆蓋 |
| 證明 finding 是真的 | `finding-verifier` 回 `confidence: <0-100>`（`plugins/code-audit-rigor/agents/finding-verifier.md:51`），不跑程式 | 階梯，已排 W5-1 |
| **證明變更是安全的** | 沒有。review 的產出只有 finding；零 finding 時沒有任何正面論證 | **缺**。CLAUDE.md 自己寫了「無 finding、沒觸發、審查出錯三者同樣沉默」 |
| **grep 停下的地方** | 零散寫在 CLAUDE.md 的教訓裡：ORM 動態關聯與字串類名（曾漏 25 個活呼叫點）、「檔案生死看 runtime 讀取路徑」。review-branch 與 code-audit-rigor 都沒有對應清單（全文搜 wire format／serializ／feature flag／DB column 零命中） | **缺**。有教訓，但沒有收成 reviewer 會讀到的清單 |

### 建議

併進 W5-1，同一次 schema 變更：

1. **證據階梯**：照 W5-1 原案。
2. **安全支點欄位**：`/review-branch` 的結果檔加一個 `safety_pivot`，內容是「這個 diff 安全，是因為 X」加上 X 到第幾階。零 finding 的輪次也必須填，填不出來就寫 `unproven`。這讓「沒找到問題」第一次有可被反駁的內容。
3. **「grep 停下的地方」清單**：放 `plugins/code-audit-rigor/tools/`（與 `sweep-patterns.md` 同層），用我方技術棧的實例改寫，例如：Eloquent 動態關聯與 `->關聯名`、Blade、字串類名與 `config()`、queue job 的序列化 payload、migration 的欄位與 API Resource 的 JSON 形狀（前端會讀）。codegraph skill 加一行指過去：「impact 不含以下耦合」。

**怎麼證明有效**：拿 `refs/review-escapes.md` 已記錄的逃逸案例回放。加清單前後各跑一次 `/review-branch`，看動態關聯那一類有沒有被點名。沒被點名，就代表清單沒進到 reviewer 的 prompt，這是接線問題，不是清單內容的問題。

## 2. create-verification-skill（＋maintain-verification-skill）

### 它做什麼

- 從 repo 本身（不問使用者）找出使用者介面、啟動方式、驅動方式、可蒐集的證據、能否隔離（`create-verification-skill/SKILL.md:13-21`）。
- 產出 `verify-<app>` skill，分 Launch、Doctor、Drive、Evidence、Cleanup、Helpers 六段（`:27-34`），另附 feature map，每個功能一檔、固定四個 H2（`:38`）。
- 交付前要把產出的 skill 端到端跑一次。cleanup 之後證據必須還在，用替身環境（stand-in）證明的，要列出替身做了而真實目標不會做的步驟（`:42`）。
- `maintain-*` 是定期稽核：每個功能派一個唯讀子代理讀原始碼，主迴圈逐一實際驅動每個功能，最後歸成 clean、changed、blocked 三種結局之一（`maintain-verification-skill/SKILL.md:15-19,31-35`）。

### 前次沒查到的事實：Claude Code 已內建同功能

以 Claude Code 2.1.322 binary 的字串查證：

- 內建 `run` 的 SKILL.md 第一段「First: does a project skill already cover this?」，用 `grep -Hm1 '^description:' "$d"/.claude/skills/*/SKILL.md` 從目前目錄往上找到 git 根，挑一個 description 描述「launching/driving this app」的 skill 照做。找到多個就問使用者，過期就建議 `/run-skill-generator`。
- `run-skill-generator` 已註冊：`disableModelInvocation: true`、`userInvocable: true`，description 是「Author or improve the run-<unit> skill - a per-project skill that tells agents how to build, launch, and drive this project's app」。因為禁止模型叫用，它不會出現在模型的 skill 清單裡，這就是前次沒發現它的原因。
- 它的 SKILL.md 本體在 binary 裡沒有明文可抽（大概是壓縮過），所以**無法逐段比對它的產出形狀**。

### 判定

不移植 pstack 的產生器。理由：`run` 是靠 description 挑 skill。若同一個專案裡有一份 `run-<unit>` 和一份 `verify-<app>` 都在描述「怎麼啟動這個 app」，`run` 會落入「several plausible → ask the user」那一支，每次都多問一次使用者。

W5-5 改成：

1. 在一個 Laravel 專案跑內建 `/run-skill-generator`，取得實際產出。
2. 拿產出對照 pstack 的六段與 feature map，只補缺的部分。從 `run` 的 fallback 文字看不到、而 pstack 有的，有這幾項：
   - **Doctor**：唯讀的「這個 instance 值得驅動嗎」檢查。
   - **Isolate**：無法並存時拒絕重複驅動。
   - **證據標準**：驗副作用（寫入的列、送出的訊息），而不只驗畫面；dry-run 跳過了什麼要觀察，不能只信它的名字。
   - **cleanup 保留證據並事後確認**。
   - **feature map**，以及「前置條件不足時回報失敗，不准把 journey 改弱」。
3. 補的位置放在產出的 skill 本身，或寫成專案層 ref，不另開 skill。

**maintain-verification-skill**：這是內建版完全沒有的部分，內建只有被動的「stale 就重產」。但它要有東西可稽核才有價值，等專案的 run skill 有 3 個以上功能檔再評估。

**本 repo 不適用**：這裡的「app」是 hook 與 CLI 腳本，`tests/*.test.sh` 已經用 stdin JSON 直接驅動它們（例如 pr-merge-gate 有 146 個 check、36 個 mutant），等於已經有驗證 skill 的實質。價值在 Laravel 與前端專案。

**怎麼證明有效**：試點專案裡挑一個近期修過的 UI bug，`git checkout` 到修正前的 commit，照產出的 skill 驅動該功能，它必須重現 bug。重現不了，就代表 Drive 段驅動的不是真實的使用者路徑。

## 3. create-formal-verification-skill（＋maintain-formal-verification-skill）

### 它做什麼

- 從 repo 裡挑出「壞了傷害使用者、測試又很少碰到」的承諾，選最強的那個，而不是最好驗的那個（`create-formal-verification-skill/SKILL.md:17`）。
- 依問題選工具：事件順序選 model checker，預設 TLA+；對所有輸入都要成立的性質，選跑在程式碼上的 verifier。**該語言沒有 verifier 時，就用生成的輸入測真實程式碼，而不是手寫一份函式的模型**（`:21`）。
- 品質判準：每個性質都要先在一個故意弄壞的版本上看到它失敗（`:26`）；當前程式碼若違反性質，就當 finding 回報，不准把性質改弱（`:27`）；記錄涵蓋範圍與 sync commit，讓之後的 agent 看得出驗證已經過期（`:31`）。
- `maintain-*` 處理的危險情境是：程式碼改了、模型沒改，模型「仍然通過」，但它描述的已經是不存在的程式碼（`maintain-formal-verification-skill/SKILL.md:11`）。

### 前次判定為什麼要改

前次的理由是「少有並行狀態機」，而且要 TLA+、Java、網路。但這個 skill 的 description 點名的目標除了並行，還有 **parsers**；它的工具選擇也不只 TLA+。本 repo 就有符合的目標：

- `plugins/openspec-superpowers-workflow/hooks/archive-gate.sh:47` 起嵌了一支手寫的 Perl shell tokenizer：heredoc 跨行狀態、`$'…'`、`$(( ))` 與 `<<` 的區分、雙引號與 heredoc 本體內的 `$( … )`／反引號、keyword 與 wrapper 後面的命令位置、`bash -c` 遞迴展開。
- **同源的 tokenizer 也在 merge 閘門**：`plugins/pr-closeout/hooks/pr-merge-gate.sh:44`「Same tokenizer as openspec's archive-gate」。這句在初版寫成時並不成立：兩份已分岔，archive-gate 完全不掃引號內與 heredoc 本體的替換。PR #55 把它對齊，並以 `# >>> shared-tokenizer:` 標記界定共用區段（archive-gate `:49-67`、`:73-142`），由 `tests/shared-tokenizer.test.sh` 比對兩份必須一致。
- **第三份**：`plugins/scope-ledger/hooks/scope-gate-bash.sh:36` 用 awk 剝除 heredoc 本體與引號字串，與上面兩份不同源，#48、#51、#55 的修正都沒到它那裡（已列 follow-ups）。
- 修補史：skip-gate、archive-gate、pr-merge-gate 各 5 個 commit，在本 repo 的 hook 與腳本中名列前茅。
  - #48（`3d9baa9`）：「read any <<WORD as the start of a heredoc and dropped the lines after it, so an archive on the next line went through unchecked」。commit body 自己列了一張 Not covered 清單。
  - #51（`392d732`）：「an openspec archive or gh pr merge on a later line was never seen (**bash ran it**; the code before this series missed it the same way)」。
  - #55（`38f95d7`）：archive-gate 不掃 `echo "$(openspec archive foo)"` 與 heredoc 本體裡的 `$( … )`（bash 會執行、閘門放行）；兩支 gate 都逐行掃 heredoc 本體，切斷跨行的 `$( … )`，一個方向漏擋、另一個方向把單引號內的字面文字當成命令。後者 pr-merge-gate 自 1.0.0 即有，是 codex 跨 vendor review 抓到的。

每一輪都是撞上沒人想到的輸入才補 case，正是 skill 開頭那句「A test checks the cases that someone thought to write」的情形。而閘門的承諾正好可以寫成一句話：**bash 實際會執行的每一個 `openspec archive X`／`gh pr merge N`，tokenizer 都要抓到**。

### 套用 skill 自己的選擇樹

- 不用 TLA+：這裡沒有並行，問題出在「解析」，不在「事件順序」。
- 嵌在 bash 裡的 Perl 沒有程式碼層的 verifier，所以走 `:21` 的退路：**用生成的輸入測真實程式碼**。
- 現成的 oracle 就是 bash 本身：在空的暫存目錄、`env -i PATH=<stub 目錄>` 下用 `bash --noprofile --norc -c "$cmd"` 執行生成的命令。stub 目錄裡只有記錄 argv 的 `openspec` 與 `gh`，其他名稱都找不到，所以執行沒有副作用。
- 性質只取**完整性方向**：bash 執行到的集合 ⊆ tokenizer 抓到的集合。反方向不成立，因為像 `false && openspec archive x` 這種 bash 不會執行、但閘門照樣攔下的命令，是刻意的保守。
- 生成語法要排除閘門已明文不處理的情形（`archive-gate.sh:43-44`：從 stdin 餵給 shell 的腳本、alias、存在變數裡的命令）。#48 的 Not covered 清單則該**納入**生成語法，讓 backlog 機械化地分成「確認是 bug」與「確認沒事」兩類。
- **附帶的好處**：測的是真實程式碼，不是另寫一份模型，所以 `maintain-formal-verification-skill` 處理的「模型過期卻仍通過」那類問題根本不存在。不需要 sync commit，也不需要 maintain 流程。

### 判定與驗證計畫

不安裝 skill，做一次試點（成本 S–M，零新依賴，node 或 perl 加固定 seed）：

1. **先證明它抓得到舊 bug**（skill 的「Able to fail」，也是 pstack `correct` 的「Prove each new check fails on a real past mistake」）。回歸集是四個已修正的真實缺陷，harness 對每個修正前版本都必須找出反例：
   - `3d9baa9^` 的 archive-gate：#48 的 heredoc 誤判（here-string、引號內的 `<<` 之後的歸檔被吞掉）。
   - `392d732^` 的 archive-gate 與 pr-merge-gate：#51 的 `$'…'` 引號錯位。
   - `a86abf5` 的 archive-gate：#55 的雙引號與 heredoc 本體內替換完全不掃。
   - `a86abf5` 的 pr-merge-gate：#55 的 heredoc 本體逐行掃描（跨行 `$( … )` 漏擋與誤擋）。

   任何一個找不到，就是生成語法太窄，該修的是語法，不是放寬標準。四個之中後兩個都是人工審查各層先漏掉、最後才被抓到的，正好用來衡量 harness 是否比審查多抓到東西。
2. 再對 HEAD（`38f95d7`）的 archive-gate 與 pr-merge-gate 跑。找到的反例照「Findings stay findings」原則，以 bash 的語言重述成步驟後進 scope-ledger 帳本，不在試點裡順手修。兩份共用區段已經一致，所以同一個反例應同時出現在兩支 gate；只出現在一支，代表差異在共用區段之外（命令位置判斷或 `bash -c` 展開）。
3. 固定 seed 與次數後，寫成 `plugins/*/tests/*.test.sh` 的一支 suite：CI 的 `validate.yml` 與本機 `validate-on-plugin-edit` hook 都會自動列舉、執行它。

**已知限制**：hooks.json 的 `if` 前置過濾（`archive-gate.sh:2-3`）由 Claude Code 判定，harness 碰不到；閘門是 fail-open 設計（`:12-13`），所以這個性質只涵蓋 parser，不涵蓋整條攔截路徑。

## 4. 對 roadmap 的修訂建議

| 項目 | 原案 | 建議 |
|---|---|---|
| W5-1 | 證據階梯 | 加上「安全支點」欄位與「grep 停下的地方」清單，同一次 schema 變更 |
| W5-5 | 移植專案驗證 skill 產生器（M） | 改成「試用內建 `/run-skill-generator`，再對照 pstack 補差額」（S） |
| 新增 | — | tokenizer differential 試點：archive-gate＋pr-merge-gate，先用 #48、#51、#55（兩個）修正前的版本證明抓得到 |

## 5. 本文件沒有驗證的事

- `run-skill-generator` 的 SKILL.md 本體與產出形狀：binary 裡沒有明文。它會不會出現在使用者的 `/` 選單，也還沒實際看過。
- differential harness 沒有實作。「它能抓到 #48、#51、#55 的四個缺陷」是設計目標，要等第 3 節第 1 步跑過才算數。
- scope-gate-bash.sh 的 awk 剝除是否也有同類缺陷，沒有實測；它不在試點範圍內，只列為 follow-up。
- 「安全支點」欄位能否降低漏抓率，要靠 W0-1 量尺與逃逸案例回放；目前只是推論。

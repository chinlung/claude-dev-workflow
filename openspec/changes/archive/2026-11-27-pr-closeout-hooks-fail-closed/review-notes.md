# Review Notes — pr-closeout-hooks-fail-closed

<!-- Phase 5 log. One line per review comment, appended under a `## Round N - [Review Type] (YYYY-MM-DD)` heading:
     - [REQUIREMENT|DESIGN|CODE|CONSTITUTION] Y/N - description
     Y/N answers ONE question: "must an OpenSpec artifact be updated in Phase 6?" — it does NOT mean "handled / fixed".
       [CODE] is therefore always N, even when the fix is already committed.
       [CONSTITUTION] Y = a NEW cross-feature rule to add to the project constitution; do not log "existing rules were followed".
     Tag by the artifact the fix lands in (spec → REQUIREMENT, design.md → DESIGN, code only → CODE), not by the nature of the problem.
     Never edit proposal.md / specs/ / design.md / tasks.md during review — record here, reconcile in Phase 6.
     Add `final` to the last Round heading only after the user says review has converged — the archive gate checks it. -->

## Round 1 - Implementation deviations + review-branch (2026-11-27)
- [DESIGN] Y - D4 的金絲雀原訂「`set -u; echo "$a）"` 必須失敗」：ubuntu amd64 容器實測 GNU bash 3.2.57 在 glibc 下（C.UTF-8 與 C）不重現，是 macOS libc 特有的；金絲雀改測兩個在 Linux 重現的 3.2 語意（set -u 空陣列、雙引號 `${…}` 內的 `$'…'`），D1a 型只由兩份套件的 lint 擋。建置另需 bison（`YACC="bison -y"`）與 x86_64 runner（2002 年的 config.guess 不認 aarch64）
- [CODE] N - CI 快取 key 不含建置方式，改建置步驟時命中舊 binary：key 加 `r1` 標記並註明改建置時遞增（review-branch r1，已修）
- [CODE] N - guard 突變 `no-continue` 的替換模式跟著 D1b 的寫法更新（Task 3 時發現套不上）

## Round 2 - Codex cross-vendor review (2026-11-27)
- [CODE] N - 無 finding（bash 3.2／5 探測、CI canary、腳本語法、YAML 解析通過；唯讀 sandbox 未跑完整套件）

## Round 3 - /security-review (2026-11-27, final)
- [CODE] N - 無 HIGH／MEDIUM finding：提早 exit 0 不是新的放行（main 在同條件也放行）；`"$bsnl"` 以字面比對、與舊寫法在 bash 5 下位元組相同；onFailure block 只會收緊；CI job 的 run 步驟沒有內插、不用 secrets。非安全觀察：cache hit 時跳過 sha256 檢查，binary 的完整性只靠快取範圍

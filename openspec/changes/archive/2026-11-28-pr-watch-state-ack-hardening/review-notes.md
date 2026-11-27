# Review Notes — pr-watch-state-ack-hardening

<!-- Phase 5 log. One line per review comment, appended under a `## Round N - [Review Type] (YYYY-MM-DD)` heading:
     - [REQUIREMENT|DESIGN|CODE|CONSTITUTION] Y/N - description
     Y/N answers ONE question: "must an OpenSpec artifact be updated in Phase 6?" — it does NOT mean "handled / fixed".
       [CODE] is therefore always N, even when the fix is already committed.
       [CONSTITUTION] Y = a NEW cross-feature rule to add to the project constitution; do not log "existing rules were followed".
     Tag by the artifact the fix lands in (spec → REQUIREMENT, design.md → DESIGN, code only → CODE), not by the nature of the problem.
     Never edit proposal.md / specs/ / design.md / tasks.md during review — record here, reconcile in Phase 6.
     Add `final` to the last Round heading only after the user says review has converged — the archive gate checks it. -->

## Round 1 - Final whole-branch review, opus (2026-11-27)
- [CODE] N - `watch --start --force` 的拒絕沒有測試（spec「--force 搭配其他命令」首例）；允許它的突變存活。已補案例與訊息斷言
- [CODE] N - `--start --stop --force` 遇到讀不懂的狀態檔時在互斥檢查前就移開檔案（與 Round 2 codex 同一條）。互斥檢查移到 parseArgs
- [CODE] N - `ready`／`landed` 加 `--force` 的訊息是「is for watch only」，spec 要指出只能與 `watch --stop` 並用。已改並加 f-usage-cmd 突變
- [DESIGN] Y - moveAside 的目的地是懸空 symlink 時 `existsSync` 判不存在、`renameSync` 覆蓋它；改用 `lstatSync`。design D3 只寫「目的地已存在就拒絕」，Phase 6 寫明以 lstat 判斷（symlink 本身也算佔用）
- [CODE] N - 測試的兩個 glob 斷言用測試自己的常數、永遠不會失敗；改為斷言輸出 `.watch.movedAside` 的 basename
- [CODE] N - 拒絕訊息只做子字串比對：補「以 `foreign-state:` 開頭」與「upgrade the plugin」兩個斷言
- [DESIGN] Y - D5 的突變清單與實際不符：沒有「讀得懂也移開」那個永久突變（由 `[readable state: stays in place]` 守住、審查者的同型突變被殺），實際為 f-class、f-overwrite、f-prefix、f-usage、f-usage-cmd、f-json；`--start`／`--stop` 互斥改在 parseArgs 檢查也寫進 D2/D3

## Round 2 - Codex cross-vendor (2026-11-27, final)
- [CODE] N - P2：`--start --stop --force` 遇到讀不懂的狀態檔時繞過互斥檢查而移開檔案（與 Round 1 第 2 條相同，已修）

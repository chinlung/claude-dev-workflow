# openspec-superpowers-workflow 人工確認點的實際效用（2026-11-10）

> **問題**：這個 workflow 在幾個 phase 會停下來等使用者確認。如果確認幾乎每次都通過，這些確認點還有沒有必要？能不能改成 agent 依 SDD＋TDD 一路跑完，最後再 verify？
> **證據**：
> - 本機 Claude Code transcript，2026-09-12 至 2026-11-10（transcript 保留期限內）。
> - 各專案 `openspec/changes/**/review-notes.md`。
>
> **去識別化**：本文件不寫專案名、change 名、session id 和逐筆編號；需要回查時看原始資料，不在 repo 內。
> 本文件只做分析與建議，沒有改任何程式碼或設定。

## 1. 確認點盤點

| 代號 | 位置 | 等什麼 | 現行強度 |
|---|---|---|---|
| P1 | `phases.md:100-103` | 核准 proposal.md 與 specs/ | 硬停："Do NOT proceed to Phase 2 until user explicitly approves" |
| P2 | `phases.md:109,116-120` | 核准 design.md | 半軟：最多問 2 題、design 先照預設寫；但 Phase 3 的 trigger 仍是「User approves Phase 2 design」 |
| P3 | `phases.md:165,171` | 審 tasks.md | 硬停（Quality gate） |
| P5 | `phases.md:248,256` | 宣告 review 收斂（`final`） | 只有使用者能宣告；archive-gate 會機器檢查 |
| P6b | `phases.md:279-281` | 確認改寫後的 spec | 軟："Present ... for user review" |
| P6b5 | `phases.md:302-303` | reconcile-check 回 rejected 或 needs_user_decision 時裁決 | 有條件才觸發 |

## 2. 方法

1. **找出 session**：真正跑過這個 workflow 的 session，判準是有 Skill 呼叫、讀過 phases.md，或延續 Phase N。排除 plugin 開發本身和 `~/.claude` 設定工作後，有確認點事件的 session 有 9 個，分屬 6 個專案。
2. **抽出回應**：取出這些 session 的人類回應，以及每則回應前一段 agent 文字，共 994 筆。篩掉和 openspec 無關的，剩 326 筆。
3. **分類**：由 4 個 opus 子代理逐筆分類，標出三件事：
   - 屬於哪個確認點；
   - 結果：原樣通過、照 agent 建議、選了非建議選項、改範圍、否決，或中途改方向；
   - 人類這次回應是否抓到 agent 漏掉的問題。

   326 筆全數覆蓋。回原文抽查 3 筆，標籤都正確。
4. **剔除與去重**：剔除 4 筆被誤標成確認點的 merge／收尾指令。之後以「change × 確認點」去重，避免單一長 session 主導比例。
5. **反事實**：把分類到的 25 個 change 對照各自的 review-notes.md，統計 `[REQUIREMENT] Y`／`[DESIGN] Y`。這些 Y 項是通過人工核准後，到 Phase 5 才發現的規格層修正。

## 3. 結果

### 3.1 各確認點的介入率

| 確認點 | 事件 | change 實例 | WHAT 被人類改變的 change* | 原樣通過 | 等待 p50／p75 | 等待 > 1 小時 |
|---|---|---|---|---|---|---|
| P1 核准成品 proposal／spec | 36 | 25 | **3（12%）** | 21 | 176 s／621 s | 3 |
| P1 前的範圍提問（還沒有 artifact） | 3 | 3 | 1 | 0 | — | — |
| P2 design | 28 | 19 | 1（5%） | 13 | 231 s／1391 s | 1 |
| **P3 tasks** | 20 | 20 | **0（0%）** | 15（其餘 5 筆選了建議的執行方式） | 168 s／321 s | 0 |
| P5 收斂 | 10 | 8 | 不適用（3 筆改變的是「要不要再花 token 加審」） | 4 | 177 s／296 s | 0 |
| P6b 確認改寫 | 9 | 9 | 1（11%，拒絕 agent 建議的修正） | 7 | 404 s／1926 s | 0 |

\* 只算真正改變了「要做什麼」的情形。「核准但延後某項查核」「要求跳過提問」不算。

整體數字：
- **嚴格意義的反轉（否決或退回重做）**：P1–P3 的 87 個事件中只有 1 個，約 1%。
- **P1–P3 的 87 個事件組成**：原樣通過 49、照 agent 建議 27、選非建議選項 5、暫不核准並要求再查 5、否決 1。
- **等待成本**：107 個確認點事件中，只有 4 個超過 1 小時，原因是使用者剛好不在。但這 4 個合計佔了 **22.3 小時**的實際經過時間。中位數只有 2–4 分鐘，成本集中在少數長尾。

### 3.2 確認點上「抓到問題」的 3 次，機制相同

| 確認點 | 使用者的回應 | 結果 |
|---|---|---|
| P2 | 「使用 opus review 一下 phase 1 和 phase 2」 | 抓到 1 個 Critical、3 個 Important 設計錯誤 |
| P1 | 「業界和 claude code 的最佳實踐做法和你建議一致嗎？」 | 找出 agent 沒列出的選項，使用者改選它 |
| P1 | 「以業界最佳實踐再核對一次」（一次核對多個 change） | 一份 proposal 修改，另三個 change 調整 |

**3 次都不是使用者讀 spec 時自己看出錯誤**，而是使用者在確認點要求再跑一次更強的機器審查，問題由那次審查抓到。換句話說，確認點的品質價值，大部分可以由「確認前自動跑獨立審查」取代。

### 3.3 人類不可取代的是價值與風險取捨

選了 agent **非建議**選項的例子：
- 改採更嚴格的權限方案，不給任何寫入例外；
- 接受某種失敗情境，不擴大範圍去處理；
- 在 proposal 寫出前的範圍提問中，多加了三項 agent 沒建議的項目；
- 收斂前加跑 claude-security 掃描，這是成本與風險的取捨。

另一類情形是 agent 列出替代方案、由使用者決定要不要採用。例如帳號安全政策的折衷方案：agent 自己也推薦它，但 spec 原本是照另一案寫的。

這類決定 TDD 驗證不了。測試只證明程式符合 agent 理解的 spec，不能證明 spec 是使用者要的（verification ≠ validation）。

### 3.4 反事實：確認點沒有擋住大部分規格缺陷

- **25 個經過人工核准的 change 中，有 23 個（92%）在 Phase 5 仍有 `[REQUIREMENT]`／`[DESIGN]` Y 項。** 其中有 P1 只回一句「核准」、到 Phase 5 卻記了 REQ-Y 5 條、DES-Y 22 條的例子。
- **這 25 個 change 共有 218 條 REQ／DES Y 項。** 依所在 Round 的標題歸因來源，一條可以同時屬於多個來源：
  - security 類（/security-review、claude-security）65 條；
  - codex 40 條；
  - review-branch 25 條；
  - code-audit-rigor 16 條；
  - claude[bot] 11 條；
  - 標題寫明使用者或操作者裁定的 6 條；
  - 標題看不出來源的 85 條。
- **背景參考**（分母較寬，**不是**同一批 change）：所有專案共 236 份不重複的 review-notes 中，有紀錄的 194 個 change 裡有 157 個（81%）有 REQ／DES Y。這批包含 2026-04 至 08、早於 transcript 保留期限的 change，以及格式不同的專案。
- **結論**：P1／P2 的人工核准在實務上**不是品質閘門**。能判斷來源的 Y 項，絕大多數是 Phase 5 的機器審查抓到的。

### 3.5 中途（Phase 4／5）的人類介入

Phase 4／5 期間共 50 個人類介入事件：改方向 5 次、中斷 4 次，其中 4 次抓到 agent 漏掉的問題。例如：
- 「PR 的 base 開錯分支」；
- 「先整體看規格的目的，不要在 edge case 上改到架構無法收斂」。

**這些都不是任何確認點問出來的**，而是使用者在旁邊看到後主動插話。改成一路跑完後，這類介入不會消失，只會變成事後才發現。

## 4. 判斷

### 4.1 「每次都通過就沒必要」只對一半

- **對 P3 成立。** 0／20 改變，而且輸出可以機器核對：每個設計決策都有對應任務、每個 Task 恰好一個勾選框，這些規則已經寫在 `OUTPUT-CONTRACTS.md:88`。
- **對 P1 只成立一半。** 成品 spec 的核准點上，12% 的 change 改變了 WHAT。其中 2 個是使用者要求加查最佳實踐之後才浮現的，真正靠人類直接取捨的只有 1 個。這種錯誤如果晚發現，代價是整段實作重做；而確認點的等待中位數約 3 分鐘，只有長尾超過 5 小時。
- **通過率高的另一面是走過場。** P1–P3 有 56% 原樣通過。不過 P1 的 21 筆原樣通過中，只有 5 筆在 60 秒內回覆，其餘多半有幾分鐘的閱讀時間，所以不能全算成橡皮圖章。資料顯示，確認點較大的價值不在使用者逐字審 spec，而在逼 agent 把待決事項攤開。拿掉確認點時，這個作用要保留。

### 4.2 「SDD＋TDD 一路跑完、最後 verify」可行，但要三個前提

1. **WHAT 層的決策仍由人做，但改成「有決策要做才停」，不再每個 phase 都停。** 什麼時候該停，不能交給 agent 自己判斷。中途被使用者糾正的兩件事（PR base 開錯、edge case 修到架構無法收斂），agent 都沒有主動提出。skip-gate hook 存在，也正是因為 agent 自己宣告「沒有契約面風險」並不可靠。所以觸發條件要綁在 hook 讀得到的事實上：
   - 八項契約面聲明中，任一面為「是」，就硬停；
   - 改動的路徑落在高風險域清單內，就硬停；
   - design.md 的 `## Open Questions` 不是空的，就硬停。

   其餘情況改成非同步：先通知使用者、照預設繼續，使用者可以事後否決。
2. **最後的 verify 只驗證、不確認需求。** 所以「待決事項清單」和「agent 自行採用的預設」必須寫進 artifact，讓使用者事後能否決。
3. **高風險域（auth／crypto／payment／IaC）維持 P1 硬停。** 這類錯誤晚發現的代價沒有上限，和漏抓的代價遠高於誤判的不對稱原則一致。

### 4.3 對照業界做法

> 以下都來自二手資料。搜尋沒有拿到 Anthropic 原文頁，原文措辭以 anthropic.com/engineering/building-effective-agents 為準。

- **Anthropic〈Building effective agents〉**：多份轉述提到，agent 在 checkpoint 或遇到阻礙時暫停、取得人類回饋，並以工具或執行結果作為每一步的 ground truth；停止條件（迭代上限）是另一套機制。重點是在資訊不足處停、搭配可驗證的環境回饋，而不是每個階段都停。（[besthub.dev 轉述](https://www.besthub.dev/articles/how-anthropic-builds-effective-ai-agents-practical-patterns-and-principles-01de16a84598)、[cobusgreyling 轉述](https://cobusgreyling.substack.com/p/anthropics-research-on-genai-building)）
- **Approval fatigue**：有第三方指南指出，每個動作都要求核准，會讓核准淪為橡皮圖章，所以硬停應該只留給後果重大的動作。這不是 Anthropic 的措辭。（[genai4a11 human-in-the-loop](https://genai4a11.github.io/concepts/human-in-the-loop.html)）
- **Kiro（spec-driven IDE）**：提供 Autopilot 與 Supervised 兩種模式。第三方資料建議：理解清楚的工作用 Autopilot；auth、基礎設施、外部契約等關鍵元件用 Supervised。但沒有資料說明兩種模式下 spec 各階段是否需要核准。（[dev.to: Letting Kiro drive](https://dev.to/aws-builders/letting-kiro-drive-autopilot-and-hooks-12c0)、[Kiro workshop: spec vs vibe](https://awsugbne.github.io/kiro-workshop-feb26/core-concepts/spec-vs-vibe)）
- **本文件的建議方向和上述一致**：依風險分級決定要不要停（高風險域與契約面硬停），而不是每個 phase 一律停。

## 5. 各確認點的建議

| 確認點 | 建議 | 理由 |
|---|---|---|
| **P1 spec** | **保留，但改成有決策才停**：確認前自動跑獨立的 spec 審查（opus）和最佳實踐比對，結果和待決事項清單一起呈現。停不停綁在 hook 讀得到的事實上（契約面、高風險路徑、Open Questions 非空），其餘情況改為非同步：通知使用者後繼續，使用者可否決 | 12% 改變 WHAT；3 次抓到問題中有 2 次來自使用者要求加跑審查，可以改成預設步驟 |
| **P2 design** | **改為非同步**：會改變 WHAT 的設計問題，併到 P1 一起問；其餘照預設寫進 `## Open Questions` 後直接進 Phase 3 | 13／28 原樣通過，其餘多半照 agent 建議；`phases.md:118` 已經是「先寫再問」，只差 Phase 3 的 trigger 不再等核准 |
| **P3 tasks** | **拿掉，改成機器閘門**：由 validator 核對 tasks.md 的格式，以及每個設計決策都有對應任務；執行方式（Native／SDD）用預設值 | 0／20 改變 |
| **P5 收斂** | **保留給使用者，但提供收斂政策**：例如最後一輪各層審查都沒有新的 Y 項時，由 agent 主動建議收斂；使用者只決定要不要加跑高成本掃描 | 改變的內容是「要不要再花 token」，屬於預算決定 |
| **P6b 確認改寫** | **改成機器閘門加上 PR 的非同步審查**：reconcile-check 已經存在；歸檔 PR 合併時，使用者本來就會看 | 1／9 |
| P6b5 needs_user_decision | 維持 | 本期 0 次觸發，沒有成本 |

照這些建議，一個典型 change 的硬停會從 4–5 次降到最多 2 次：P1 只在有待決事項時停，加上 P5 收斂。

## 6. 限制

- **樣本集中**：只有 9 個 session、2 個月的資料，P1–P3 事件約 70% 來自同一個專案的兩個長 session。使用者只有一位，而且就是 plugin 作者本人；換成較不熟悉的使用者，介入率可能更高。
- **保留期限**：transcript 只回溯到 2026-09-12。更早的 change 雖然有 review-notes，但沒有對話可以對照。
- **分類由模型判定**：opus 的標籤只人工抽查了 3 筆。4 個分類子代理中，有 2 個在檔案寫出之前就回報了計數，前後兩次的數字也不一致。所有統計都以磁碟上的分類檔重算，沒有採用子代理自己報的摘要。
- **Y 項不全是確認點的失誤**：有些是實作之後才可能知道的事。另外有 84 條 `[CODE] Y`，顯示 Y／N 仍有誤標。
- **測不到「準備效應」**：為了確認點把待決事項整理出來，這件事本身就有價值，但本資料量不到。這也是建議保留待決事項清單的原因。

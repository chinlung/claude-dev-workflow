# Plugin 優化修正計劃 — 2026-07-02

**前置文件：** `docs/loop-design-review-2026-07-01.md`（三輪修正的設計依據與執行紀錄）
**本文件目的：** 逐項源碼驗證 7/1 三輪修正的宣稱是否屬實，盤點殘留缺口，給出下一步的優先序。

---

## 1. 宣稱驗證結果（逐項親自 Read / 執行確認）

| 宣稱 | 驗證方式 | 結果 |
|---|---|---|
| 133 checks 全過 | `node scripts/validate-fixtures.cjs` 實跑 | ✅ 133 passed, 0 failed |
| debate 6a 結構閘門 live（1.2.0） | Read `debate.md`:157-172 | ✅ emit `debate-output.json` → 跑 `validate-debate-output.cjs` → exit 0 才進 6b；失敗有修正迴路（組裝錯→重跑；辯論不自洽→比照 `rejected` 退回 Phase 2）；不得靜默跳過 |
| debate Tier-2（閘門接進迴圈退出條件） | 同上 | ✅ 已隨 6a 一併完成，review 文件 §5 Tier 2 對 debate 的目標已達成 |
| HP 環境測試閘門（1.3.0） | Read `start.md`:153-167 | ✅ controller 親跑 SPEC 測試、`WF_TEST_EXIT=$?` sentinel、接 capped fix-loop、元規則 (a)(b) 明文寫入 |
| openspec live pre-check（1.2.1） | Read `phases.md`:66-71 | ✅ Phase 1 step 4 lenient pre-check 在 `openspec validate --strict` 之前 |
| CI + PostToolUse hook 強制層 | ls `.github/workflows/` + grep `scripts/hooks/` | ✅ `validate.yml` 與 `validate-on-plugin-edit.cjs` 都在，hook 邏輯放 repo 內版控（符合 sandbox 紀律） |
| 版本一致性 | Read `marketplace.json` | ✅ 1.8.10；各 plugin 版本與 CHANGELOG 對齊 |
| security-audit vendored 同步狀態 | `gh api compare/4de1ac8...HEAD` | ✅ 上游僅 1 個新 commit（`f75f9a0`），純 rename +0/−0，**內容零 drift** |

**結論：三輪修正的宣稱全部屬實，工程債已清。**「結果不如預期順利」的根因不是 security-audit 參考模型不好，而是 PR #4 的移植方式——把「結構閘門」cargo-cult 式統一鋪到四個 plugin，卻只有一個接到 live path，且漏 bump 版本。這兩個根因的預防紀律都已寫入 `~/.claude/CLAUDE.md`（Test/Gate Enforcement 兩條 + Release/Versioning 一條），修正路徑（per-plugin「lift vs 邊際價值」裁決）也被 `/debate` 對抗式檢驗確認正確。

---

## 2. 殘留缺口與修正計劃（優先序）

### P1 — security-audit「vendored 了但沒接進工作流」（最直接呼應原始預想的落空處）

原始預想是「參考 cloudflare/security-audit-skill 改進本 repo 的 plugin」。結構閘門模式的移植已完成（見 §1），但 **security-audit plugin 本身 6/29 vendored 進來後，從未進入使用決策流程**：

- `~/.claude/CLAUDE.md` 的「Plugin 使用決策樹 › Code Review」只有 review-branch / code-audit-rigor / audit-review-fix 三個入口，**沒有 security-audit 的觸發條件**。README 寫了互補定位（security-audit 主動獵捕 exploit、code-audit-rigor 治理 PR review），但決策樹沒反映。
- 建議動作：在決策樹 Code Review 段加一行入口，例如「主動式漏洞獵捕（無特定 diff、對整個 codebase 找可利用漏洞、pen-test 式審查）→ `/security-audit`；與 `/code-audit-rigor`（diff/PR 治理）互補」。
- 成本 🟢（一行 CLAUDE.md），價值高——否則 plugin 是死庫存。

### P2 — HP 1.5.0 跨家族 model 指派從未 live-test

1.5.0（`model: opus` / `model: sonnet` frontmatter）是三輪修正中**唯一沒有實跑驗證的變更**（debate 1.2.0 已在 §8 re-examination 中 live-test 過）。`model` 是合法 frontmatter 欄位、agents 有註冊，但「agent 真的跑在指定家族」只有實跑一輪 `/high-precision-dev:start` 冒煙才算環境事實。
- 建議動作：找一個小型 SPEC 跑一次冒煙（或下次真實使用時記錄），確認六個 agent 的實際 model。
- 成本 🟡（一輪 HP 流程），風險：若 frontmatter 被忽略，1.5.0 的「最大去相關槓桿」實際是 no-op。

### P3 — security-audit 的 validator 不在 fixture suite / hook 覆蓋

`validate-findings.cjs` 是四個 validator 中唯一不受 `scripts/validate-fixtures.cjs` + CI + PostToolUse hook 保護的。按元規則檢驗：(a) fixture check 讀 exit code（環境事實）✅、(b) 消費者是 CI 擋 merge ✅——**有資格加**。但另一面：檔案是 vendored verbatim、更新只來自上游 re-vendor，本地變異機率低。
- 建議動作（二擇一，都可辯護）：
  - 加 2-3 個最小 smoke fixtures（1 valid + 1-2 invalid mutation），納入 runner——防未來有人動 vendored 檔或 Node 版本行為漂移；
  - 或在 `scripts/validate-fixtures.cjs` 註明「security-audit 刻意排除：vendored verbatim，以上游 pin 為準」，把「不加」變成明文決定而非遺漏。
- 成本 🟢。

### P4 — vendoring pin 註記更新 + openspec pre-check 路徑一致性

- CHANGELOG pin 寫 `4de1ac8`；上游 HEAD `f75f9a0` 已確認純 rename、內容零 drift。在 CHANGELOG 補一行「已對照 f75f9a0，純目錄重構，內容一致」，未來 re-vendor 檢查點就從 f75f9a0 起算。🟢
- `phases.md`:68 的 pre-check 用相對路徑 + prose 說明（「resolve it from where the skill is installed」），而 `debate.md` 用 `${CLAUDE_PLUGIN_ROOT}`。先查證 **skill 上下文是否可用 `${CLAUDE_PLUGIN_ROOT}`**（command 可以，skill 未確認——別靠記憶猜）；可用則統一，不可用則維持現狀並在 debate.md 風格說明中註記差異原因。🟢

### P5 — 擱置項做明文處置（避免變成沉默的半成品）

Review 文件 Tier 3 有兩項既沒做也沒列入「Dropped」清單，狀態懸空：
- **#4** code-audit-rigor 超過 diff 門檻的多角度 fan-out（🔵 judgment call）
- **#13** openspec phase-completion 判準機械化（🔵 low urgency）

建議：明確裁決 won't-do（並補進 review 文件 §0 的 Dropped 清單）或給出觸發條件（例如「等 audit-review-fix 實戰中出現 routine review 漏抓案例再議」）。維持懸空是最差選項。🟢

### P6 —（決策項）dev-workflow 是否從 marketplace 下架

`dev-workflow` 1.0.2 仍在 `marketplace.json`，但 2026-05-09 已從本機 uninstall、決策樹重整後不再引用它。它的功能已被 openspec-superpowers-workflow + 各專用 plugin 取代。
- 選項：(a) 從 marketplace 移除 + plugin 目錄標記 deprecated（保留歷史）；(b) 整個目錄移除；(c) 保留現狀（供其他安裝者用）。
- 這是 outward-facing 決策（影響 marketplace 使用者），**需使用者裁決**，不自行執行。

---

## 3. 建議執行順序

```
P1 CLAUDE.md 決策樹加 security-audit 入口   🟢 一行，立即
P4 pin 註記 + 路徑一致性查證                 🟢 十分鐘
P5 Tier-3 懸空項明文處置                     🟢 十分鐘（won't-do 只需補文件）
P3 security-audit fixture 覆蓋（或明文排除）  🟢 半小時
P2 HP 1.5.0 冒煙驗證                         🟡 下次真實使用時順帶，或專跑一輪小 SPEC
P6 dev-workflow 處置                         🔵 等使用者裁決
```

P1–P5 全部完成後，「參考 security-audit 改進本 repo plugin」的原始預想即完整落地：結構閘門模式已按 per-plugin 邊際價值移植（而非 cargo-cult 統一鋪設），security-audit 本體進入使用決策流程，且所有機器閘門都符合「讀環境事實 + 有下游消費者」的元規則。

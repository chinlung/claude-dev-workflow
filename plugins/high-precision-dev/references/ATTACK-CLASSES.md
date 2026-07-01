# Attack Classes Reference

**When to read this:** Adversary 在 Phase 3 開始三輪攻擊前；Disproof Agent 在 Phase 3.5 評估 adversary 的 ATTACKS.md 前；Verifier 在步驟零確認攻擊覆蓋完整性時。本文件詳細描述三輪九類攻擊模式（Round 1：2 類；Round 2：4 類；Round 3：3 類），補充 `adversary.md` 的攻擊架構。

---

## Round 1 攻擊類別：邊界攻擊（Boundary Attacks）

邊界攻擊針對每個輸入參數的型別邊界。以下是每種型別的必要攻擊矩陣：

### 數值型邊界

| 攻擊輸入 | 目標問題 | 嚴重性基準 |
|---------|---------|-----------|
| `0` | 除以零、空集合迭代、索引 off-by-one | Medium-High |
| `-1` | 負索引、無符號整數下溢 | Medium-High |
| `INT_MAX / INT_MIN` | 整數溢出（特別是加法） | High |
| `NaN`, `Infinity` | 浮點數比較（`NaN != NaN` 在 JS/Python） | Medium |

**具體攻擊範例（正確寫法）：**
```python
# 攻擊目標：處理分頁的函式 get_page(page_num, page_size)
get_page(0, 10)      # 第 0 頁——應該是 1-indexed 還是 0-indexed？
get_page(-1, 10)     # 負頁碼——應拋出 ValidationError 而非返回最後一頁
get_page(1, 0)       # page_size=0——應拋出 ValidationError 而非除以零
get_page(1, 2**31)   # 極大 page_size——應有上限限制
```

### 字串型邊界

| 攻擊輸入 | 目標問題 |
|---------|---------|
| `""` | 空字串未驗證就使用（例如 `split("")` 在各語言行為不同） |
| `"   "` | 只有空白——有時通過 `if field:` 的空值檢查但仍是無效輸入 |
| 10,000+ 字元 | 緩衝區限制、資料庫欄位長度、記憶體攻擊 |
| 含 `\0` 的字串 | C 字串截斷、日誌注入 |
| 含換行符 `\n\r` | Header 注入、日誌偽造 |
| 含 emoji（4-byte UTF-8）| 字元計數 vs 位元組計數不一致導致截斷 |

---

## Round 2 攻擊類別：語意攻擊（Semantic / Business Logic Attacks）

語意攻擊針對業務邏輯層，而不是型別邊界。

### 2a. 業務邏輯濫用（Business Logic Abuse）

問：「如何讓這個系統做**它不應該做**的事？」

**範例：**
```
系統：折扣碼 API，每個碼只能使用一次
攻擊：同時發出 100 個 PATCH /apply-coupon 請求（使用同一個折扣碼）
預期問題：若 check-then-act 不在同一個 transaction 中，折扣碼可以被使用多次
```

### 2b. 組合攻擊（Combination Attack）

問：「有沒有辦法讓兩個合法操作的**組合**產生非法狀態？」

**範例：**
```
系統：訂單狀態機 draft → confirmed → shipped → completed
攻擊：confirmed 後立即呼叫 cancel（cancel 只允許 draft 狀態）
      同時呼叫 ship（ship 只允許 confirmed 狀態）
預期問題：若這兩個操作在 DB 層沒有鎖，狀態可能變成 shipped + cancelled 的矛盾狀態
```

### 2c. 冪等性攻擊（Idempotency Attack）

問：「如果我**重複執行**同一個操作，狀態還是正確的嗎？」

**範例：**
```
系統：扣款 API POST /debit {amount: 100}
攻擊：同一個請求重送（網路逾時後重試）
預期問題：若沒有冪等鍵（idempotency key），可能被扣兩次
```

### 2d. 順序攻擊（Ordering Attack）

問：「如果我把操作的**執行順序顛倒**，會發生什麼？」

**範例：**
```
系統：Webhook 訂閱流程 → 先 subscribe 再 verify
攻擊：直接呼叫 verify endpoint（跳過 subscribe）
預期問題：若 verify 假設 subscription 一定存在，可能拋出 NullPointerException
```

---

## Round 3 攻擊類別：假設攻擊（Assumption Attacks）

假設攻擊針對「實作者以為永遠成立，但其實可能不成立」的前提。

### 3a. 未驗證的外部狀態（Unvalidated External State）

**識別方式：** 找到所有直接使用外部資料（API 回應、資料庫查詢結果、環境變數）而沒有驗證的地方。

**範例：**
```python
# 假設攻擊：user = db.get_user(user_id) 之後直接使用 user.role
# 沒有驗證 user 是否為 None
# 沒有驗證 user.role 是否在允許的角色列表中
user = db.get_user(user_id)
if user.role == "admin":  # 若 user 為 None → AttributeError
    grant_admin_access()
```

### 3b. 競態條件（Concurrency / Race Condition）

**識別方式：** 找到所有 check-then-act 模式（先讀取狀態，再根據狀態操作）。

注意：`adversary.md` Round 2 的第 5 問也涵蓋並發場景；此處從「實作假設是否成立」角度深入分析。DISPROOF.md 評估時不必因輪次名稱不同而視為不同攻擊類別。

**範例：**
```python
# 假設攻擊
if not user.is_banned:       # Thread A: 讀取 is_banned = False
    send_email(user)         # Thread B: 同時 ban 了這個使用者
                             # Thread A: 仍然發送了郵件給已封禁使用者
```

### 3c. 無效的外部狀態（Invalid External State）

問：「如果依賴的外部服務或資料來源返回了非預期的值，會發生什麼？」

| 假設 | 攻擊場景 |
|------|---------|
| 資料庫欄位永遠有值 | 欄位為 NULL（歷史資料遷移留下的問題） |
| 外部 API 永遠返回 JSON | 外部 API 返回 502 HTML 頁面 |
| 環境變數永遠存在 | 部署時漏設某個 env var |
| 時鐘永遠正確 | 伺服器時鐘偏移（特別是 JWT 的 `exp` 驗證） |

---

## Severity 校準指南

使用與 critic 統一的 severity 1-5 分級：

| Severity | 定義 | 攻擊範例 |
|----------|------|---------|
| 5 | 資料損毀、安全漏洞、生產崩潰 | 並發扣款導致重複扣費、auth bypass |
| 4 | 重要業務流程中斷但可恢復 | 折扣碼可被重複使用 |
| 3 | 明顯錯誤但影響範圍有限 | 邊界輸入返回錯誤的錯誤碼 |
| 2 | 輕微不符合規格、使用者體驗問題 | 空字串應返回 400 但返回了 422 |
| 1 | 文件不一致、極罕見情況 | 極大數值的效能退化（非崩潰） |

**高 Severity 的必要條件：** 必須有具體的攻擊輸入（可執行的程式碼），而不只是「可能有問題」的描述。Disproof Agent 在 Phase 3.5 會要求重現反例。

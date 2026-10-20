#!/bin/bash
# security-audit：跑上游隨 vendored validator 出貨的測試套件（validate-findings、validate-coverage-ledger）
# 用法:bash plugins/security-audit/tests/upstream.test.sh
# 消費者:validate-on-plugin-edit hook（列舉 tests/*.test.sh）+ CI(.github/workflows/validate.yml)
# 測試檔是上游逐字 vendored 的內容，本檔只負責執行；fixture＋單欄位突變另在 scripts/validate-fixtures.cjs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$SCRIPT_DIR/../skills/security-audit"

TESTS=("$SKILL_DIR/validate-findings.test.cjs" "$SKILL_DIR/validate-coverage-ledger.test.cjs")

# 逐一確認存在：node --test 拿到「一支存在、一支不存在」時只跑存在的那支並回 0（node 22 實測），
# re-vendor 漏複製一支會變成靜默少跑
for f in "${TESTS[@]}"; do
  [ -f "$f" ] || { echo "FAIL: missing vendored test file $f" >&2; exit 1; }
done

node --test "${TESTS[@]}"

// Canonical audit-review-fix Workflow script.
//
// 跨專案重用：
// 1. 在任何專案 session 中，把整份檔案內容當作 `script` 參數傳給 Workflow tool
//    （不能用 file:// import — Workflow 需要 script 字串）
// 2. 或從本機讀進來再傳：Read 此檔 → 把內容傳入 Workflow({ script: <content>, args })
// 3. 已建立過的 run 可用 scriptPath + resumeFromRunId 續跑（cache 秒回）
//
// 限制：
// - `today` 預設 hardcoded（因 Workflow 禁用 Date.now() / new Date() 避免破壞 resume）
//   呼叫時務必傳 args.today = 'YYYY-MM-DD' 否則報告檔名會錯
//
// 完整使用說明：本 plugin 內 workflow/audit-review-fix.md（${CLAUDE_PLUGIN_ROOT}/workflow/audit-review-fix.md）
// 設計背景：2026-05-29 NewebPay payment state machine 修復 session
// 詳細坑（外部選讀，通用 workflow 知識，未隨本 plugin 發佈）：作者個人 refs/workflow-gotchas.md

export const meta = {
  name: 'audit-review-fix',
  description: 'Hybrid /code-review + /security-review + /code-audit-rigor + safe auto-fix. Multi-angle parallel finders, per-finding adversarial verification, sweep, EV-math + boy-scout triage, low-risk auto-fix with test enforcement, audit report to disk.',
  phases: [
    { title: 'Scope', detail: 'gather diff + file list' },
    { title: 'Baseline', detail: 'snapshot pre-existing test failures so Verify Fix only counts NEW regressions' },
    { title: 'Review', detail: '9-angle parallel finder pass' },
    { title: 'Verify', detail: 'per-finding adversarial verification' },
    { title: 'Sweep', detail: 'fresh reviewer for gaps' },
    { title: 'Triage', detail: 'EV math + boy-scout discipline' },
    { title: 'Fix', detail: 'apply safe fixes with test enforcement' },
    { title: 'Verify Fix', detail: 'run tests + formatter, compare new failures vs baseline' },
    { title: 'Report', detail: 'write audit-rigor report to audits/' },
  ],
}

const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'short stable id like A-1, B-2' },
          file: { type: 'string' },
          line: { type: 'string', description: 'line number or range' },
          summary: { type: 'string' },
          severity: { enum: ['Critical', 'High', 'Medium', 'Low'] },
          confidence: { type: 'number', minimum: 0, maximum: 100 },
          claim: { type: 'string' },
          evidence: { type: 'string', description: '1-3 sentences why it is wrong' },
          stride: { enum: ['S', 'T', 'R', 'I', 'D', 'E', 'NA'] },
          cwe: { type: 'string', description: 'CWE-NNN or NA' },
          failureScenario: { type: 'string', description: 'concrete inputs/state to wrong output/crash' },
        },
        required: ['id', 'file', 'line', 'summary', 'severity', 'confidence', 'claim', 'evidence', 'failureScenario'],
      },
    },
  },
  required: ['findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    vote: { enum: ['CONFIRMED', 'PLAUSIBLE', 'REFUTED'] },
    revisedConfidence: { type: 'number', minimum: 0, maximum: 100 },
    reasoning: { type: 'string' },
    crossReferences: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          lines: { type: 'string' },
          note: { type: 'string' },
        },
        required: ['file', 'lines', 'note'],
      },
    },
  },
  required: ['vote', 'revisedConfidence', 'reasoning', 'crossReferences'],
}

const TRIAGE_SCHEMA = {
  type: 'object',
  properties: {
    decision: { enum: ['MUST_FIX', 'BOY_SCOUT_FIX', 'DEFER_OUT_OF_SCOPE', 'DISMISS'] },
    estimatedLoc: { type: 'number' },
    behaviorChangeRisk: { enum: ['none', 'low', 'medium', 'high'] },
    requiresUserDecision: { type: 'boolean' },
    reasoning: { type: 'string' },
  },
  required: ['decision', 'estimatedLoc', 'behaviorChangeRisk', 'requiresUserDecision', 'reasoning'],
}

const FIX_SCHEMA = {
  type: 'object',
  properties: {
    applied: { type: 'boolean' },
    filesModified: { type: 'array', items: { type: 'string' } },
    testsAddedOrUpdated: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
    skipReason: { type: 'string', description: 'if applied=false, why skipped' },
  },
  required: ['applied', 'filesModified', 'summary'],
}

// args 正規化：部分 Workflow runtime 把 args 以 JSON 字串送達（已實測 typeof args==='string'），
// 而非 tool 文件承諾的 parsed object。直接讀 args.baseRef 會在字串上得 undefined → 所有旗標
// 靜默吃預設值（baseRef/model/votes/angles/focus/sweep 全失效）。此層統一轉成 object，parse 失敗
// 退回 {}（零退化：等同沒傳 args）。下方所有參數讀取一律走 A0，不再直接碰全域 args。
const A0 = typeof args === 'string' ? (() => { try { return JSON.parse(args || '{}') } catch (e) { return {} } })() : (args || {})

const baseRef = A0.baseRef || 'origin/main'
const allowAutoFix = A0.autoFix !== false
const today = A0.today || '2026-05-29'
const focus = A0.focus || null // git pathspec：只審符合的路徑（大 diff 省 token + 範圍紀律）
const testCmd = A0.testCmd || null // 覆寫測試指令（非標準 runner，如 'make test'）
const testCmdDirective = testCmd ? 'IMPORTANT: run this EXACT test command, do NOT auto-detect: ' + testCmd + '\n\n' : ''
// 成本/嚴格度旗標（皆有零退化預設）：
const doSweep = A0.sweep !== false // --no-sweep → false：跳過 Sweep 階段
const keepAll = !!A0.keepAll // --keep-all → true：關閉 EV 自動 dismiss（low-EV 仍進 triage agent）
const maxFixLoc = A0.maxFixLoc != null ? A0.maxFixLoc : Infinity // --max-fix-loc N：自動修 LOC 上限。用 !=null 而非 `||Infinity`：後者會把 0（最緊上限）當 falsy → Infinity（無上限），危險反轉
// （--angles N 對應的 activeAngles 定義在 ANGLES 之後）

// 統一模型覆寫：傳了 args.model（如 'haiku' / 'sonnet'）→ 所有 agent 降階壓成本；
// 不傳 → undefined ≡ 沿用 session model（原行為，零退化）。透過 A() wrapper 注入，
// 不必逐一改 10 個 agent() options。降階會犧牲 recall——高風險域審查請審慎使用。
const agentModel = A0.model || undefined
const A = (prompt, opts) => agent(prompt, agentModel ? { ...opts, model: agentModel } : opts)

// 從測試輸出解析「失敗數」摘要（framework-agnostic）。用於 Verify Fix 在
// 失敗鍵（FAIL <file>）粒度太粗時（如 jest 檔案級）仍能抓出「同檔新增 failure」
// 這種 key 不變但數量上升的 regression。解析不到回 null（呼叫端跳過數量比對）。
function parseFailCount(text) {
  if (!text) return null
  const m = text.match(/(\d+)\s+failed/i) || text.match(/Failures:\s*(\d+)/i)
  return m ? parseInt(m[1], 10) : null
}

phase('Scope')

const pathspec = focus ? ' -- ' + focus : ''
const scopePrompt = 'Run git diff ' + baseRef + '...HEAD' + pathspec + ' then git diff HEAD' + pathspec + ' (working tree). Concatenate as one unified diff. List modified file paths separately.\n\nOutput format:\n=== UNIFIED DIFF ===\n<combined diff>\n=== FILE LIST ===\n<one absolute path per line>\n=== END ===\n\nSkip vendor/, node_modules/, .git/. If diff is huge, prioritize app/, lib/, src/, tests/ — keep total under ~30,000 tokens.' + (focus ? '\n\nSCOPE FILTER: only files under git pathspec "' + focus + '" are in scope; the pathspec is already applied to the diff commands above — do not widen it.' : '')

const scopeText = await A(scopePrompt, { label: 'gather-diff', phase: 'Scope' })

// baseRef 打錯（如本機無 origin/main）時 git diff 會吐 fatal/unknown revision。
// 只在「出現 git 錯誤字樣」且「整段不含任何真實 diff 標記」時才中止——若已有
// diff --git/@@ 內容（即使某行剛好含 'fatal:'）就不誤判，故近乎零 false-positive。
const looksLikeGitError = /fatal:|unknown revision|ambiguous argument|not a git repository/i.test(scopeText ? scopeText.slice(0, 400) : '')
const hasRealDiff = scopeText ? /diff --git|^@@ |^\+\+\+ |^--- /m.test(scopeText) : false
if (!scopeText || scopeText.length < 100 || /no changes|nothing to commit/i.test(scopeText.slice(-300)) || (looksLikeGitError && !hasRealDiff)) {
  log(looksLikeGitError && !hasRealDiff ? 'Scope step hit a git error (bad baseRef?) with no diff content — aborting.' : 'No changes to review. Workflow complete.')
  return { status: 'EMPTY_DIFF', reviewed: 0, applied: 0 }
}

log('Diff gathered (' + Math.round(scopeText.length / 1000) + 'k chars).')

// Phase Baseline：跑一次 pre-fix tests，記錄已存在的 failure，避免 Verify Fix
// 把 pre-existing failure 誤判成本次 workflow 造成的 regression（false positive 已實測過）。
// 只在 allowAutoFix=true 時跑（若不打算改 code 就不需要 baseline，節省 token）。
let baselineFailureKeys = []
let baselineFailCount = null
let hasBaseline = false

if (allowAutoFix) {
  phase('Baseline')
  const baselinePrompt = 'Run the project test suite ONCE to capture pre-existing test failures. Do NOT modify any files.\n\n' + testCmdDirective + 'Laravel/PHP: php artisan test 2>&1 | tail -80\nNode/TS: npm test 2>&1 | tail -80\nPython: pytest 2>&1 | tail -80\n\nReturn the LAST ~80 lines of output verbatim, including the phpunit/jest/pytest summary line and any FAILED markers. Do not summarize.'
  const baselineText = await A(baselinePrompt, { label: 'baseline-tests', phase: 'Baseline' })

  if (baselineText) {
    // 抓 FAILED test names。phpunit/pest 格式：「FAILED  Tests\Feature\X > it does Y」
    // npm test/jest：「FAIL  src/foo.test.ts > test name」
    // pytest：「FAILED tests/test_foo.py::test_bar」
    const failureMatches = baselineText.match(/FAIL(ED)?\s+[^\n]+/gi) || []
    baselineFailureKeys = [...new Set(failureMatches.map((s) => s.trim()))]
    baselineFailCount = parseFailCount(baselineText)
    hasBaseline = true
    log('Baseline captured: ' + baselineFailureKeys.length + ' pre-existing failure key(s)' + (baselineFailCount != null ? ', ' + baselineFailCount + ' reported failed' : '') + '.')
  } else {
    log('Baseline run returned empty output — Verify Fix will fall back to strict regex.')
  }
}

const ANGLES = [
  { id: 'A', name: 'line-by-line', focus: 'Read every changed hunk + enclosing function. Flag inverted conditions, off-by-one, null deref, missing await, falsy-zero, wrong-variable copy-paste, errors swallowed in catch, unescaped regex metachars. Bugs in unchanged lines of touched functions are in scope.' },
  { id: 'B', name: 'removed-behavior', focus: 'For every deleted or short-circuited line: name the invariant it enforced, then search new code for where the invariant is re-established. Missing re-establishment is a finding.' },
  { id: 'C', name: 'cross-file', focus: 'For each changed function: grep callers and check whether the change breaks call sites (new precondition, changed return shape, new exception, timing dependency). Also check callees for parallel-PR co-changes.' },
  { id: 'D', name: 'language-pitfall', focus: 'Classic pitfalls. PHP/Laravel: enum nullability, mass-assignment, Eloquent N+1, DB::raw injection, observer firing on every save. JS/TS: falsy-zero, == coercion, closure-captured loop var. Python: mutable defaults, late-binding closures. SQL injection, timezone/DST, float equality. Race conditions in tests.' },
  { id: 'E', name: 'wrapper-proxy', focus: 'For new wrappers/decorators/adapters: verify all methods route to wrapped instance not back through registry/global. Check the wrapper forwards all methods callers actually use.' },
  { id: 'F', name: 'reuse', focus: 'Flag new code that re-implements something the codebase already has. Grep shared/utility modules and adjacent files. Name the existing helper to call instead.' },
  { id: 'G', name: 'simplification', focus: 'Flag unnecessary complexity, copy-paste with slight variation, deep nesting, dead code. Name the simpler form that does the same job.' },
  { id: 'H', name: 'efficiency', focus: 'Flag wasted work: redundant computation, repeated I/O, sequential ops that could parallelize, blocking work in hot paths, double-save patterns. Name the cheaper alternative.' },
  { id: 'I', name: 'altitude', focus: 'Each change implemented at right depth? Special cases layered on shared infra = wrong altitude. Prefer generalizing underlying mechanism over special cases. Check if a model-layer or framework-layer fix would close more bugs than the patch under review.' },
]

// --angles N：取前 N 個角度（A-I 已按 recall 價值排序，前段是核心 bug 角度，
// 後段偏 quality/refactor）。clamp 到 [1, 全部]；不傳 → 全 9 角，零退化。
// 用 !=null 而非 `|| ANGLES.length`：後者把 A0.angles===0 當 falsy → 回全 9 角
// （與「最少」意圖相反）。!=null 讓 0 進下方 clamp（→ 1），且與 maxFixLoc 解析一致、
// 容忍 numeric-string（下方 Math.min/max 會強制轉型）。
const reqAngles = A0.angles != null ? A0.angles : ANGLES.length
const activeAngles = ANGLES.slice(0, Math.max(1, Math.min(ANGLES.length, reqAngles)))

// 對抗式驗證：每個 finding 跑 verifyVotes 個獨立 verifier，recall mode——只有
// 「多數票 REFUTED」才 drop。votes=1（預設）與單票完全相同：不加 lens、label
// 不加 -vN、prompt 不變 → agent 簽名一致、resume 快取照命中、EV/triage 零退化。
// votes>1 時每票套不同 lens（perspective-diverse 勝過 N 個一樣的 refuter）。
const verifyVotes = Math.max(1, Math.floor(A0.votes || 1))
const VERIFY_LENSES = [
  'correctness — 具體輸入/狀態是否真能到達錯誤輸出？',
  'guard-chain — 呼叫鏈上游或 framework/runtime 是否已防護？',
  'reproduce — 能否給出可重現的具體 trigger，而非泛泛宣稱？',
]

async function verifyFinding(f, angleId, phaseLabel) {
  const base = 'You are an adversarial verifier. Steel-man this finding to find evidence it might be REFUTED.\n\nCANDIDATE FINDING:\n' + JSON.stringify(f, null, 2) + '\n\nYOUR TASK:\n1. Read the cross-referenced file:lines yourself using Read/Grep (Principle 3: verify source, not diff).\n2. Steel-man the opposite: is the framework or runtime already preventing this? Is there a guard further up the call chain? Is the assumed adversarial input actually validated upstream?\n3. Vote one of:\n   - CONFIRMED: verified inputs/state + observed wrong output / can quote the line.\n   - PLAUSIBLE: mechanism is real, trigger uncertain (timing/env/config).\n   - REFUTED: factually wrong, or guarded elsewhere — quote the line that proves it.\n4. Provide revisedConfidence (0-100) and crossReferences citing specific file:lines you actually read.\n\nThis is recall mode — only REFUTED drops the finding.'
  const verdicts = await parallel(
    Array.from({ length: verifyVotes }, (_, i) => () => {
      const lens = verifyVotes > 1 ? '\n\nVERIFICATION LENS (focus your refutation here): ' + VERIFY_LENSES[i % VERIFY_LENSES.length] : ''
      const label = 'verify:' + angleId + '-' + f.id + (verifyVotes > 1 ? '-v' + (i + 1) : '')
      return A(base + lens, { label: label, phase: phaseLabel || 'Verify', schema: VERDICT_SCHEMA })
    })
  )
  const valid = verdicts.filter(Boolean)
  if (valid.length === 0) return null
  const refuted = valid.filter((v) => v.vote === 'REFUTED').length
  if (refuted > valid.length / 2) return null // 多數 REFUTED → drop（recall mode；votes=1 時即單票 REFUTED）
  const kept = valid.filter((v) => v.vote !== 'REFUTED')
  // 代表 verdict：保留最高信心票的 reasoning/crossReferences，但 revisedConfidence
  // 取非 REFUTED 票的平均（共識而非最樂觀；votes=1 時平均=自己 → 原值不變）。
  const meanConf = Math.round(kept.reduce((s, v) => s + v.revisedConfidence, 0) / kept.length)
  const rep = kept.slice().sort((a, b) => b.revisedConfidence - a.revisedConfidence)[0]
  return { ...f, angle: angleId, verdict: { ...rep, revisedConfidence: meanConf, votes: { total: valid.length, refuted: refuted } } }
}

phase('Review')

const reviewResults = await pipeline(
  activeAngles,
  async (angle) => {
    const prompt = 'You are a code reviewer at EXTRA-HIGH recall effort — catching real bugs matters more than avoiding false positives. Your angle: ' + angle.name + '.\n\nFOCUS: ' + angle.focus + '\n\nDIFF + FILE LIST:\n' + scopeText + '\n\nINSTRUCTIONS:\n1. Read every in-scope file end-to-end before forming any finding (audit-rigor Principle 1).\n2. Self-check before submitting each finding: "Have I actually read this file:line, or am I guessing?" If guessing, re-read first (Principle 2).\n3. For security-relevant findings, tag STRIDE (S/T/R/I/D/E) and CWE-NNN; for non-security findings use NA.\n4. Provide concrete failure scenarios (specific inputs/state to wrong output/crash), not vague claims.\n5. Use confidence honestly — 50% means "I am not sure". Don\'t pad with low-confidence findings.\n\nReturn UP TO 6 candidate findings via StructuredOutput.'
    return await A(prompt, { label: 'find:' + angle.id + '-' + angle.name, phase: 'Review', schema: FINDINGS_SCHEMA })
  },
  async (findResult, angle) => {
    if (!findResult || !findResult.findings || findResult.findings.length === 0) {
      return []
    }
    // verifyFinding 內含 N 票對抗式驗證；多數 REFUTED 或全空 → 回 null，由 filter 移除。
    const verified = await parallel(findResult.findings.map((f) => () => verifyFinding(f, angle.id, 'Verify')))
    return verified.filter(Boolean)
  }
)

const angleFindings = reviewResults.flat()
log('Phase Review+Verify: ' + angleFindings.length + ' non-REFUTED findings across ' + activeAngles.length + ' angle(s) (' + verifyVotes + ' verifier vote(s) each' + (agentModel ? ', model=' + agentModel : '') + ').')

let sweepVerified = []
if (doSweep) {
  phase('Sweep')

  const knownList = angleFindings.map((f) => '[' + f.severity + '/' + f.verdict.vote + '] ' + f.file + ':' + f.line + ' - ' + f.summary).join('\n')
  const sweepPrompt = 'You are a fresh reviewer doing the FINAL pass. The first ' + activeAngles.length + ' angles produced these non-REFUTED findings:\n\n' + (knownList || '(none)') + '\n\nDIFF + FILE LIST:\n' + scopeText + '\n\nDO NOT re-derive any of the above. Find DIFFERENT defects the first pass missed. Focus on what first passes tend to miss:\n- Moved/extracted code that dropped a guard or invariant anchor\n- Setup/teardown asymmetry in tests (forgotten spy/fake, missing cache clear)\n- Predicate methods with hidden side effects\n- Config defaults flipped\n- Race conditions / lock-scope shrink / read-then-write without lock\n- Tests that pass but do not lock the actual contract (would still pass if guard removed)\n- Symmetry violations: e.g. existing helper has unit tests but new symmetric helper does not\n- Boy-scout opportunities: pre-existing issue this PR makes marginally worse AND fix is <10 LOC\n\nReturn UP TO 6 NEW findings. Empty array if nothing genuinely new.'

  const sweepResult = await A(sweepPrompt, { label: 'sweep-gaps', phase: 'Sweep', schema: FINDINGS_SCHEMA })
  const sweepCandidates = (sweepResult && sweepResult.findings) || []
  for (const f of sweepCandidates) {
    // 與 angle findings 同款 N 票對抗式驗證（phase 標 'Sweep' 以維持進度分組）。
    const v = await verifyFinding(f, 'sweep', 'Sweep')
    if (v) sweepVerified.push(v)
  }
} else {
  log('Sweep skipped (--no-sweep).')
}

const verifiedFindings = [...angleFindings, ...sweepVerified]
log('After sweep: ' + verifiedFindings.length + ' total non-REFUTED findings.')

phase('Triage')

const SEVERITY_POINTS = { Critical: 10, High: 5, Medium: 3, Low: 1 }
const triaged = []

// keepAll 時 triage agent 也不該以 EV/低信心為由 DISMISS（使用者已明確禁用 EV 閘），
// 否則機械閘關了、agent 又把同公式撿回來用，部分抵消 --keep-all 的意圖。
const dismissCriterion = keepAll
  ? '- DISMISS: false positive ONLY on source re-read (do NOT dismiss on EV / low-confidence grounds — --keep-all explicitly disabled the EV gate).'
  : '- DISMISS: false positive on re-read OR EV negative.'

for (const f of verifiedFindings) {
  const points = SEVERITY_POINTS[f.severity] || 1
  const conf = f.verdict.revisedConfidence / 100
  const ev = conf * points - (1 - conf) * 2 * points

  // keepAll（--keep-all）關閉 EV 機械式自動 dismiss：low-EV finding 不在此丟，
  // 改交 triage agent（強模型、重讀原始碼）決定，偏執高風險域用。
  if (ev < 0 && !keepAll) {
    triaged.push({
      ...f,
      triage: {
        decision: 'DISMISS',
        estimatedLoc: 0,
        behaviorChangeRisk: 'none',
        requiresUserDecision: false,
        reasoning: 'Negative EV (' + ev.toFixed(2) + ') at confidence ' + f.verdict.revisedConfidence + '% — below 67% threshold for severity ' + f.severity + '.',
        autoDismissed: true,
      },
      ev,
    })
    continue
  }

  const triagePrompt = 'Triage this verified finding per CLAUDE.md discipline:\n\n- MUST_FIX: bug actively reachable in production with user-facing impact. Code-level fix.\n- BOY_SCOUT_FIX: pre-existing or adjacent issue that meets ALL three CLAUDE.md boy-scout conditions:\n    (a) fix < 50 LOC\n    (b) zero behavior-change risk (interface/observable behavior unchanged; only adds locks/defensive checks/comments/ids/tests)\n    (c) real measurable improvement (closes a CWE, prevents race, locks contract, adds symmetric test coverage)\n  IMPORTANT: do NOT auto-defer just because finding is "pre-existing". CLAUDE.md explicitly forbids the "scope filter degenerating into wholesale rejection of pre-existing issues" anti-pattern.\n- DEFER_OUT_OF_SCOPE: real bug but fix is structurally large (refactor, new dep, ops change, daily heartbeat, monitoring infra) OR requires user product decision.\n' + dismissCriterion + '\n\nFINDING:\n' + JSON.stringify(f, null, 2) + '\n\nCompute estimatedLoc honestly. Set behaviorChangeRisk: "none" only if the fix adds defensive checks/locks without changing observable behavior — otherwise low/medium/high. Set requiresUserDecision=true if fix touches public API, schema migration, or has multiple acceptable approaches.'

  const triageResp = await A(triagePrompt, { label: 'triage:' + f.id, phase: 'Triage', schema: TRIAGE_SCHEMA })

  if (triageResp) {
    triaged.push({ ...f, triage: { ...triageResp, autoDismissed: false }, ev })
  }
}

const mustFix = triaged.filter((f) => f.triage.decision === 'MUST_FIX')
const boyScout = triaged.filter((f) => f.triage.decision === 'BOY_SCOUT_FIX')
const defer = triaged.filter((f) => f.triage.decision === 'DEFER_OUT_OF_SCOPE')
const dismiss = triaged.filter((f) => f.triage.decision === 'DISMISS')

log('Triage: ' + mustFix.length + ' MUST_FIX | ' + boyScout.length + ' BOY_SCOUT_FIX | ' + defer.length + ' DEFER | ' + dismiss.length + ' DISMISS')

phase('Fix')

const applyEligible = [
  ...mustFix.filter((f) => !f.triage.requiresUserDecision && f.triage.estimatedLoc < 100 && f.triage.estimatedLoc <= maxFixLoc),
  ...boyScout.filter((f) => !f.triage.requiresUserDecision && f.triage.estimatedLoc < 50 && f.triage.behaviorChangeRisk === 'none' && f.triage.estimatedLoc <= maxFixLoc),
]

// userReviewRequired 必須是 applyEligible 的「精確補集」，否則某些 triaged finding
// 兩邊都不落而被無聲丟棄。apply 的每個上限（mustFix loc<100、boyScout loc<50、
// 共同 loc<=maxFixLoc）在這裡都要有對應反向項（>=100、>=50、>maxFixLoc）。
// 改任一邊的 LOC/risk 條件，務必同步改另一邊（見 batch proof 的補集完整性驗證）。
const userReviewRequired = [
  ...mustFix.filter((f) => f.triage.requiresUserDecision || f.triage.estimatedLoc >= 100 || f.triage.estimatedLoc > maxFixLoc),
  ...boyScout.filter((f) => f.triage.requiresUserDecision || f.triage.behaviorChangeRisk !== 'none' || f.triage.estimatedLoc >= 50 || f.triage.estimatedLoc > maxFixLoc),
]

log('Fix: ' + applyEligible.length + ' eligible for auto-apply | ' + userReviewRequired.length + ' require user decision')

// 同 file::line 只自動修一次：兩個 angle 抓到同位置時修較高嚴重度者，sibling
// 進 fixSkipped（可見、不靜默丟），避免兩個 fix agent 在同一行打架/重複加測試。
// 刻意只收斂「自動修」——verify/triage/report 仍保留全部 finding，不在此 drop：
// 同一行可能是兩個不同 bug（如 null-deref + SQLi），用 file::line 合併會 drop 真
// finding，違反 asymmetric cost。sibling 標記後交人工判斷是否為相異問題。
const fixByLoc = new Map()
for (const f of applyEligible) {
  const key = f.file + '::' + f.line
  const prev = fixByLoc.get(key)
  if (!prev || (SEVERITY_POINTS[f.severity] || 1) > (SEVERITY_POINTS[prev.severity] || 1)) {
    fixByLoc.set(key, f)
  }
}
const fixTargets = [...fixByLoc.values()]
const siblingCovered = applyEligible.filter((f) => !fixTargets.includes(f))
if (siblingCovered.length > 0) {
  log('Fix dedup: ' + siblingCovered.length + ' finding(s) share a file:line with a higher-severity sibling — not re-fixed, routed to Skipped.')
}

const applied = []
const fixSkipped = []

if (allowAutoFix && applyEligible.length > 0) {
  for (const f of siblingCovered) {
    fixSkipped.push({ ...f, skipReason: 'same file:line (' + f.file + ':' + f.line + ') as a sibling auto-fix — verify manually if this is a distinct issue' })
  }
  for (const f of fixTargets) {
    const fixPrompt = 'Apply the fix for this verified finding. Strict discipline:\n\n1. READ FIRST (Principle 2/3): self-check "have I actually read this, or am I guessing?" If guessing, Read first.\n2. MINIMUM-VIABLE CHANGE: do not refactor surrounding code beyond the fix. CLAUDE.md "Don\'t add features beyond what the task requires".\n3. ADD OR UPDATE A TEST that LOCKS THE CONTRACT — the test must FAIL without your fix. This is non-negotiable per CLAUDE.md "Every change must be programmatically tested".\n4. MATCH EXISTING STYLE — look at sibling files for patterns. Run Pint if PHP, Prettier if JS, etc.\n5. DO NOT commit (workflow handles that separately).\n\nFINDING:\n' + JSON.stringify(f, null, 2) + '\n\nReturn what you did: filesModified (paths), testsAddedOrUpdated (paths), summary (one sentence).\nIf you find the fix is not actually safe or the test would be fragile, set applied=false and explain in skipReason.'
    const result = await A(fixPrompt, { label: 'fix:' + f.id, phase: 'Fix', schema: FIX_SCHEMA })

    if (result && result.applied) {
      applied.push({ ...f, fix: result })
    } else {
      fixSkipped.push({ ...f, skipReason: (result && result.skipReason) || 'fix agent declined or returned empty' })
    }
  }
} else if (!allowAutoFix) {
  log('autoFix=false → skipping Fix phase. applyEligible findings recorded as SKIPPED in report.')
  for (const f of applyEligible) {
    fixSkipped.push({ ...f, skipReason: 'autoFix disabled in args' })
  }
}

phase('Verify Fix')

let testsPass = true
let testsOutput = ''

if (applied.length > 0) {
  const testPrompt = 'Run the test suite to confirm the fixes do not regress anything.\n\n' + testCmdDirective + 'If this is a Laravel/PHP project: run php artisan test 2>&1 | tail -50.\nIf Node/TS: run npm test 2>&1 | tail -50 or detect from package.json.\nIf Python: run pytest 2>&1 | tail -50 or detect from pyproject.toml.\n\nReturn the LAST ~50 lines of output verbatim. Do not summarize — the workflow needs raw output to detect failures.\n\nThen also run the formatter (if applicable):\n- Laravel: vendor/bin/pint --dirty 2>&1 | tail -10\n- JS: npx prettier --write on changed files\n- Python: ruff format on changed files\n\nReturn both outputs concatenated.'
  testsOutput = await A(testPrompt, { label: 'run-tests-and-format', phase: 'Verify Fix' })

  if (hasBaseline) {
    // 比對 baseline：只有「不在 baseline 裡的 failure」才算本次 workflow 造成的 regression。
    // 避免 pre-existing failure（例：先前 PR 引入但未修的 ExampleTest 殘留）被誤判成本次破壞。
    const currentMatches = testsOutput ? testsOutput.match(/FAIL(ED)?\s+[^\n]+/gi) || [] : []
    const currentFailureKeys = [...new Set(currentMatches.map((s) => s.trim()))]
    const newFailures = currentFailureKeys.filter((k) => !baselineFailureKeys.includes(k))

    // 失敗鍵新增 → 一定 regression。鍵不變但「失敗數」上升 → 仍是 regression
    // （cover jest 檔案級 FAIL <file>：同檔多一個 failing test，key 不變但 count +1，
    //  純比鍵會漏抓 → false negative，正是 asymmetric-cost 最該防的方向）。
    const currentFailCount = parseFailCount(testsOutput)
    const countRegressed = baselineFailCount != null && currentFailCount != null && currentFailCount > baselineFailCount

    testsPass = newFailures.length === 0 && !countRegressed
    log('Verify Fix: ' + currentFailureKeys.length + ' failure key(s), ' + newFailures.length + ' NEW key(s)' + (currentFailCount != null ? ', ' + currentFailCount + ' reported failed (baseline ' + (baselineFailCount != null ? baselineFailCount : 'n/a') + ')' : '') + '.')

    if (newFailures.length > 0) {
      log('NEW failure keys (not in baseline):\n  ' + newFailures.slice(0, 10).join('\n  '))
    }
    if (countRegressed) {
      log('Failure COUNT rose ' + baselineFailCount + ' → ' + currentFailCount + ' with no new key — likely same-file regression (jest granularity).')
    }
  } else {
    // Fallback：無 baseline 時用嚴格 regex。注意此模式會把 pre-existing failure
    // 一併視為 regression，導致 false positive。修法：跑前確保 clean baseline。
    testsPass = !!testsOutput &&
      !/Tests:\s+\d+\s+failed/i.test(testsOutput) &&
      !/FAIL(ED)?\s*\n/i.test(testsOutput) &&
      !/^FAILED\s/m.test(testsOutput)

    log('Verify Fix (no baseline): tests ' + (testsPass ? 'PASS' : 'FAIL') + ' after ' + applied.length + ' fixes.')
  }

  if (!testsPass) {
    log('TESTS FAILED — workflow will mark fixes as REQUIRES_USER_REVIEW, no auto-commit.')
  }
}

phase('Report')

const reportPath = 'audits/workflow-audit-' + today + '.md'

const reportPrompt = 'Write a comprehensive audit-rigor report to ' + reportPath + ' using the Write tool.\n\nDATA:\n=== APPLIED FIXES (' + applied.length + ') ===\n' + JSON.stringify(applied.map((f) => ({ id: f.id, file: f.file, line: f.line, severity: f.severity, summary: f.summary, stride: f.stride, cwe: f.cwe, votes: f.verdict.votes, fix: f.fix })), null, 2) + '\n\n=== USER REVIEW REQUIRED (' + userReviewRequired.length + ') ===\n' + JSON.stringify(userReviewRequired.map((f) => ({ id: f.id, file: f.file, line: f.line, severity: f.severity, summary: f.summary, votes: f.verdict.votes, triageReason: f.triage.reasoning, ev: f.ev })), null, 2) + '\n\n=== DEFERRED OUT OF SCOPE (' + defer.length + ') ===\n' + JSON.stringify(defer.map((f) => ({ id: f.id, file: f.file, line: f.line, severity: f.severity, summary: f.summary, deferReason: f.triage.reasoning })), null, 2) + '\n\n=== DISMISSED (' + dismiss.length + ') ===\n' + JSON.stringify(dismiss.map((f) => ({ id: f.id, file: f.file, severity: f.severity, summary: f.summary, originalConfidence: f.confidence, revisedConfidence: f.verdict.revisedConfidence, ev: f.ev, dismissReason: f.triage.reasoning })), null, 2) + '\n\n=== SKIPPED (FIX DECLINED OR NOT ATTEMPTED) (' + fixSkipped.length + ') ===\n' + JSON.stringify(fixSkipped.map((f) => ({ id: f.id, file: f.file, line: f.line, severity: f.severity, summary: f.summary, triageDecision: f.triage.decision, skipReason: f.skipReason })), null, 2) + '\n\n=== TEST OUTPUT TAIL ===\n' + (testsOutput || '(skipped - no fixes applied)').slice(-2500) + '\n\nREPORT STRUCTURE (Markdown):\n# Workflow Audit Report — ' + today + '\n\n## Executive Summary\nOne paragraph: scope, total findings, applied/skipped/deferred/dismissed counts, tests pass/fail, recommendation.\n\n## Scope\nFiles in/out + reason.\n\n## Applied Fixes (' + applied.length + ')\nFor each: file:line, severity, claim, the change made, test added, EV score.\n\n## User Review Required (' + userReviewRequired.length + ')\nFor each: file:line, severity, claim, why human decision needed.\n\n## Deferred Out of Scope (' + defer.length + ')\nFor each: file:line, severity, claim, structural reason fix does not belong in this PR.\n\n## Dismissed (' + dismiss.length + ')\nFor each: file:line, original vs revised confidence, steel-manning rationale.\n\n## Skipped (' + fixSkipped.length + ')\nFor each: file:line, triage decision, why the fix was declined or not attempted (agent judged it unsafe/fragile, or autoFix disabled). These are NOT resolved — surface them so they are not silently lost.\n\n## Test Verification\n' + (applied.length > 0 ? 'Test output tail with PASS/FAIL.' : 'Skipped — no fixes applied.') + '\n\n## Recommendation\n- READY_FOR_COMMIT: tests pass, no MUST_FIX requiring review.\n- REQUIRES_USER_REVIEW: list specific items.\n- REQUIRES_FOLLOW_UP: defer items that should become future PRs.\n\nSave to ' + reportPath + ' and confirm path. Return the path.'

await A(reportPrompt, { label: 'write-report', phase: 'Report' })

// fixSkipped 非空代表有「已驗證但未解決」的 finding（agent 拒修，或 dry-run 未修），
// 必須計入：否則 dry-run（applied=0, userReviewRequired=0）會誤報 CLEAN，掩蓋真 finding。
const status =
  applied.length === 0 && userReviewRequired.length === 0 && fixSkipped.length === 0
    ? 'CLEAN'
    : !testsPass && applied.length > 0
      ? 'TESTS_FAILED'
      : userReviewRequired.length > 0 || fixSkipped.length > 0
        ? 'REQUIRES_USER_REVIEW'
        : 'READY_FOR_COMMIT'

return {
  status,
  reportPath,
  testsPass,
  counts: {
    totalReviewed: verifiedFindings.length,
    applied: applied.length,
    skipped: fixSkipped.length,
    userReviewRequired: userReviewRequired.length,
    deferred: defer.length,
    dismissed: dismiss.length,
  },
  applied: applied.map((f) => ({
    id: f.id,
    file: f.file,
    summary: f.summary,
    votes: f.verdict.votes,
    fixSummary: f.fix.summary,
    filesModified: f.fix.filesModified,
    testsAdded: f.fix.testsAddedOrUpdated || [],
  })),
  userReviewRequired: userReviewRequired.map((f) => ({
    id: f.id,
    file: f.file,
    severity: f.severity,
    summary: f.summary,
    votes: f.verdict.votes,
    reason: f.triage.reasoning,
  })),
  deferred: defer.map((f) => ({
    id: f.id,
    file: f.file,
    severity: f.severity,
    summary: f.summary,
    reason: f.triage.reasoning,
  })),
  skipped: fixSkipped.map((f) => ({
    id: f.id,
    file: f.file,
    severity: f.severity,
    summary: f.summary,
    skipReason: f.skipReason,
  })),
}

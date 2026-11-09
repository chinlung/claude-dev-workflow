#!/usr/bin/env node
// pr-closeout — the facts a PR closeout needs, read from GitHub (and the local clone) instead of
// typed by hand, with a verdict a gate can act on.
//
//   ready  <owner/repo> <pr> [--expect-head <sha>] [--repo-dir <path>] [--fixture <dir>]
//          [--accept-unreviewed <path>=<reason>]...
//   landed <owner/repo> <pr> --expect-head <sha> --repo-dir <path> [--branch <name>] [--fixture <dir>]
//
// stdout is one JSON object; the exit code is the verdict:
//   0 ready · 2 conflict · 3 unresolved review threads · 4 checks failed · 5 pending
//   6 merge gate (field `gate` says which) · 7 query failed, unknown value or usage error
// Every check runs; `hits[]` lists every condition met and the exit is the most urgent of them.
// Fail-closed: a value this script does not know, a missing field or a failed query is never ready.
//
// Queries: `gh api` first; when it fails, the token from `gh auth token` is handed to curl on
// stdin (`-H @-`), so it never appears in argv, output or a file. --fixture <dir> reads recorded
// answers instead (graphql.json, pulls-comments.json, pulls-reviews.json, issues-comments.json,
// compare.json, prev-pulls.json, prev-commit.json) — the tests use it; nothing else should.
// Design: docs/pr-closeout-skill-design-2026-11-09.md. Tests: tests/pr-closeout.test.sh
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const USAGE = `Usage:
  pr-closeout.mjs ready  <owner/repo> <pr> [--expect-head <sha>] [--repo-dir <path>] [--fixture <dir>] [--accept-unreviewed <path>=<reason>]...
  pr-closeout.mjs landed <owner/repo> <pr> --expect-head <sha> --repo-dir <path> [--branch <name>] [--fixture <dir>]`;

export class QueryError extends Error {}
class UsageError extends Error {}

const PAGE = 100;
const GQL = `query($owner:String!,$name:String!,$n:Int!){repository(owner:$owner,name:$name){pullRequest(number:$n){
state isDraft mergeable mergeStateStatus reviewDecision headRefOid headRefName baseRefName
reviewThreads(first:${PAGE}){pageInfo{hasNextPage} nodes{isResolved isOutdated path line comments(first:1){nodes{author{login}}}}}
commits(last:1){nodes{commit{oid statusCheckRollup{state contexts(first:${PAGE}){pageInfo{hasNextPage} nodes{__typename
... on CheckRun{name status conclusion startedAt completedAt} ... on StatusContext{context state}}}}}}}}}}`;

// ── query layer ──────────────────────────────────────────────────────────────────────────────────
function run(cmd, args, input) {
  const r = spawnSync(cmd, args, { input, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  return { ok: r.status === 0 && !r.error, stdout: r.stdout || '' };
}
const parse = (text, what) => {
  try { return JSON.parse(text); } catch { throw new QueryError(`${what}: not JSON`); }
};

let cachedToken;
function token() {
  if (cachedToken === undefined) {
    const r = run('gh', ['auth', 'token']);
    cachedToken = r.ok ? r.stdout.trim() : '';
  }
  if (!cachedToken) throw new QueryError('no GitHub token (gh auth token failed)');
  return cachedToken;
}
// curl with the token on stdin (-H @-): never in argv, so `ps` and logs do not see it
function curl(url, body) {
  const args = ['-sS', '-f', '-H', '@-', '-H', 'Accept: application/vnd.github+json'];
  if (body !== undefined) args.push('-X', 'POST', '-H', 'Content-Type: application/json', '--data-binary', body);
  args.push(url);
  return run('curl', args, `Authorization: bearer ${token()}\n`);
}

function graphql(owner, repo, pr) {
  let r = run('gh', ['api', 'graphql', '-f', `query=${GQL}`, '-F', `owner=${owner}`, '-F', `name=${repo}`, '-F', `n=${pr}`]);
  if (!r.ok) r = curl('https://api.github.com/graphql', JSON.stringify({ query: GQL, variables: { owner, name: repo, n: pr } }));
  if (!r.ok) throw new QueryError('GraphQL query failed (gh and curl)');
  return parse(r.stdout, 'GraphQL answer');
}
function rest(apiPath) {
  let r = run('gh', ['api', apiPath]);
  if (!r.ok) r = curl(`https://api.github.com/${apiPath}`);
  if (!r.ok) throw new QueryError(`REST ${apiPath.split('?')[0]} failed (gh and curl)`);
  return parse(r.stdout, `REST ${apiPath.split('?')[0]}`);
}
function fullPage(list, what) {
  if (!Array.isArray(list)) throw new QueryError(`${what}: not a list`);
  if (list.length >= PAGE) throw new QueryError(`${what}: ${PAGE} or more entries, not read in full`);
  return list;
}

const FIXTURE_FILES = {
  graphql: 'graphql.json', pullsComments: 'pulls-comments.json', pullsReviews: 'pulls-reviews.json',
  issuesComments: 'issues-comments.json', compare: 'compare.json', prevPulls: 'prev-pulls.json', prevCommit: 'prev-commit.json',
};
function readFixture(dir) {
  const raw = {};
  for (const [key, file] of Object.entries(FIXTURE_FILES)) {
    const f = path.join(dir, file);
    if (!fs.existsSync(f)) {
      if (key === 'prevCommit') { raw[key] = null; continue; }   // no merged PR before this one
      throw new QueryError(`fixture ${file} missing`);
    }
    raw[key] = parse(fs.readFileSync(f, 'utf8'), `fixture ${file}`);
  }
  return raw;
}

// The PR object of a GraphQL answer, or a QueryError naming what is wrong with the answer.
export function prOf(graphqlAnswer) {
  const p = graphqlAnswer && graphqlAnswer.data && graphqlAnswer.data.repository && graphqlAnswer.data.repository.pullRequest;
  if (!p || typeof p !== 'object') {
    const err = graphqlAnswer && Array.isArray(graphqlAnswer.errors) && graphqlAnswer.errors[0] && graphqlAnswer.errors[0].message;
    throw new QueryError(`GraphQL answer has no pullRequest${err ? `: ${err}` : ''}`);
  }
  return p;
}

export function fetchAll({ owner, repo, pr, fixture }) {
  if (fixture) return readFixture(fixture);
  const raw = { graphql: graphql(owner, repo, pr) };
  const p = prOf(raw.graphql);
  const base = `repos/${owner}/${repo}`;
  raw.pullsComments = fullPage(rest(`${base}/pulls/${pr}/comments?per_page=${PAGE}`), 'review comments');
  raw.pullsReviews = fullPage(rest(`${base}/pulls/${pr}/reviews?per_page=${PAGE}`), 'reviews');
  raw.issuesComments = fullPage(rest(`${base}/issues/${pr}/comments?per_page=${PAGE}`), 'issue comments');
  raw.compare = rest(`${base}/compare/${encodeURIComponent(p.baseRefName)}...${p.headRefOid}`);
  raw.prevPulls = rest(`${base}/pulls?state=closed&sort=updated&direction=desc&per_page=20`);
  const prev = Array.isArray(raw.prevPulls) ? raw.prevPulls.find((x) => x && x.merged_at && x.number !== Number(pr)) : null;
  raw.prevCommit = prev ? rest(`${base}/commits/${prev.merge_commit_sha}`) : null;
  return raw;
}

// ── local clone: review coverage ─────────────────────────────────────────────────────────────────
function git(dir, args) {
  const r = spawnSync('git', ['-C', dir, ...args], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, env: { ...process.env, GIT_NO_REPLACE_OBJECTS: '1' } });
  return { ok: r.status === 0 && !r.error, out: r.stdout || '' };
}
const DOC_PATH = /\.(md|mdx|txt|rst|adoc)$|^docs?\//;
// review-branch records a file as <hash>, <hash>+x (executable) or link:<hash> (symlink)
function blobKey(mode, hash) {
  if (mode === '100755') return `${hash}+x`;
  if (mode === '120000') return `link:${hash}`;
  return hash;
}

// Did the last review-branch round see exactly the bytes this PR merges? Compared file by file,
// not by commit: review-branch reviews the working tree, so its recorded head need not hold what
// it read. status: covered | unreviewed | unknown (no record, another branch, head not here…).
export function coverage(repoDir, { headRefName, headOid, baseRef, accept = [] }) {
  const unknown = (reason) => ({ status: 'unknown', reason, unreviewed: [], docsOnly: [], accepted: [] });
  if (!repoDir) return unknown('no --repo-dir');
  const gd = git(repoDir, ['rev-parse', '--absolute-git-dir']);
  if (!gd.ok) return unknown(`${repoDir} is not a git repository`);
  if (!headOid || !git(repoDir, ['cat-file', '-e', `${headOid}^{commit}`]).ok) return unknown('the PR head is not in the local clone (fetch it)');
  const stateFile = path.join(gd.out.trim(), 'review-branch-last.json');
  if (!fs.existsSync(stateFile)) return unknown('no review-branch record');
  let state;
  try { state = JSON.parse(fs.readFileSync(stateFile, 'utf8')); } catch { return unknown('review-branch record is not JSON'); }
  if (!state || state.branch !== headRefName) return unknown(`review-branch record is for ${state && state.branch}, not ${headRefName}`);
  const reviewed = new Map((Array.isArray(state.scopedFiles) ? state.scopedFiles : [])
    .filter((f) => f && f.status === 'reviewed' && typeof f.blob === 'string').map((f) => [f.file, f.blob]));
  let mb = git(repoDir, ['merge-base', `origin/${baseRef}`, headOid]);
  if (!mb.ok) mb = git(repoDir, ['merge-base', baseRef, headOid]);
  if (!mb.ok) return unknown(`no merge base with ${baseRef}`);
  const changed = git(repoDir, ['diff', '--name-only', '-z', '--diff-filter=d', mb.out.trim(), headOid]);
  if (!changed.ok) return unknown('git diff failed');
  const out = { status: 'covered', unreviewed: [], docsOnly: [], accepted: [] };
  for (const file of changed.out.split('\0').filter(Boolean)) {
    const lt = git(repoDir, ['ls-tree', '-z', headOid, '--', file]);
    const m = /^(\d+) \w+ ([0-9a-f]+)\t/.exec(lt.out);
    if (m && reviewed.get(file) === blobKey(m[1], m[2])) continue;
    const ok = accept.find((a) => a.path === file);
    if (DOC_PATH.test(file)) out.docsOnly.push(file);
    else if (ok) out.accepted.push({ path: file, reason: ok.reason });
    else out.unreviewed.push(file);
  }
  if (out.unreviewed.length) out.status = 'unreviewed';
  return out;
}

// ── local clone: openspec changes the PR leaves unarchived (W3-2; a warning, never the exit) ──────
function reconcileCheckPath() {
  if (process.env.RECONCILE_CHECK) return process.env.RECONCILE_CHECK;
  const cache = path.join(os.homedir(), '.claude', 'plugins', 'cache');
  const ls = (d) => { try { return fs.readdirSync(d); } catch { return []; } };
  const found = [];
  for (const market of ls(cache)) {
    const root = path.join(cache, market, 'openspec-superpowers-workflow');
    for (const ver of ls(root)) {
      const f = path.join(root, ver, 'skills', 'openspec-superpowers-workflow', 'validators', 'reconcile-check.cjs');
      if (fs.existsSync(f)) found.push({ ver, f });
    }
  }
  const num = (v) => v.split('.').map((x) => Number(x) || 0);
  found.sort((a, b) => { const [x, y] = [num(a.ver), num(b.ver)]; return x[0] - y[0] || x[1] - y[1] || x[2] - y[2]; });
  return found.length ? found[found.length - 1].f : null;
}

export function openspecChanges(repoDir, { headOid, baseRef }) {
  if (!repoDir || !headOid || !git(repoDir, ['cat-file', '-e', `${headOid}^{commit}`]).ok) return null;
  const present = git(repoDir, ['ls-tree', '-d', headOid, '--', 'openspec']).out.trim() !== '';
  if (!present) return { present: false, unarchivedChanges: [] };
  let mb = git(repoDir, ['merge-base', `origin/${baseRef}`, headOid]);
  if (!mb.ok) mb = git(repoDir, ['merge-base', baseRef, headOid]);
  const names = new Set();
  if (mb.ok) {
    for (const f of git(repoDir, ['diff', '--name-only', '-z', mb.out.trim(), headOid]).out.split('\0')) {
      const m = /^openspec\/changes\/([^/]+)\//.exec(f);
      if (m && m[1] !== 'archive') names.add(m[1]);
    }
  }
  const script = reconcileCheckPath();
  const unarchivedChanges = [...names].sort()
    .filter((n) => git(repoDir, ['ls-tree', '-d', headOid, '--', `openspec/changes/${n}`]).out.trim() !== '')
    .map((name) => {
      let verify = 'unavailable';
      if (script && fs.existsSync(script)) {
        const r = spawnSync(process.execPath, [script, 'verify', path.join(repoDir, 'openspec', 'changes', name)], { encoding: 'utf8' });
        if (r.status === 0 || r.status === 3) verify = (r.stdout || '').trim().split('\n')[0] || 'unavailable';
      }
      return { name, verify };
    });
  return { present: true, unarchivedChanges };
}

// ── verdict ──────────────────────────────────────────────────────────────────────────────────────
const KNOWN = {
  state: new Set(['OPEN', 'CLOSED', 'MERGED']),
  mergeable: new Set(['MERGEABLE', 'CONFLICTING', 'UNKNOWN']),
  mergeStateStatus: new Set(['CLEAN', 'HAS_HOOKS', 'UNSTABLE', 'BLOCKED', 'BEHIND', 'DIRTY', 'UNKNOWN']),
  reviewDecision: new Set([null, 'APPROVED', 'CHANGES_REQUESTED', 'REVIEW_REQUIRED']),
  rollup: new Set(['SUCCESS', 'FAILURE', 'ERROR', 'PENDING', 'EXPECTED']),
};
const OK_CONCLUSIONS = new Set(['SUCCESS', 'NEUTRAL', 'SKIPPED']);
const EXIT_OF = { 'query-failed': 7, 'merge-gate': 6, conflict: 2, 'unresolved-threads': 3, 'checks-failed': 4, pending: 5 };
// Order of urgency: what waiting cannot fix comes first. The two "soft" gates (an unseen block,
// a base the branch must catch up with) rank below pending: a running check may be what blocks.
const SOFT_GATES = new Set(['blocked-unseen', 'behind']);
const RANK = { 'query-failed': 0, 'merge-gate': 1, conflict: 2, 'unresolved-threads': 3, 'checks-failed': 4, pending: 5 };
const rankOf = (h) => (h.code === 'merge-gate' && SOFT_GATES.has(h.gate) ? 6 : RANK[h.code]);

// A check context → 'ok' | 'failed' | 'pending'. Anything not known to be fine is failed.
function contextState(c) {
  if (c && c.__typename === 'CheckRun') {
    if (c.status !== 'COMPLETED') return 'pending';
    return OK_CONCLUSIONS.has(c.conclusion) ? 'ok' : 'failed';
  }
  if (c && c.__typename === 'StatusContext') {
    if (c.state === 'SUCCESS') return 'ok';
    if (c.state === 'PENDING' || c.state === 'EXPECTED') return 'pending';
    return 'failed';
  }
  return 'failed';
}

// The per-user list of checks that must appear on a repo's PRs (D6). Personal data, so it lives
// outside this plugin: $PR_CLOSEOUT_CONFIG, else ~/.claude/pr-closeout/required-checks.json.
// Shape: {"<owner>/<repo>": {"required": ["<check>"], "minSeconds": {"<check>": <n>}}}.
// No file: nothing is required. An unreadable or misshapen file: { error } (a query failure).
export function loadConfig() {
  const file = process.env.PR_CLOSEOUT_CONFIG || path.join(os.homedir(), '.claude', 'pr-closeout', 'required-checks.json');
  if (!fs.existsSync(file)) return { file, repos: {} };
  let c;
  try { c = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return { file, error: `config ${file} is not JSON` }; }
  const bad = (why) => ({ file, error: `config ${file}: ${why}` });
  if (!c || typeof c !== 'object' || Array.isArray(c)) return bad('not an object');
  for (const [slug, e] of Object.entries(c)) {
    if (!e || typeof e !== 'object') return bad(`${slug} is not an object`);
    if (e.required !== undefined && !(Array.isArray(e.required) && e.required.every((x) => typeof x === 'string'))) return bad(`${slug}.required is not a list of names`);
    if (e.minSeconds !== undefined && !(e.minSeconds && typeof e.minSeconds === 'object' && Object.values(e.minSeconds).every((n) => typeof n === 'number' && n >= 0))) return bad(`${slug}.minSeconds is not a map of numbers`);
  }
  return { file, repos: c };
}

const seconds = (c) => (Date.parse(c.completedAt) - Date.parse(c.startedAt)) / 1000;

// Facts that inform the model's judgment and never change the exit: how earlier PRs were merged,
// how far the base moved, who commented where.
function extras(raw, pr) {
  const prev = Array.isArray(raw.prevPulls) ? raw.prevPulls.find((x) => x && x.merged_at && x.number !== pr) : null;
  const parents = raw.prevCommit && Array.isArray(raw.prevCommit.parents) ? raw.prevCommit.parents.length : null;
  const method = !prev || parents === null ? 'unknown' : parents === 1 ? 'squash' : parents === 2 ? 'merge' : 'unknown';
  const list = (x) => (Array.isArray(x) ? x : []);
  const authors = new Set();
  for (const k of ['pullsComments', 'pullsReviews', 'issuesComments']) {
    for (const c of list(raw[k])) if (c && c.user && c.user.login) authors.add(c.user.login);
  }
  return {
    precedent: { pr: prev ? prev.number : null, parents: prev ? parents : null, method },
    baseBehind: raw.compare && Number.isInteger(raw.compare.behind_by) ? raw.compare.behind_by : null,
    comments: {
      pullsComments: list(raw.pullsComments).length, pullsReviews: list(raw.pullsReviews).length,
      issuesComments: list(raw.issuesComments).length, authors: [...authors].sort(),
    },
  };
}

export function assess(raw, { expectHead, owner, repo, pr, config, cover } = {}) {
  const p = prOf(raw.graphql);
  const hits = [];
  if (cover && cover.status === 'unreviewed') {
    hits.push({ code: 'merge-gate', gate: 'unreviewed', detail: `not covered by the last review: ${cover.unreviewed.join(', ')}` });
  }
  if (config && config.error) hits.push({ code: 'query-failed', detail: config.error });
  const policy = (config && config.repos && config.repos[`${owner}/${repo}`]) || {};
  const unknown = (field, value) => hits.push({ code: 'query-failed', detail: `unknown ${field}: ${JSON.stringify(value)}` });
  const known = (field, value) => (KNOWN[field].has(value) ? true : (unknown(field, value), false));
  const gate = (g, detail) => hits.push({ code: 'merge-gate', gate: g, detail });

  if (known('state', p.state) && p.state !== 'OPEN') gate('not-open', `the PR is ${p.state}`);
  if (typeof p.isDraft !== 'boolean') unknown('isDraft', p.isDraft);
  else if (p.isDraft) gate('draft', 'the PR is a draft');
  if (known('reviewDecision', p.reviewDecision === undefined ? '(missing)' : p.reviewDecision) && p.reviewDecision === 'CHANGES_REQUESTED') {
    gate('changes-requested', 'a reviewer requested changes');
  }
  if (typeof p.headRefOid !== 'string') unknown('headRefOid', p.headRefOid);
  else if (expectHead && p.headRefOid !== expectHead) gate('head-mismatch', `head is ${p.headRefOid}, expected ${expectHead}`);

  const mergeableKnown = known('mergeable', p.mergeable);
  const stateKnown = known('mergeStateStatus', p.mergeStateStatus);
  if ((mergeableKnown && p.mergeable === 'CONFLICTING') || (stateKnown && p.mergeStateStatus === 'DIRTY')) {
    hits.push({ code: 'conflict', detail: 'the branch conflicts with its base' });
  }

  const rt = p.reviewThreads;
  let threads = [];
  if (!rt || !Array.isArray(rt.nodes) || !rt.pageInfo) unknown('reviewThreads', rt);
  else {
    if (rt.pageInfo.hasNextPage) hits.push({ code: 'query-failed', detail: `more than ${PAGE} review threads` });
    // outdated is not resolved: it only means the line moved
    threads = rt.nodes.filter((t) => !t || t.isResolved !== true).map((t) => ({
      path: t && t.path, line: t && t.line, outdated: !!(t && t.isOutdated),
      author: t && t.comments && t.comments.nodes && t.comments.nodes[0] && t.comments.nodes[0].author && t.comments.nodes[0].author.login,
    }));
    if (threads.length) hits.push({ code: 'unresolved-threads', detail: `${threads.length} unresolved review thread(s)` });
  }

  const commit = p.commits && p.commits.nodes && p.commits.nodes[0] && p.commits.nodes[0].commit;
  if (!commit) unknown('commits', p.commits);
  // null means the head has no checks at all; a missing field or a non-object is an answer this
  // script does not understand (fail-closed), not "no checks"
  let rollup = null;
  if (commit) {
    const r = commit.statusCheckRollup;   // undefined (missing) is neither null nor an object
    if (r !== null && typeof r !== 'object') unknown('statusCheckRollup', r === undefined ? '(missing)' : r);
    else rollup = r;
  }
  let checks = [];
  if (rollup) {
    const cx = rollup.contexts;
    if (!cx || !Array.isArray(cx.nodes) || !cx.pageInfo) unknown('statusCheckRollup.contexts', cx);
    else {
      if (cx.pageInfo.hasNextPage) hits.push({ code: 'query-failed', detail: `more than ${PAGE} check contexts` });
      checks = cx.nodes.map((c) => ({
        name: c && (c.name || c.context), state: contextState(c),
        conclusion: c && (c.conclusion || c.state || null), startedAt: c && c.startedAt, completedAt: c && c.completedAt,
      }));
    }
  }
  // a required check that never ran (paths-ignore, a skipped workflow) is a failed check, not a green one
  const missing = (policy.required || []).filter((name) => !checks.some((c) => c.name === name));
  if (missing.length) hits.push({ code: 'checks-failed', detail: missing.map((n) => `required check missing: ${n}`).join('; ') });
  const suspectedSkip = Object.entries(policy.minSeconds || {})
    .filter(([name, min]) => checks.some((c) => c.name === name && c.state === 'ok' && c.startedAt && c.completedAt && seconds(c) < min))
    .map(([name]) => name);
  if (rollup) {
    const failedChecks = checks.filter((c) => c.state === 'failed');
    const pendingChecks = checks.filter((c) => c.state === 'pending');
    const rollupKnown = known('rollup', rollup.state);
    const rollupFailed = rollupKnown && (rollup.state === 'FAILURE' || rollup.state === 'ERROR');
    if (failedChecks.length || rollupFailed) {
      hits.push({ code: 'checks-failed', detail: failedChecks.length ? `failed: ${failedChecks.map((c) => c.name).join(', ')}` : `the head's rollup is ${rollup.state}` });
    }
    if (pendingChecks.length || (rollupKnown && (rollup.state === 'PENDING' || rollup.state === 'EXPECTED'))) {
      hits.push({ code: 'pending', detail: pendingChecks.length ? `running: ${pendingChecks.map((c) => c.name).join(', ')}` : `the head's rollup is ${rollup.state}` });
    }
  }

  if ((mergeableKnown && p.mergeable === 'UNKNOWN') || (stateKnown && p.mergeStateStatus === 'UNKNOWN')) {
    hits.push({ code: 'pending', detail: 'GitHub is still computing mergeability' });
  }
  // BLOCKED with failing checks is already a checks-failed hit; BLOCKED with nothing visible wrong
  // is the gate this script cannot see (a required review, a ruleset) — never read that as green.
  if (stateKnown && p.mergeStateStatus === 'BLOCKED' && !hits.some((h) => h.code === 'checks-failed')) {
    gate('blocked-unseen', `GitHub reports BLOCKED (review decision ${p.reviewDecision ?? 'none'})`);
  }
  if (stateKnown && p.mergeStateStatus === 'BEHIND') gate('behind', 'the base requires the branch to be up to date');

  hits.sort((a, b) => rankOf(a) - rankOf(b));
  const top = hits[0];
  return {
    exit: top ? EXIT_OF[top.code] : 0,
    gate: top && top.code === 'merge-gate' ? top.gate : null,
    hits,
    head: p.headRefOid ?? null,
    headRefName: p.headRefName ?? null,
    baseRefName: p.baseRefName ?? null,
    threads,
    checks,
    suspectedSkip,
    ...extras(raw, pr),
    coverage: cover || null,
  };
}

// ── landed: was it merged, as reviewed, onto the base, and is the branch gone? ───────────────────
// merged_at proves the merge; the merge commit (never the branch tip: a squash leaves the tip off the
// base) proves where it landed. Gates: not-merged, head-mismatch, not-on-base, branch-remains.
export function landed(o) {
  if (!o.expectHead || !o.repoDir) throw new UsageError('landed needs --expect-head and --repo-dir');
  const base = `repos/${o.owner}/${o.repo}`;
  const read = (file, apiPath) => (o.fixture
    ? (fs.existsSync(path.join(o.fixture, file)) ? parse(fs.readFileSync(path.join(o.fixture, file), 'utf8'), `fixture ${file}`) : (() => { throw new QueryError(`fixture ${file} missing`); })())
    : rest(apiPath));
  const pull = read('pull.json', `${base}/pulls/${o.pr}`);
  if (!pull || typeof pull !== 'object' || !pull.base || !pull.head) throw new QueryError('PR answer is missing head or base');
  const hits = [];
  const gate = (g, detail) => hits.push({ code: 'merge-gate', gate: g, detail });
  if (!pull.merged_at) gate('not-merged', 'merged_at is empty');
  const headMatches = pull.head.sha === o.expectHead;
  if (!headMatches) gate('head-mismatch', `merged head is ${pull.head.sha}, expected ${o.expectHead}`);

  const baseRef = pull.base.ref;
  if (!git(o.repoDir, ['fetch', '-q', 'origin', baseRef]).ok) throw new QueryError(`git fetch origin ${baseRef} failed`);
  const mc = pull.merge_commit_sha;
  // merge_commit_sha before merged_at is GitHub's trial merge: only judged once merged
  const onBase = !!(pull.merged_at && mc && git(o.repoDir, ['merge-base', '--is-ancestor', mc, `origin/${baseRef}`]).ok);
  if (pull.merged_at && !onBase) gate('not-on-base', `merge commit ${mc} is not on origin/${baseRef}`);

  let branch = null;
  if (o.branch) {
    const open = read('open-pulls.json', `${base}/pulls?head=${o.owner}:${encodeURIComponent(o.branch)}&state=open&per_page=${PAGE}`);
    if (!Array.isArray(open)) throw new QueryError('open PR list is not a list');
    const ls = git(o.repoDir, ['ls-remote', '--heads', 'origin', `refs/heads/${o.branch}`]);
    if (!ls.ok) throw new QueryError('git ls-remote origin failed');
    const local = git(o.repoDir, ['branch', '--list', o.branch]).out.trim() !== '';
    branch = { name: o.branch, openPulls: open.length, remote: ls.out.trim() !== '', local };
    const left = [open.length && `${open.length} open PR`, branch.remote && 'remote branch', local && 'local branch'].filter(Boolean);
    if (left.length) gate('branch-remains', `still there: ${left.join(', ')}`);
  }
  const top = hits[0];
  return {
    exit: top ? 6 : 0, gate: top ? top.gate : null, hits,
    mergedAt: pull.merged_at || null, mergeCommit: mc || null, headMatches, onBase, branch,
  };
}

// ── CLI ──────────────────────────────────────────────────────────────────────────────────────────
function parseArgs(argv) {
  const [cmd, slug, prArg, ...rest] = argv;
  if (!['ready', 'landed'].includes(cmd)) throw new UsageError('unknown subcommand');
  const m = /^([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)$/.exec(slug || '');
  if (!m) throw new UsageError('<owner/repo> expected');
  if (!/^[1-9][0-9]*$/.test(prArg || '')) throw new UsageError('<pr> must be a number');
  const o = { cmd, owner: m[1], repo: m[2], pr: Number(prArg), accept: [] };
  for (let i = 0; i < rest.length; i++) {
    const flag = rest[i];
    const val = rest[i + 1];
    if (!['--expect-head', '--repo-dir', '--fixture', '--branch', '--accept-unreviewed'].includes(flag)) throw new UsageError(`unknown option ${flag}`);
    if (val === undefined) throw new UsageError(`${flag} needs a value`);
    i++;
    if (flag === '--expect-head') {
      if (!/^[0-9a-f]{40}([0-9a-f]{24})?$/.test(val)) throw new UsageError('--expect-head must be a full commit sha');
      o.expectHead = val;
    } else if (flag === '--repo-dir') o.repoDir = val;
    else if (flag === '--fixture') o.fixture = val;
    else if (flag === '--branch') o.branch = val;
    else {
      const eq = val.indexOf('=');
      const p = eq < 0 ? '' : val.slice(0, eq);
      const reason = eq < 0 ? '' : val.slice(eq + 1).trim();
      if (!p || !reason) throw new UsageError('--accept-unreviewed needs <path>=<reason>, and the reason may not be empty');
      o.accept.push({ path: p, reason });
    }
  }
  return o;
}

function emit(obj) {
  process.stdout.write(`${JSON.stringify(obj, null, 2)}\n`);
  return obj.exit;
}

export function main(argv) {
  let o;
  try { o = parseArgs(argv); } catch (e) {
    process.stderr.write(`${e.message}\n${USAGE}\n`);
    return emit({ exit: 7, gate: null, hits: [{ code: 'query-failed', detail: `usage: ${e.message}` }] });
  }
  const head = { pr: { owner: o.owner, repo: o.repo, number: o.pr } };
  try {
    if (o.cmd === 'landed') return emit({ ...head, ...landed(o) });
    const raw = fetchAll(o);
    const p = prOf(raw.graphql);
    const cover = o.repoDir
      ? coverage(o.repoDir, { headRefName: p.headRefName, headOid: p.headRefOid, baseRef: p.baseRefName, accept: o.accept })
      : null;
    const spec = o.repoDir ? openspecChanges(o.repoDir, { headOid: p.headRefOid, baseRef: p.baseRefName }) : null;
    return emit({ ...head, ...assess(raw, { ...o, config: loadConfig(), cover }), openspec: spec });
  } catch (e) {
    if (e instanceof UsageError) {
      process.stderr.write(`${e.message}\n${USAGE}\n`);
      return emit({ ...head, exit: 7, gate: null, hits: [{ code: 'query-failed', detail: `usage: ${e.message}` }] });
    }
    if (!(e instanceof QueryError)) throw e;
    return emit({ ...head, exit: 7, gate: null, hits: [{ code: 'query-failed', detail: e.message }] });
  }
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1] && fs.realpathSync(process.argv[1]) === new URL(import.meta.url).pathname) {
  process.exitCode = main(process.argv.slice(2));
}

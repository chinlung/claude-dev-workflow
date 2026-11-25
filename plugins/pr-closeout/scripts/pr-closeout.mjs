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
import crypto from 'node:crypto';
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
state isDraft isCrossRepository mergeable mergeStateStatus reviewDecision headRefOid headRefName baseRefName
reviewThreads(first:${PAGE}){pageInfo{hasNextPage} nodes{isResolved isOutdated path line comments(first:1){nodes{author{login}}}}}
commits(last:1){nodes{commit{oid statusCheckRollup{state contexts(first:${PAGE}){pageInfo{hasNextPage} nodes{__typename
... on CheckRun{name status conclusion startedAt completedAt detailsUrl} ... on StatusContext{context state}}}}}}}}}}`;

// ── query layer ──────────────────────────────────────────────────────────────────────────────────
// One deadline for every query of a run (PR_CLOSEOUT_DEADLINE_MS, default 20 s), under the merge
// gate hook's 30 s timeout: a slow GitHub ends in exit 7 here, never in a hook the harness gave up on.
const DEADLINE = Date.now() + (Number(process.env.PR_CLOSEOUT_DEADLINE_MS) || 20000);
function run(cmd, args, input) {
  const left = DEADLINE - Date.now();
  if (left <= 0) throw new QueryError('deadline passed before the queries finished');
  const r = spawnSync(cmd, args, { input, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, timeout: left, killSignal: 'SIGKILL' });
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
// Every page of a list endpoint: page n+1 is asked for only while page n came back full. One loop
// for the network and the fixtures (pageOf differs), so the tests run the code a real PR runs.
const MAX_PAGES = 10;
function allPages(pageOf, what) {
  const all = [];
  for (let n = 1; n <= MAX_PAGES; n++) {
    const list = pageOf(n);
    if (!Array.isArray(list)) throw new QueryError(`${what}: not a list`);
    all.push(...list);
    if (list.length < PAGE) return all;
  }
  throw new QueryError(`${what}: more than ${MAX_PAGES * PAGE} entries, not read in full`);
}

const FIXTURE_FILES = {
  graphql: 'graphql.json', pullsComments: 'pulls-comments.json', pullsReviews: 'pulls-reviews.json',
  issuesComments: 'issues-comments.json', compare: 'compare.json', prevPulls: 'prev-pulls.json', prevCommit: 'prev-commit.json',
};
const PAGED = new Set(['pullsComments', 'pullsReviews', 'issuesComments']);
function readFixture(dir) {
  const raw = {};
  for (const [key, file] of Object.entries(FIXTURE_FILES)) {
    const f = path.join(dir, file);
    if (!fs.existsSync(f)) {
      if (key === 'prevCommit') { raw[key] = null; continue; }   // no merged PR before this one
      throw new QueryError(`fixture ${file} missing`);
    }
    if (PAGED.has(key)) {
      // <name>.json is page 1, <name>.<n>.json page n; a page with no file is an empty page
      const pageFile = (n) => path.join(dir, n === 1 ? file : file.replace(/\.json$/, `.${n}.json`));
      raw[key] = allPages((n) => (fs.existsSync(pageFile(n)) ? parse(fs.readFileSync(pageFile(n), 'utf8'), `fixture ${file} page ${n}`) : []), `fixture ${file}`);
      continue;
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
  const paged = (p, what) => allPages((n) => rest(`${p}?per_page=${PAGE}&page=${n}`), what);
  raw.pullsComments = paged(`${base}/pulls/${pr}/comments`, 'review comments');
  raw.pullsReviews = paged(`${base}/pulls/${pr}/reviews`, 'reviews');
  raw.issuesComments = paged(`${base}/issues/${pr}/comments`, 'issue comments');
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
// prose that is code: prompts carry behaviour in a plugin repo, and these .txt files are build input
const NOT_DOC_PATH = /(^|\/)(skills|commands|agents|output-styles|hooks)\/|(^|\/)requirements[^\/]*\.txt$|(^|\/)CMakeLists\.txt$/;
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
    // settled the way review-branch itself counts it: reviewed, or skipped as unchanged since an earlier round
    .filter((f) => f && (f.status === 'reviewed' || (f.status === 'skipped' && Number.isInteger(f.unchangedSince))) && typeof f.blob === 'string').map((f) => [f.file, f.blob]));
  let mb = git(repoDir, ['merge-base', `origin/${baseRef}`, headOid]);
  if (!mb.ok) mb = git(repoDir, ['merge-base', baseRef, headOid]);
  if (!mb.ok) return unknown(`no merge base with ${baseRef}`);
  const changed = git(repoDir, ['diff', '--name-only', '-z', mb.out.trim(), headOid]);
  if (!changed.ok) return unknown('git diff failed');
  const out = { status: 'covered', unreviewed: [], docsOnly: [], accepted: [] };
  for (const file of changed.out.split('\0').filter(Boolean)) {
    const lt = git(repoDir, ['ls-tree', '-z', headOid, '--', file]);
    const m = /^(\d+) \w+ ([0-9a-f]+)\t/.exec(lt.out);
    // a file gone at the head is a deletion: review-branch records a reviewed one as blob "deleted"
    const key = m ? blobKey(m[1], m[2]) : 'deleted';
    if (reviewed.get(file) === key) continue;
    const ok = accept.find((a) => a.path === file);
    if (DOC_PATH.test(file) && !NOT_DOC_PATH.test(file)) out.docsOnly.push(file);
    else if (ok) out.accepted.push({ path: file, reason: ok.reason });
    else out.unreviewed.push(file);
  }
  if (out.unreviewed.length) out.status = 'unreviewed';
  return out;
}

// ── local clone: openspec changes the PR leaves unarchived (W3-2; a warning, never the exit) ──────
// reconcile-check verify shares the run's deadline (never less than a second, so a deadline already
// spent on the queries still lets a quick verify answer).
const verifyLeft = () => Math.max(1000, DEADLINE - Date.now());
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
        // verify reads the change in the working tree of repoDir, not the PR's head: a checkout of
        // another branch answers for what is on disk. A checker that hangs is cut off: unavailable.
        const r = spawnSync(process.execPath, [script, 'verify', path.join(repoDir, 'openspec', 'changes', name)], { encoding: 'utf8', timeout: verifyLeft(), killSignal: 'SIGKILL' });
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
  const items = [];
  // one entry per comment, for pr-watch to tell a new or edited comment from one it already handled;
  // a review has no updated_at, so its submitted_at stands in, and only a review can be empty
  const ENDPOINTS = [['pullsComments', 'pulls/comments', 'updated_at'], ['pullsReviews', 'pulls/reviews', 'submitted_at'], ['issuesComments', 'issues/comments', 'updated_at']];
  for (const [k, endpoint, stamp] of ENDPOINTS) {
    for (const c of list(raw[k])) {
      if (c && c.user && c.user.login) authors.add(c.user.login);
      if (!c) continue;
      items.push({
        endpoint, id: c.id ?? null, updatedAt: c[stamp] ?? null, author: (c.user && c.user.login) || null,
        emptyBody: endpoint === 'pulls/reviews' && String(c.body ?? '').trim() === '',
        // an edit changes the hash; a review has no updated_at, so the hash is how its edits show
        bodyHash: crypto.createHash('sha256').update(String(c.body ?? '')).digest('hex').slice(0, 16),
      });
    }
  }
  return {
    precedent: { pr: prev ? prev.number : null, parents: prev ? parents : null, method },
    baseBehind: raw.compare && Number.isInteger(raw.compare.behind_by) ? raw.compare.behind_by : null,
    comments: {
      pullsComments: list(raw.pullsComments).length, pullsReviews: list(raw.pullsReviews).length,
      issuesComments: list(raw.issuesComments).length, authors: [...authors].sort(), items,
    },
  };
}

export function assess(raw, { expectHead, owner, repo, pr, config, cover } = {}) {
  const p = prOf(raw.graphql);
  const hits = [];
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
  // after the PR's own state: equal ranks keep their order, and "the PR is closed" is the more basic fact
  if (cover && cover.status === 'unreviewed') gate('unreviewed', `not covered by the last review: ${cover.unreviewed.join(', ')}`);

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
        name: c && (c.name || c.context), state: contextState(c), detailsUrl: (c && c.detailsUrl) || null,
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
    // reported, never judged here: ready's verdict does not depend on it (pr-watch's watch does)
    isCrossRepository: typeof p.isCrossRepository === 'boolean' ? p.isCrossRepository : null,
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
  if (!['ready', 'landed', 'watch', 'watch-ack'].includes(cmd)) throw new UsageError('unknown subcommand');
  const m = /^([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)$/.exec(slug || '');
  if (!m) throw new UsageError('<owner/repo> expected');
  if (!/^[1-9][0-9]*$/.test(prArg || '')) throw new UsageError('<pr> must be a number');
  const o = { cmd, owner: m[1], repo: m[2], pr: Number(prArg), accept: [], comments: [], start: false };
  const watchFlags = ['--start', '--now', '--comment'];
  for (let i = 0; i < rest.length; i++) {
    const flag = rest[i];
    const val = rest[i + 1];
    if (!['--expect-head', '--repo-dir', '--fixture', '--branch', '--accept-unreviewed', ...watchFlags].includes(flag)) throw new UsageError(`unknown option ${flag}`);
    if (watchFlags.includes(flag) && !cmd.startsWith('watch')) throw new UsageError(`${flag} is for watch only`);
    if (flag === '--start') { o.start = true; continue; }
    if (val === undefined) throw new UsageError(`${flag} needs a value`);
    i++;
    if (flag === '--now') {
      if (Number.isNaN(Date.parse(val))) throw new UsageError('--now must be an ISO time');
      o.now = new Date(val);
    } else if (flag === '--comment') {
      if (!COMMENT_KEY.test(val)) throw new UsageError(`--comment must look like <endpoint>:<id>:<16 hex>, got ${val}`);
      o.comments.push(val);
    } else if (flag === '--expect-head') {
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

// ── pr-watch: the per-PR state file (only watch and watch-ack write it) ──────────────────────────
const COMMENT_KEY = /^(pulls\/comments|pulls\/reviews|issues\/comments):[0-9]+:[0-9a-f]{16}$/;
export const STATE_VERSION = 1;
export const statePath = (repoDir, pr) => path.join(repoDir, '.claude', `pr-watch.${pr}.local.json`);

// The state of a PR's watch, null when there is none yet. Anything else that is not a state this
// version wrote is refused, never rebuilt: a rebuilt state forgets which comments were handled.
export function loadState(file, pr) {
  if (!fs.existsSync(file)) return null;
  const s = parse(fs.readFileSync(file, 'utf8'), `state ${file}`);
  const bad = (why) => new QueryError(`state ${file}: ${why}`);
  if (!s || typeof s !== 'object' || Array.isArray(s)) throw bad('not an object');
  if (s.version !== STATE_VERSION) throw bad(`version ${JSON.stringify(s.version)}, this script writes ${STATE_VERSION}`);
  if (s.pr !== pr) throw bad(`it is the state of PR ${JSON.stringify(s.pr)}, not ${pr}`);
  if (!Array.isArray(s.seen) || !s.seen.every((k) => typeof k === 'string')) throw bad('seen is not a list of keys');
  if (!s.headSeen || typeof s.headSeen !== 'object' || Array.isArray(s.headSeen)) throw bad('headSeen is not an object');
  for (const k of ['round', 'noProgressRounds', 'unchangedRounds', 'queryFailures']) {
    if (!Number.isInteger(s[k]) || s[k] < 0) throw bad(`${k} is not a count`);
  }
  if (typeof s.active !== 'boolean' || Number.isNaN(Date.parse(s.startedAt))) throw bad('active or startedAt is missing');
  return s;
}

// A new stretch of watching: what was handled stays handled, everything else starts over.
export function startState(prev, pr, now) {
  return {
    version: STATE_VERSION, pr, active: true, startedAt: now.toISOString(), round: 0,
    seen: prev ? [...prev.seen] : [], headSeen: {}, lastSignature: null,
    noProgressRounds: 0, unchangedRounds: 0, queryFailures: 0, lastTickAt: prev ? prev.lastTickAt ?? null : null,
  };
}

export function saveState(file, s) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmpFile = `${file}.tmp.${process.pid}`;
  fs.writeFileSync(tmpFile, `${JSON.stringify(s, null, 2)}\n`);
  fs.renameSync(tmpFile, file);
}

// Why a stretch of watching ends, in the order watchVerdict checks them; the first that holds wins.
// The pr-watch SKILL names exactly these (its docs test reads this list).
export const STOP_REASONS = ['not-open', 'fork', 'head-not-allowed', 'query-failed', 'limit', 'ready', 'needs-user', 'no-progress'];
const LIMIT_MS = 24 * 3600 * 1000;
const LIMIT_ROUNDS = 60;
const QUERY_FAILURES_TO_STOP = 3;
const NO_PROGRESS_TO_STOP = 2;
const REQUIRED_MISSING = 'required check missing:';

// One round of a watch, without I/O: verdict is ready's answer (null when the query threw), local the
// clone's facts about that head, extra the run attempts of failed checks. Returns the next state, the
// round's facts and exit 0 (go on) or 8 (stop, reason in watch.stop).
export function watchVerdict(verdict, queryError, state, local, extra, now) {
  const s = { ...state, seen: [...state.seen], headSeen: { ...state.headSeen } };
  const w = {
    round: s.round + 1, inGrace: false, settled: false, newComments: [], headAllowed: null, unpushed: null,
    dirty: local ? !!local.dirty : null, staleRemote: false, failedRuns: [], unchangedRounds: s.unchangedRounds,
    noProgressRounds: s.noProgressRounds, queryFailed: false, stop: null,
  };
  const finish = (reason, detail) => {
    if (reason) { w.stop = { reason, detail: detail || '' }; s.active = false; }
    s.round = w.round;
    s.lastTickAt = now.toISOString();
    return { state: s, watch: w, exit: reason ? 8 : 0 };
  };

  // a round that could not read the PR judges nothing else; only the third in a row stops
  let qerr = queryError;
  const items = (verdict && verdict.comments && verdict.comments.items) || [];
  if (!qerr && verdict.exit === 7) qerr = (verdict.hits[0] && verdict.hits[0].detail) || 'query failed';
  if (!qerr && typeof verdict.isCrossRepository !== 'boolean') qerr = 'isCrossRepository missing from the answer';
  if (!qerr && items.some((i) => i.id === null || i.id === undefined)) qerr = 'a comment has no id';
  if (qerr) {
    s.queryFailures += 1;
    w.queryFailed = true;
    return finish(s.queryFailures >= QUERY_FAILURES_TO_STOP ? 'query-failed' : null, qerr);
  }
  s.queryFailures = 0;

  const hits = verdict.hits || [];
  if (hits.some((h) => h.code === 'merge-gate' && h.gate === 'not-open')) return finish('not-open', 'the PR is merged or closed');
  if (verdict.isCrossRepository) return finish('fork', 'the PR comes from a fork');
  w.headAllowed = !!(local && local.headKnown && local.headAllowed);
  if (!w.headAllowed) return finish('head-not-allowed', `PR head ${verdict.head} is not an ancestor of the local HEAD`);
  w.unpushed = local.unpushed;
  if (now - Date.parse(s.startedAt) > LIMIT_MS || s.round >= LIMIT_ROUNDS) return finish('limit', `started ${s.startedAt}, ${s.round} rounds`);

  // a head is in its grace round the first time it is seen: GitHub may not have started its checks
  if (s.headSeen[verdict.head] === undefined) s.headSeen[verdict.head] = w.round;
  w.inGrace = s.headSeen[verdict.head] === w.round;
  const pending = hits.some((h) => h.code === 'pending');
  const requiredMissing = hits.some((h) => h.code === 'checks-failed' && String(h.detail).startsWith(REQUIRED_MISSING));
  w.settled = !w.inGrace && !pending && !requiredMissing;
  w.newComments = items.filter((i) => !i.emptyBody).map((i) => `${i.endpoint}:${i.id}:${i.bodyHash}`).filter((k) => !s.seen.includes(k));
  w.staleRemote = w.unpushed > 0;
  if (w.settled && !w.staleRemote) {
    const attempts = (extra && extra.runAttempts) || {};
    w.failedRuns = (verdict.checks || []).filter((c) => c.state === 'failed').map((c) => {
      const m = /\/actions\/runs\/([0-9]+)/.exec(c.detailsUrl || '');
      const runId = m ? m[1] : null;
      return { name: c.name, runId, attempt: runId && attempts[runId] !== undefined ? attempts[runId] : null };
    });
  }

  const signature = JSON.stringify([hits.map((h) => `${h.code}|${h.gate || ''}|${h.detail}`).sort(), verdict.head, local.head, w.newComments.length]);
  const unchanged = signature === s.lastSignature;
  s.lastSignature = signature;
  s.unchangedRounds = w.unchangedRounds = unchanged ? s.unchangedRounds + 1 : 0;
  // only settled rounds count: while checks run nothing is expected to move
  s.noProgressRounds = w.noProgressRounds = w.settled && unchanged ? s.noProgressRounds + 1 : 0;

  const quiet = !w.inGrace && w.newComments.length === 0;
  if (quiet && w.settled && verdict.exit === 0 && w.unpushed === 0) return finish('ready', 'mergeable, every check done');
  if (quiet && (w.staleRemote || (w.settled && hits.length > 0 && !hits.some((h) => h.code === 'checks-failed')))) {
    return finish('needs-user', w.staleRemote ? `${w.unpushed} local commit(s) not pushed` : hits.map((h) => h.code).join(', '));
  }
  if (s.noProgressRounds >= NO_PROGRESS_TO_STOP) return finish('no-progress', `${s.noProgressRounds} settled rounds without change`);
  return finish(null);
}

// The attempt number of each failed Actions run (the run id is in a check's detailsUrl). A run whose
// attempt cannot be read is left out: the skill then only reports it, never reruns it blind.
function runAttempts(o, checks) {
  const ids = [...new Set(checks.filter((c) => c.state === 'failed').map((c) => (/\/actions\/runs\/([0-9]+)/.exec(c.detailsUrl || '') || [])[1]).filter(Boolean))];
  const out = {};
  if (o.fixture) {
    const f = path.join(o.fixture, 'runs.json');
    const all = fs.existsSync(f) ? parse(fs.readFileSync(f, 'utf8'), 'fixture runs.json') : {};
    for (const id of ids) if (Number.isInteger(all[id])) out[id] = all[id];
    return out;
  }
  for (const id of ids) {
    try {
      const run = rest(`repos/${o.owner}/${o.repo}/actions/runs/${id}`);
      if (Number.isInteger(run && run.run_attempt)) out[id] = run.run_attempt;
    } catch (e) { if (!(e instanceof QueryError)) throw e; }
  }
  return out;
}

// One round of `watch`: read the state (or start one), ask GitHub and the clone, judge, write. Every
// refusal before the judgement (not started, too soon, wrong branch, a state it did not write) is
// exit 7 with the state file untouched.
function watchCli(o) {
  if (!o.repoDir) throw new UsageError('watch needs --repo-dir');
  const now = o.now || new Date();
  const file = statePath(o.repoDir, o.pr);
  let s = loadState(file, o.pr);
  if (!s && !o.start) throw new QueryError(`not-started: no watch state at ${file}; start one with watch --start`);
  if (o.start) s = startState(s, o.pr, now);
  else if (s.lastTickAt && now - Date.parse(s.lastTickAt) < 30000) throw new QueryError(`too-soon: the last round of PR ${o.pr} was at ${s.lastTickAt}; is another session watching it?`);

  let verdict = null;
  let queryError = null;
  try {
    verdict = assess(fetchAll(o), { ...o, config: loadConfig(), cover: null });
  } catch (e) {
    if (!(e instanceof QueryError)) throw e;
    queryError = e.message;
  }
  const branch = git(o.repoDir, ['rev-parse', '--abbrev-ref', 'HEAD']).out.trim();
  if (verdict && verdict.headRefName && branch !== verdict.headRefName) {
    throw new QueryError(`wrong-branch: the clone is on ${branch}, the PR's branch is ${verdict.headRefName}`);
  }
  const localHead = git(o.repoDir, ['rev-parse', 'HEAD']).out.trim();
  const local = { head: localHead, headKnown: false, headAllowed: false, unpushed: null, dirty: git(o.repoDir, ['status', '--porcelain', '--untracked-files=no']).out.trim() !== '' };
  if (verdict && typeof verdict.head === 'string') {
    local.headKnown = git(o.repoDir, ['cat-file', '-e', `${verdict.head}^{commit}`]).ok;
    local.headAllowed = local.headKnown && git(o.repoDir, ['merge-base', '--is-ancestor', verdict.head, 'HEAD']).ok;
    if (local.headAllowed) local.unpushed = Number(git(o.repoDir, ['rev-list', '--count', `${verdict.head}..HEAD`]).out.trim());
  }
  const extra = { runAttempts: verdict ? runAttempts(o, verdict.checks || []) : {} };
  const r = watchVerdict(verdict, queryError, s, local, extra, now);
  saveState(file, r.state);
  const stateIgnored = spawnSync('git', ['-C', o.repoDir, 'check-ignore', '-q', '--', file]).status === 0;
  const base = verdict || { gate: null, hits: [{ code: 'query-failed', detail: queryError }] };
  return { ...base, readyExit: verdict ? verdict.exit : 7, exit: r.exit, watch: { ...r.watch, stateIgnored } };
}

function watchAck(o) {
  if (!o.repoDir) throw new UsageError('watch-ack needs --repo-dir');
  if (!o.comments.length) throw new UsageError('watch-ack needs at least one --comment');
  const file = statePath(o.repoDir, o.pr);
  const s = loadState(file, o.pr);
  if (!s) throw new QueryError(`no watch state at ${file}: start one with watch --start`);
  s.seen = [...new Set([...s.seen, ...o.comments])];
  saveState(file, s);
  return { exit: 0, state: s };
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
    if (o.cmd === 'watch-ack') return emit({ ...head, ...watchAck(o) });
    if (o.cmd === 'watch') return emit({ ...head, ...watchCli(o) });
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

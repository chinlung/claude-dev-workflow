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

export function assess(raw, { expectHead } = {}) {
  const p = prOf(raw.graphql);
  const hits = [];
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
  const rollup = commit ? commit.statusCheckRollup : null;   // null: the head has no checks at all
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
    const raw = fetchAll(o);
    return emit({ ...head, ...assess(raw, o) });
  } catch (e) {
    if (!(e instanceof QueryError)) throw e;
    return emit({ ...head, exit: 7, gate: null, hits: [{ code: 'query-failed', detail: e.message }] });
  }
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1] && fs.realpathSync(process.argv[1]) === new URL(import.meta.url).pathname) {
  process.exitCode = main(process.argv.slice(2));
}

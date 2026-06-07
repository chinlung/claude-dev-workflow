# TypeScript / JavaScript / React review rules

> Applies to `**/*.{ts,tsx,js,jsx,mjs,cjs,vue,svelte}`. Adapted from alibaba/open-code-review `rule_docs/ts_js_tsx_jsx.md` (Apache-2.0), rewritten and extended.

## Review focus

**Language pitfalls**
- Loose equality (`==`/`!=`) where coercion can bite; falsy-zero / falsy-empty-string bugs in `if (x)` guards on numeric/string values
- `var` usage; closure capturing a loop variable; mutating shared objects passed by reference
- Missing `await` on a Promise (fire-and-forget that should be awaited; unhandled rejection); `forEach(async ...)` expecting sequential/awaited behavior
- `any` (or `as` casts) introduced without justification, especially at trust boundaries
- Destructuring / property access on possibly-undefined values without a guard
- Nested ternaries; business-significant hardcoded strings (especially URL paths)

**Async patterns**
- Independent awaits run sequentially that should be `Promise.all`; dependent operations incorrectly parallelized
- `try/catch` that swallows errors without logging or user feedback
- Race conditions: state read-then-write across an `await` boundary

**React (when .tsx/.jsx)**
- Hooks rules: conditional hook calls, hooks outside component/custom-hook scope
- `useEffect`: missing/stale dependencies, missing cleanup for subscriptions/timers/aborts
- Side effects during render (API calls, DOM mutation, state set in render body)
- Components declared inside other components (remount on every render)
- State placed at wrong hierarchy level (prop-drilling a value that belongs in the owner, or global state for purely local concerns)

**Security**
- `dangerouslySetInnerHTML` / `innerHTML` / `document.write` with non-static content (CWE-79)
- `eval`, `new Function`, string-form `setTimeout`/`setInterval`
- Secrets or API keys in client-shipped code; tokens persisted in `localStorage` without stated rationale
- Prototype pollution: assigning untrusted keys into objects (`obj[userKey] = ...` without allowlist)

## Do NOT report

- `==` against `null` used deliberately to match both null and undefined
- Missing `await` on intentionally fire-and-forget calls that are explicitly commented or `.catch`-handled
- `any` in test files, type-shim/.d.ts files, or rapidly-prototyped scripts
- Inline styles for genuinely dynamic values (computed positions, animation states)
- Exhaustive-deps "violations" where the omitted dep is a stable ref (setState, refs, dispatch)
- Sequential awaits where order is a real data dependency

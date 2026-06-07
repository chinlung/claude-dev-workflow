# Go review rules

> Applies to `**/*.go`. Structure follows alibaba/open-code-review rule_docs conventions (Apache-2.0); content written for Go codebases.

## Review focus

**Language pitfalls**
- Ignored error returns (`_ = f()` or unchecked `err`), especially on `Close`, `Write`, `Commit`
- Shadowed `err` inside `if`/`for` blocks masking the outer error
- Loop-variable capture in goroutines/closures (pre-1.22 semantics or when targeting older versions)
- Nil-map writes; nil-pointer method calls on interfaces holding typed nil
- Slice aliasing: append on a shared backing array mutating the caller's data
- `defer` inside loops (resource accumulation until function exit)

**Concurrency**
- Data races: shared state without mutex/atomic; check-then-act windows
- Goroutine leaks: blocked sends/receives on channels nobody drains; missing context cancellation
- `sync.WaitGroup.Add` inside the goroutine instead of before launch
- Channel close by receiver, or double-close

**Context & errors**
- `context.Context` not propagated to outbound calls; `context.Background()` deep in call chains
- Errors compared by string; missing `errors.Is/As` for wrapped errors
- Panics on paths reachable by external input where an error return is expected

**Security**
- SQL string concatenation (CWE-89); command construction from input (CWE-78)
- Path traversal on file serving (CWE-22); `math/rand` where `crypto/rand` is required
- Hardcoded credentials (CWE-798); TLS `InsecureSkipVerify: true`

## Do NOT report

- Ignored errors on deferred `Close` of read-only resources where failure is inconsequential and the codebase consistently does so
- "Missing" mutex around values confined to a single goroutine by construction
- Loop-variable capture when the module's `go.mod` targets Go ≥ 1.22
- `panic` in `init`/main-path startup validation (fail-fast is idiomatic)
- Unbuffered channels used deliberately for synchronization handoff

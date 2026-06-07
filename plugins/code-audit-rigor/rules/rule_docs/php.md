# PHP / Laravel review rules

> Applies to `**/*.php`. Structure follows alibaba/open-code-review rule_docs conventions (Apache-2.0); content written for PHP/Laravel codebases.

## Review focus

**Language pitfalls**
- Type juggling: `==` where `===` is needed (`"0" == false`, `0 == "abc"` pre-PHP8 semantics); `in_array`/`array_search` without strict flag
- `empty()` / falsy checks rejecting legitimate `0`, `"0"`, `0.0` values
- Null propagation: method call on possibly-null return (`find()` vs `findOrFail()`); missing nullsafe operator on optional chains
- Enum/backed-enum nullability: `tryFrom()` returning null unhandled; `from()` throwing on unexpected input
- String/array functions returning `false` on failure used as if returning data (`strpos` truthiness bug)

**Laravel-specific**
- Eloquent N+1: relation access inside loops without eager loading (`with()`)
- Mass assignment: `$request->all()` into `create()/update()` without `$fillable`/validated-only data (CWE-915)
- `DB::raw` / `whereRaw` with interpolated variables (CWE-89)
- Model observers/events firing on every `save()` in bulk operations
- Queued jobs capturing stale model state instead of re-fetching by id; missing idempotency on retryable jobs
- Transactions: partial writes without `DB::transaction`; events/notifications dispatched inside transactions that may roll back

**Security**
- Unvalidated request input reaching file paths (CWE-22), shell commands (CWE-78), or `unserialize` (CWE-502)
- `{!! !!}` blade output with user-influenced content (CWE-79)
- Authorization: route/controller actions missing policy/gate checks; IDOR via unscoped `find($id)` (CWE-639)
- Sensitive fields missing from `$hidden`; secrets in config files committed to VCS (CWE-798)

## Do NOT report

- `==` against constants where both sides are guaranteed same-typed
- `$request->all()` flowing into a FormRequest-validated path (validation already constrains keys)
- N+1 on relations provably bounded to a handful of rows (e.g. settings singletons)
- Missing transactions around single-statement writes
- `env()` calls inside `config/*.php` files (that is the correct location)
- Static-analysis-style nullability complaints where an upstream `abort_if`/`findOrFail` already guarantees non-null

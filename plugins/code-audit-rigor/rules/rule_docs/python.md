# Python review rules

> Applies to `**/*.py`. Structure follows alibaba/open-code-review rule_docs conventions (Apache-2.0); content written for modern Python codebases.

## Review focus

**Language pitfalls**
- Mutable default arguments (`def f(x, acc=[])`); late-binding closures in loops
- `is` vs `==` misuse (identity check on strings/ints outside the small-int cache)
- Bare `except:` / `except Exception: pass` swallowing errors silently
- Float equality comparison; integer division semantics (`/` vs `//`)
- Dict/attr access without guard on optional data (`d["k"]` vs `d.get("k")` on external input)
- Generator exhausted then re-iterated; modifying a list/dict while iterating it

**Async / concurrency**
- Blocking calls (`requests`, `time.sleep`, sync DB) inside `async def`
- Missing `await`; `asyncio.gather` without `return_exceptions` consideration
- Shared mutable state across threads without lock; non-atomic check-then-act

**Typing & contracts**
- `# type: ignore` added without justification; `Any` at trust boundaries
- Optional return types (`-> X | None`) whose callers never handle None

**Security**
- `subprocess` with `shell=True` and interpolated input (CWE-78)
- SQL built by string formatting/f-strings (CWE-89)
- `pickle.loads` / `yaml.load` (non-safe loader) on untrusted data (CWE-502)
- Path traversal: user input joined into filesystem paths without normalization check (CWE-22)
- Hardcoded secrets (CWE-798); `random` used where `secrets` is required

## Do NOT report

- Mutable defaults in private helpers provably never relying on cross-call state
- Bare `except` in top-level CLI entry points that log-and-exit
- `is None` / `is not None` — that is the correct idiom
- Blocking calls in scripts/CLIs that are not async contexts
- `yaml.safe_load` — already the safe variant
- Missing type hints in tests or one-off scripts

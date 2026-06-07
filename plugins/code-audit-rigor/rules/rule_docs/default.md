# Generic review rules (fallback for unmatched file types)

> Injected into review prompts for files no specific rule pack matches. Adapted from alibaba/open-code-review `rule_docs/default.md` patterns (Apache-2.0), rewritten.

## Review focus

**Obvious issues**
- Spelling errors in identifiers (declarations only — reference sites follow the declaration) and in user-facing / log / exception messages
- Unreachable code (impossible conditions, code after unconditional return/throw), unused declarations
- Large commented-out blocks with no stated retention intent

**Logic errors**
- Inverted or always-true/false conditionals; boolean operator misuse (`&&`/`||` swapped)
- Off-by-one and boundary violations, especially index/length checks
- Missing `break`/fallthrough in switch-like constructs; infinite-loop exit conditions
- Null/undefined dereference on paths where the value is provably absent

**Severe performance**
- Queries or I/O inside loops (N+1); unpaginated processing of unbounded datasets
- Nested-loop algorithms O(n²)+ on data that can grow

**Security baseline**
- Hardcoded credentials / API keys / tokens (CWE-798)
- Untrusted input reaching shell, SQL, file paths, or eval-like sinks without validation

## Do NOT report

- Reference-site "typos" that consistently follow the (possibly misspelled) declaration
- Style/formatting that a formatter would normalize (indentation, quote style, import order)
- Theoretical performance issues on provably small, bounded data
- Dead code that is clearly feature-flagged or platform-conditional
- Missing comments on self-explanatory code

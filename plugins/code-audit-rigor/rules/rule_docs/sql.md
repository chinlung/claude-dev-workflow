# SQL / query-mapper review rules

> Applies to `**/*.sql` and `**/*{mapper,dao}*.xml`. Adapted from alibaba/open-code-review `rule_docs/mapper_dao_xml.md` (Apache-2.0), rewritten and generalized.

## Review focus

**Injection**
- String interpolation into SQL (MyBatis `${}` instead of `#{}`; raw concatenation in any host language) — CWE-89
- Dynamic ORDER BY / table / column names from input without allowlist mapping

**Correctness**
- JOIN conditions: missing or wrong join keys producing cartesian products or silent row duplication
- `NULL` semantics: `= NULL` instead of `IS NULL`; `NOT IN` against a subquery that can yield NULL (matches nothing)
- Implicit type conversion in WHERE predicates defeating index use and causing locale-dependent matches
- UPDATE/DELETE without WHERE, or WHERE on non-unique columns where unique intent is clear

**Performance**
- Full-table scans: leading-wildcard LIKE, functions wrapping indexed columns in predicates
- Missing pagination on result sets that can grow unboundedly
- SELECT * feeding code that needs few columns, on wide or hot tables

**Migrations / DDL**
- Destructive operations (DROP, column type narrowing) without stated backfill/rollback path
- Missing index for new foreign keys / new high-cardinality query patterns introduced in the same change
- Long-locking operations (full-table ALTER) on hot tables without an online-migration strategy

## Do NOT report

- `${}`-style interpolation of values provably from a static enum/allowlist in code (verify the source before reporting)
- Full scans on small, bounded reference tables
- SELECT * in ad-hoc analytics scripts or one-off backfills
- Missing WHERE in scripts whose stated purpose is whole-table maintenance

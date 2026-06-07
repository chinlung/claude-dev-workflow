# package.json / dependency-manifest review rules

> Applies to `**/package.json`. Adapted from alibaba/open-code-review `rule_docs/package_json.md` (Apache-2.0), rewritten and extended with local dependency-upgrade discipline.

## Review focus

**Version ranges**
- `latest`, `*`, or bare `x` version ranges (non-reproducible builds, supply-chain exposure)
- Major-version jumps bundled silently into an unrelated change (should be their own reviewed upgrade)
- Git/HTTP URLs as dependency sources without commit pinning

**Dependency hygiene**
- New dependency duplicating capability already in the tree (check before adding)
- Runtime dependency placed in `devDependencies` or vice versa
- `@types/*` packages for libraries that now ship their own types (deprecated stub — remove the @types instead)

**Major-upgrade discipline (when versions change)**
- Are the APIs this codebase uses still present in the new major? (check changelog/migration guide)
- Are toolchain `peerDependencies` ready (linter / type-checker / build plugins often lag a major)? If the ecosystem hasn't caught up, defer rather than force
- Type-check + build must run after upgrades — changelog reading alone misses removed APIs

**Scripts**
- Lifecycle scripts (`postinstall`, `prepare`) running network fetches or arbitrary downloaded code
- Scripts with destructive operations lacking confirmation paths

## Do NOT report

- Caret/tilde ranges (`^1.2.3`, `~1.2.3`) — standard practice with a lockfile present
- devDependency version drift in non-published internal tooling
- Missing `engines` field unless the code demonstrably uses version-gated features

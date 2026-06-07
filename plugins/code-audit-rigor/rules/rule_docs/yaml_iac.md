# YAML / IaC / Dockerfile review rules

> Applies to `**/*.{yml,yaml,tf,tfvars}` and `**/Dockerfile*`. Structure follows alibaba/open-code-review rule_docs conventions (Apache-2.0); content written for IaC and CI config.

## Review focus

**Secrets & credentials**
- Hardcoded tokens, passwords, connection strings (CWE-798) — including base64-"obfuscated" values
- Secrets passed as plain env values in CI files instead of the platform's secret store
- Dockerfile `ARG`/`ENV` carrying secrets (persisted in image layers/history)

**Permissions & exposure**
- Wildcard IAM actions/resources (`"Action": "*"`, `"Resource": "*"`); overly broad role assumptions (CWE-732)
- Security groups / firewall rules open to 0.0.0.0/0 on non-public ports
- S3/storage buckets or databases with public access flags
- Containers running as root without stated need; privileged mode; host mounts of sensitive paths

**Correctness**
- YAML gotchas: unquoted values coerced (`no` → false, `3.10` → 3.1, leading-zero octals); duplicated keys (last-wins silently)
- Indentation placing a key under the wrong parent (valid YAML, wrong meaning)
- CI: jobs missing `needs`/dependency edges that ordering silently relied on; cache keys that never invalidate
- Terraform: `count`/`for_each` changes that force resource replacement (data loss) without a stated migration plan

**Supply chain**
- Unpinned image tags (`:latest`) or unpinned third-party GitHub Actions (tag instead of SHA) in production paths
- `curl | sh` install patterns fetching over mutable URLs

## Do NOT report

- Example/template files (`*.example`, `*.sample`, docs) containing placeholder credentials
- 0.0.0.0/0 on ports explicitly intended as public (80/443 on a public LB)
- `:latest` in local-dev compose files clearly outside production paths
- Root containers in build-stage-only images (multi-stage builds where final stage drops privileges)

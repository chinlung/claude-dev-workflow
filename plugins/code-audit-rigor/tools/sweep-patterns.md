# Sweep Patterns Reference

**When to read this:** Phase 1b (rule pack resolution) and Phase 3 (adversarial sweep) when expanding the audit scope or selecting the correct grep patterns for a category. Use this to pick precise patterns before running the literal file pass — not as a replacement for reading the actual code.

**Location:** `<plugin-root>/tools/sweep-patterns.md`, where `<plugin-root>` is `plugins/code-audit-rigor/`.

---

## Auth & Access Control

**Target:** authentication bypass, broken authorization, privilege escalation

| Pattern | Grep Example | False-positive caution |
|---------|-------------|----------------------|
| Skipped auth middleware | `grep -r "skip_auth\|bypass_auth\|no_auth\|@public" src/` | Test-only decorators may be legitimate |
| Missing authz after authn | `grep -r "req\.user" src/ \| grep -v "hasRole\|isAdmin\|can("` | ORM scopes may enforce authz transparently |
| Hardcoded admin check | `grep -rn "=== 'admin'\|== \"admin\"" src/` | Enum comparisons may be correct — read the enum definition |
| JWT/token not verified | `grep -rn "decode\|verify" src/auth/ \| grep -v "secret\|key"` | Some decode calls are for inspection only (logging), not trust decisions |

**CWE targets:** CWE-287, CWE-862, CWE-863

---

## Injection (SQL, Command, LDAP, XPath)

**Target:** user-controlled input reaching a query or command builder without escaping

| Pattern | Grep Example | False-positive caution |
|---------|-------------|----------------------|
| Raw string SQL | `grep -rn "query(.*+\|query(.*%s\|execute(.*f\"" src/` | ORM query builders that look like raw SQL — read the method definition |
| Shell command injection | `grep -rn "exec(\|spawn(\|subprocess" src/ \| grep -v "safe\|quoted"` | subprocess with array args (not string) is safe |
| Template injection | `grep -rn "render_string\|from_string\|Template(" src/` | Jinja2's `Template(user_input)` is dangerous; static templates are fine |

**CWE targets:** CWE-89, CWE-78, CWE-94

---

## Secrets & Credential Exposure

**Target:** hardcoded secrets, credentials in logs, secrets in responses

| Pattern | Grep Example | False-positive caution |
|---------|-------------|----------------------|
| Hardcoded credentials | `grep -rn "password\s*=\s*['\"][^\"']\|secret\s*=\s*['\"]" src/` | Test fixtures and example configs trigger this — check if it's production code |
| Secret in log statement | `grep -rn "log.*password\|logger.*token\|print.*secret" src/` | Masked log output (e.g., `[REDACTED]`) may be intentional |
| API key in source | `grep -rn "api_key\s*=\s*['\"][A-Za-z0-9]" src/` | Environment variable reads (`os.getenv`) are fine |

**CWE targets:** CWE-798, CWE-200, CWE-312

---

## Deserialization & File Upload

**Target:** untrusted deserialization, unrestricted file upload execution

| Pattern | Grep Example | False-positive caution |
|---------|-------------|----------------------|
| Unsafe deserialization | `grep -rn "pickle.loads\|yaml.load(\|unserialize(" src/` | `yaml.safe_load` is safe; `yaml.load` without `Loader=yaml.SafeLoader` is dangerous |
| Unrestricted upload | `grep -rn "upload\|save_file\|store_file" src/ \| grep -v "allowlist\|whitelist\|mimetype"` | Cloud storage SDKs may handle MIME validation internally — check SDK docs |
| Path traversal in upload | `grep -rn "os.path.join.*filename\|open.*filename" src/uploads/` | `secure_filename()` wrappers (Werkzeug etc.) usually prevent traversal |

**CWE targets:** CWE-502, CWE-434, CWE-22

---

## Concurrency & TOCTOU

**Target:** check-then-act races, missing locks on shared state

| Pattern | Grep Example | False-positive caution |
|---------|-------------|----------------------|
| Check-then-act in DB | `grep -rn "if.*exists.*then\|SELECT.*WHERE.*\(not in transaction\)" src/` | Requires manual inspection — grep finds candidates, not confirmed races |
| Shared state without lock | `grep -rn "global \|self\._cache\[" src/ \| grep -v "lock\|mutex\|threading.Lock"` | Read-only access to shared state is safe; locks are only needed for writes |
| Non-atomic counter increment | `grep -rn "\+= 1\|count\+\+" src/` (in threaded context) | Single-threaded execution contexts eliminate this risk |

**CWE targets:** CWE-362, CWE-367

---

## IaC & Infrastructure

**Target:** permissive IAM, open security groups, unencrypted storage

| Pattern | Grep Example | False-positive caution |
|---------|-------------|----------------------|
| Wildcard IAM | `grep -rn '"Action": "\*"\|actions = \["\*"\]' infra/` | Cross-account admin roles may legitimately need `*` |
| Open security group | `grep -rn '"0\.0\.0\.0/0"\|cidr = "0\.0\.0\.0/0"' infra/` | Public-facing load balancers legitimately need `0.0.0.0/0` on 443/80 |
| Unencrypted S3 | `grep -rn "aws_s3_bucket" infra/ \| grep -v "encrypt\|kms"` | Encryption may be set at bucket policy level, not resource level — check both |

**CWE targets:** CWE-732, CWE-312

---

## LLM Prompt & Context Injection

**Target:** user-controlled content injected into LLM system prompts without sanitization

| Pattern | Grep Example | False-positive caution |
|---------|-------------|----------------------|
| User input in system prompt | `grep -rn "system.*user_input\|system.*request\." src/` | Content that is explicitly labeled/tagged before injection may be safe |
| Unbounded context assembly | `grep -rn "messages\.append\|context \+=" src/llm/` | Without length limits, context can be exhausted by adversarial input |
| Tool call result injection | `grep -rn "tool_result.*format\|f\".*tool" src/` | Unsanitized tool outputs re-injected as trusted context |

**CWE targets:** CWE-77 (indirect — prompt injection as a class), CWE-116

---

## Using These Patterns

1. Run the grep patterns as **candidates**, not confirmed findings
2. For each match, apply Principle 2 (read the actual file:lines) before forming a finding
3. Record sweep coverage in Phase 5 report: which patterns ran, which files matched, which were read
4. False-positive cautions above are the most common dismissal reasons — steel-man against them before confirming

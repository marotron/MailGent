# MCP Leak Guard Field Contract

Type: contract
Status: resolved
Shipped: 0.2.0

## Scope

Outbound leak guard runs **after** grant evaluation on **subject** and **body** only, for placements opted in via Grant Desk. From/To/Cc/date/attachments are not scanned in v1.

## When leak guard runs

Scan when **all** of:

- Master toggle on
- Scope allowlist non-empty and includes `accountID/placement` or `accountID/*`
- Field granted by active grant
- No detector compile failure at runtime (invalid regex at runtime → fail-open, passthrough)

Grant denial still returns `not_granted` with reason `grant`; leak guard never runs on denied fields.

## MCP `get` payload (additive)

When leak guard is active for the message placement, `get` may include:

| Field | Values | Notes |
| --- | --- | --- |
| `subjectAccess` | `granted` · `not_granted` · `sanitized` · `withheld_confidential` | Agent-visible classification |
| `bodyAccess` | same | Same semantics as pre-0.2.0 grant denial, plus sanitize/withhold |
| `subjectAccessReason` | `grant` · `leak_guard` | Present when access ≠ plain grant path needs explanation |
| `bodyAccessReason` | `grant` · `leak_guard` | Omitted when reason is implicit (e.g. grant denial only) |
| `sanitizedRules` | `[String]` | Rule labels **disclosed** to the agent (redact/replace with disclose) |
| `note` | string | Optional stealth hint when replace rules hide sanitization from the agent |

### Access values

| Value | Agent sees | Body/subject text |
| --- | --- | --- |
| `granted` | Full field (possibly stealth-replaced text) | Sanitized or original per policy |
| `not_granted` | Field withheld by grant | Field omitted / empty |
| `sanitized` | Redacted or disclosed replace | Spans redacted or replaced; `sanitizedRules` lists matched disclosed rules |
| `withheld_confidential` | Whole field blocked (`blockWhole` hit mode) | Field omitted; rules in `sanitizedRules` when disclosed |

### Stealth replace

Custom rules with `discloseToAgent: false` and action `replace`:

- Agent gets `subjectAccess` / `bodyAccess` = `granted`
- Agent text shows the replacement value
- Audit log retains original + rule label
- MCP may include `note` explaining substitution; `sanitizedRules` omitted

## List / search / list_new

Subject lines on summary rows are sanitized when placement is opted in. Full access metadata appears on `get`.

## Audit log (human-facing)

`AuditMessageRef` stores optional `subjectOriginal`, `bodyOriginal`, `sanitizedRules`, `subjectAccess`, `bodyAccess`, `stealth`, and `leakDetections` (per-hit field/label/disposition for badges and detail). Access log UI overlays sanitized spans and withheld labels; hover shows originals.

## Related product ticket

Extends [08 · Agent operation contract](../../mailgent-product-definition/issues/08-define-agent-operation-contract.md) — grant denial stays explicit; leak guard adds disclosed sanitize vs stealth replace vs whole-field withhold.

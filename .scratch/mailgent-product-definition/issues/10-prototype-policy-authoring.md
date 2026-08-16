# Prototype Agent Access Policy Authoring

Type: prototype
Status: resolved
Blocked by: 07

## Question

How can a user safely create, inspect, test, explain, and revoke per-agent exposure policies using v1 selectors without needing security expertise?

## Answer

**Ship both IAs.** Wizard A for first grant; Grant desk B for inspect / edit / revoke / allow·deny carve-outs.

Locked product shape (`examples/prototype-policy-authoring.html`):

1. **Agent identity first** — pick or create agent (name, trust class, status, note). Pairing finish-setup deferred to [17](17-prototype-agent-pairing-setup.md).
2. **Scope before access** — v1 selector builder: account → placement → participants → date → smart folder. No regex / wildcards / AI rules.
3. **Resource caps, not free-form Write** — Messages: Read / Write proposals / Move / Soft-delete / Hard-delete. Drafts: Read / Create / Edit / Soft-delete. Attachments: content Read. Bulk Read/Write/Deny overwrites resource toggles; Deny exclusive.
4. **Explicit Deny carve-outs** — needed when broader allow exists (deny-wins). Absence of grant ≠ Deny.
5. **Grant desk** — left: agents → nested grants (mode dots + provider badges + scope) → Add grant. Right: agent identity or grant Scope/Access tabs with Test · Save · Revoke.

Soft-delete and hard-delete are separate grantable capabilities (ticket 08). Connect UX after Pair lives in ticket 17.

## Comments

- User: policy authoring must reflect separate access modes per resource — Read, Read+Write, Write, and Deny (block all). Aligns with ticket 07 data grants vs capabilities, but UX should surface mode on each grant/resource, not only as a hidden second axis.
- Working rule in prototype: Write on existing messages still requires enough Read to target them (at least locator). Pure Write means account drafts/send without mailbox browse. Soft-delete and hard-delete are separate grantable caps (supersedes earlier “hard delete ungivable”).
- UX revision: drop combined Read+Write control. Read and Write are independent toggles (both may be selected). Deny is exclusive and clears Read/Write.
- User insight: binary Write is a poor fit for existing messages. Content write belongs on Drafts; for mail, think Read + discrete mutation capabilities (soft delete / hard delete / move-label-archive / flags) + Deny — not free-form Write. Copy not in locked v1 ops (ticket 08). Attachment readability is its own field toggle.
- Deny is not redundant with “no grant”: deny-by-default covers absence of allow, but explicit Deny carve-outs are required when a broader allow exists (ticket 07 deny-wins). UX smell: sitting Deny next to Read/Write as a peer toggle confuses “no capability” with “override allow.”
- Variant A: Messages get Read / Write proposals / Move / Soft-delete toggles; Drafts get Read / Create / Edit / Soft-delete; Attachments keep content Read. Top modebar bulk-overwrites those resource toggles when changed.
- User chose: grow prototype step 2 as real v1 selector builder (account → placement → participants → date → smart folder). Keep regex/wildcards/AI rules out of scope per map. Access-mode step stays after scope is defined.
- Variant B grant desk inspector now mirrors A options: full selector builder + same Read/Write/Deny resource caps; row selection loads/persists per-grant scope.
- Pick agent step: list existing · configure name/trust class/status/note · pair new agent (default machine-local; lan-inference Touch ID stub). Shared agent store with Variant B sidebar.
- Deferred: finish-setup after Pair (pairing challenge, credential, local/MCP path, host config help, connection status, remote session open). Identity + trust class stay in this prototype; connect UX tracked in [17-prototype-agent-pairing-setup](17-prototype-agent-pairing-setup.md).
- Product decision: ship both authoring information architectures. Wizard A guides initial grant creation for an agent; Grant desk B supports inspecting, editing, revoking, and adding allow / deny carve-outs without step navigation.
- Grant desk: two panes. Agents group nested grant rows in left pane; agent selection opens identity settings, while grant selection opens Scope / Access tabs with Test · Save · Revoke on the tab row (right-aligned). Dropped B2/B3 layout experiments and Variant C templates preview.
- **Look locked** (`examples/prototype-policy-authoring.html`, variants A + B only):
  - Left: agent rows → nested grant rows (mode icon badges + overlapping account provider badges + scope text) → per-agent **Add grant**.
  - Right grant editor: Scope / Access tabs; Scope matches wizard A selector panel (fonts, spacing, copy); Access bulk Read/Write/Deny on one row with switches; resource caps unchanged.
  - Pair new agent opens in right pane. Header Add allow / Add deny removed.
  - Visual language: mode dots (eye/pen/ban), Gmail 2020 + Yahoo brand badges, switch toggles for bulk + caps.

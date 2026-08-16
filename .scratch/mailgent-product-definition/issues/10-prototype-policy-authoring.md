# Prototype Agent Access Policy Authoring

Type: prototype
Status: claimed
Blocked by: 07

## Question

How can a user safely create, inspect, test, explain, and revoke per-agent exposure policies using v1 selectors without needing security expertise?

## Comments

- User: policy authoring must reflect separate access modes per resource — Read, Read+Write, Write, and Deny (block all). Aligns with ticket 07 data grants vs capabilities, but UX should surface mode on each grant/resource, not only as a hidden second axis.
- Working rule in prototype: Write on existing messages still requires enough Read to target them (at least locator). Pure Write means account drafts/send without mailbox browse. Hard delete remains ungivable.
- UX revision: drop combined Read+Write control. Read and Write are independent toggles (both may be selected). Deny is exclusive and clears Read/Write.
- User insight: binary Write is a poor fit for existing messages. Content write belongs on Drafts; for mail, think Read + discrete mutation capabilities (soft delete / move-label-archive / flags) + Deny — not free-form Write. Copy not in locked v1 ops (ticket 08). Attachment readability is its own field toggle.
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

# 05 · Copy grant settings between agents

Type: feature
Status: pending
Blocked by: —
GitHub: https://github.com/marotron/MailGent/issues/35

## Summary

Add a way to duplicate one agent’s grant settings to another agent from the **Grant Desk** window. When the user is viewing the scope or access list for a target agent, show an action to copy grants from a source agent.

Example: while viewing **Cursor**’s grants, a button or menu item offers **“Copy grants from… → Grok Bot”**; after confirmation, Cursor’s rules are overwritten or merged with Grok Bot’s current rules.

## Motivation

Today each agent’s grants are managed independently. Users who connect several agents to the same mailbox often want the same baseline (e.g. read-only on a subset of mailboxes, no send). Repeating the same toggles across agents is tedious and error-prone.

## Acceptance

- [ ] In **Grant Desk**, the scope / access view for an agent shows a **“Copy grants from…”** control.
- [ ] The control lists all *other* connected agents that already have grants.
- [ ] Choosing a source agent previews what will change (added / removed / unchanged rules).
- [ ] User confirms before applying.
- [ ] Copy options: **Replace** (overwrite target with source) or **Merge** (union, with conflict resolution UI if rules differ).
- [ ] Operation is recorded in **Access Log** as a grant-change event with source + target agent IDs.
- [ ] Undo is available immediately after copy.

## Open questions

- Should mailbox-level grants and rule-level grants be copied separately or always together?
- Do we copy only enabled grants, or every grant including disabled ones?
- Should copy be allowed only between agents with the same channel set (e.g. MCP → MCP), or across any agent?
- Should there be a default “apply to all agents” option for global baseline templates?

## Notes

- This is distinct from the per-agent credential (Bearer / `MAILGENT_TOKEN`); only grants/rules are copied.
- Future work may generalize this into saved grant presets (see issue 06).

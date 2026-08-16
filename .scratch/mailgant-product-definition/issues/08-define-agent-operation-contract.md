# Define Agent Operations and Redaction Contract

Type: grilling
Status: open
Blocked by: 05, 07

## Question

Which resources and operations does MailGent expose to agents, how are searches bounded and paginated, how is inaccessible data omitted or redacted without leaking it through metadata, and how do draft and mutation proposals behave under partial access?

Constraint from map: agent `delete` is soft delete (Trash) only, approval-gated. Hard/permanent delete must not appear in the agent operation surface for Gmail or Yahoo.

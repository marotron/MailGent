# Merge Agent-Grants Train

Type: task
Status: open
Blocked by: 06

## Question

Is `train/agent-grants` ready to merge to `main` so humans can author durable agent data grants on the shipped local-read companion?

## Context

Merge when 01–06 are green. Update local-read map fog. Do not start OAuth on this PR.

## Verify

Train on `main`; `make test` green; auto-all-accounts gone; desk usable for account/mailbox/selector/deny/fields.

YAGNI: no OAuth work.

## Inputs

- Tickets 01–06

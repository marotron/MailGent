# Propose / revise — two manual sides

Same mail both times: Dana, “Server migration update”.

## Roles

| | MailGent | Agent |
|---|---|---|
| Owns | The confirm window, pins, deadline, version history | The next draft |
| Says | `awaiting_user`, then `attention_requested` or `revise_requested` | `propose_send`, then `propose_send` with `revises.proposalId` |
| Does not | Send mail on its own, or rewrite the draft | Open a second proposal for the same mail, or treat attention as “sent” |

Loop:

1. Agent calls `propose_send`. MailGent opens one confirm and returns `awaiting_user` plus `proposalId`.
2. Agent calls `await_propose_send` on that id and holds the call. Soft timeout stays at or below 50 seconds (Cursor drops the HTTP call around 60). A soft timeout is `awaiting_user` again. Call await again. Do not propose a new mail.
3. Human pins passages, expands each row, selects one or more structured Ask/Rewrite instructions, and optionally adds a note. MailGent returns `attention_requested` with `references[]` (`quote`, optional `note`, optional `instructions`, and chip-only redacted `instructionText` when instructions exist — note is never echoed as `Note: …`). The window stays open. The deadline does not move. On the fake server this is automatic: the first await is held for a few seconds, then 1 or 2 passages from that draft come back.
4. Agent reads each quote and its instructions. It calls `propose_send` with the same `to` / `subject` and `revises: { proposalId, results? }`. The new body must change passages selected for Rewrite. Each optional result is keyed by `referenceId` + `instructionId`; Ask answers must match the declared answer shape.
5. MailGent swaps the draft in place (v1 → v2) and returns `awaiting_user` on the **same** id.

`revise_requested` is the same loop, plus `revision.instructionText` for a whole-draft rewrite. Pins still have to be read. `attention_requested` means “look at these passages.” The notes on the Dana pins do ask for a rewrite of those passages, so the agent changes them and sends v2. It does not start a second proposal.

Chip rule: a pin number is drawn on a change row only when the pinned quote overlaps that row’s before or after text. Ask-only results remain as their own row when the quote is unchanged. “Rewrite more formally” on `server migration plan` means those three words change (for example → `server migration initiative`), not the clause around them.

## 1. Fake MailGent → agent

MailGent is the script. It accepts whatever mail the agent proposes, holds the first `await_propose_send` (default 5 seconds, `--delay`), then returns 1 or 2 passages from that draft. The Dana quotes are used when they are in the body. You are checking the agent.

```bash
python3 Scripts/tests/propose-revise/fake_mailgent.py --self-check
python3 Scripts/tests/propose-revise/fake_mailgent.py --wire-check
```

`--self-check` plays a good revise and the bad one from the live dogfood (the sentence around the pin changed, the pin did not). `--wire-check` does the good revise over HTTP.

Leave a server up for a real Cursor agent:

```bash
python3 Scripts/tests/propose-revise/fake_mailgent.py --port 8799
```

MCP URL `http://127.0.0.1:8799/mcp`, any bearer. Ask the agent to propose the Dana mail, await, then revise. This process prints `PASS` or `FAIL` and writes `/tmp/propose-revise-fake-mailgent.json`.

## 2. Fake agent → MailGent

The agent is the script. It always changes the pinned words. You are checking the confirm window.

Fake MailGent (no click-through):

```bash
python3 Scripts/tests/propose-revise/fake_mailgent.py --port 8799
python3 Scripts/tests/propose-revise/fake_agent.py --url http://127.0.0.1:8799/mcp
```

Real MailGent (you pin, the script revises):

```bash
export MAILGENT_BEARER="…"   # Settings → the paired agent → copy bearer
python3 Scripts/tests/propose-revise/fake_agent.py
```

Mail data lives in `email.json`; its default sender is `markujcv@gmail.com`. Override it with `--sender you@example.com` or `MAILGENT_SENDER` when testing against a different real Mail account. Real MailGent accepts only addresses returned by `list_accounts`.

Needs propose-send enabled. The script prints the two selections. After you click **Ask agent to look** it sends v2 on that same id and leaves the window open. Check:

- the window did not close or get a second copy
- v2 summary shows ① and ② with their structured instructions/results
- ‹ returns to v1

Report: `/tmp/propose-revise-fake-agent.json`.

## 3. Later

Real agent talking to real MailGent, after both sides pass on their own. Keep `await_propose_send` timeout ≤ 50. A dropped client call can cancel the proposal on the server while the confirm window is still on screen.

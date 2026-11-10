#!/usr/bin/env python3
"""Fake MailGent for propose_send envelope-guard regression.

Synthetic only — no personal mail.

  python3 Scripts/tests/propose-send-envelope/fake_mailgent.py --self-check
  python3 Scripts/tests/propose-send-envelope/fake_mailgent.py --port 8799

Self-check covers same-envelope dedupe (body ignored), already_sent after send,
cross-agent conflict, and cancel → re-propose.
"""

from __future__ import annotations

import argparse
import json
import sys
import time

from harness import (
    CLIENT_SOCKET_BUDGET,
    ProposeHTTPServer,
    ScriptedProposeMailGent,
    mcp_call,
    tool_text_payload,
)

REPORT = "/tmp/propose-send-envelope-fake-mailgent.json"


def _fail(msg: str, detail: object | None = None) -> int:
    print(f"self-check failed: {msg}", file=sys.stderr)
    if detail is not None:
        print(detail, file=sys.stderr)
    return 1


def _propose(url: str, bearer: str, *, to: str, subject: str, body: str) -> dict:
    return tool_text_payload(
        mcp_call(
            url,
            bearer,
            "tools/call",
            {
                "name": "propose_send",
                "arguments": {"to": to, "subject": subject, "body": body},
            },
            timeout=CLIENT_SOCKET_BUDGET,
        )
    )


def self_check() -> int:
    report: dict = {"cases": []}
    script = ScriptedProposeMailGent(hard_timeout=60.0)
    server = ProposeHTTPServer(script)
    url = server.start()
    try:
        # --- same envelope, different body → same proposalId ---
        first = _propose(url, "test", to="a@b.c", subject="Thanks", body="Draft A")
        if first.get("status") != "awaiting_user" or not first.get("proposalId"):
            return _fail("first propose missing awaiting_user", first)
        proposal_id = first["proposalId"]
        second = _propose(url, "test", to="a@b.c", subject="Thanks", body="Fresh copy")
        if second.get("proposalId") != proposal_id:
            return _fail("envelope dedupe minted a new proposalId", second)
        if "already open" not in str(second.get("message", "")).lower():
            return _fail("dedupe message missing already-open guidance", second)
        snap = script.snapshot(proposal_id)
        if not snap or snap["body"] != "Draft A":
            return _fail("dedupe replaced open draft body", snap)
        report["cases"].append({"name": "envelope_dedupe_ignores_body", "ok": True})

        # --- cross-agent conflict ---
        conflict = _propose(url, "other", to="a@b.c", subject="Thanks", body="Other")
        if conflict.get("status") != "conflict":
            return _fail("expected conflict across agents", conflict)
        if conflict.get("proposalId") != proposal_id:
            return _fail("conflict proposalId mismatch", conflict)
        if conflict.get("agentName") != "Cursor":
            return _fail("conflict agentName mismatch", conflict)
        report["cases"].append({"name": "cross_agent_conflict", "ok": True})

        # --- send → already_sent ---
        if not script.resolve(proposal_id, "send"):
            return _fail("resolve send failed", proposal_id)
        again = _propose(url, "test", to="a@b.c", subject="Thanks", body="After send")
        if again.get("status") != "already_sent":
            return _fail("expected already_sent after send", again)
        if again.get("proposalId") != proposal_id:
            return _fail("already_sent proposalId mismatch", again)
        report["cases"].append({"name": "already_sent_after_send", "ok": True})

        # --- cancel path allows a new propose ---
        cancelled = _propose(url, "test", to="c@d.e", subject="Other", body="One")
        cancel_id = cancelled["proposalId"]
        if not script.resolve(cancel_id, "cancel"):
            return _fail("resolve cancel failed", cancel_id)
        retry = _propose(url, "test", to="c@d.e", subject="Other", body="Two")
        if retry.get("status") != "awaiting_user":
            return _fail("expected new propose after cancel", retry)
        if retry.get("proposalId") == cancel_id:
            return _fail("cancel retry reused old proposalId", retry)
        report["cases"].append({"name": "cancel_allows_repropose", "ok": True})

        # --- soft await still awaiting ---
        open_again = _propose(url, "test", to="e@f.g", subject="Await", body="x")
        await_id = open_again["proposalId"]
        t0 = time.monotonic()
        soft = tool_text_payload(
            mcp_call(
                url,
                "test",
                "tools/call",
                {
                    "name": "await_propose_send",
                    "arguments": {"proposalId": await_id, "timeout": 1},
                },
                timeout=CLIENT_SOCKET_BUDGET,
            )
        )
        elapsed = time.monotonic() - t0
        if soft.get("status") != "awaiting_user":
            return _fail("soft await did not return awaiting_user", soft)
        if elapsed >= CLIENT_SOCKET_BUDGET:
            return _fail(f"soft await blew client budget ({elapsed:.1f}s)", soft)
        report["cases"].append(
            {"name": "soft_await_still_waiting", "elapsed": round(elapsed, 3), "ok": True}
        )

        report["ok"] = True
        print(json.dumps(report, indent=2))
        with open(REPORT, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2)
        print(f"wrote {REPORT}", file=sys.stderr)
        return 0
    finally:
        server.stop()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--port", type=int, default=8799)
    parser.add_argument("--send-delay", type=float, default=2.0)
    args = parser.parse_args()
    if args.self_check:
        return self_check()

    script = ScriptedProposeMailGent(send_delay=args.send_delay)
    server = ProposeHTTPServer(script, port=args.port)
    url = server.start()
    print(f"propose-send envelope fake listening on {url}", flush=True)
    print("Bearers: test → Cursor, other → Admin", flush=True)
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass
    finally:
        server.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

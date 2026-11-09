#!/usr/bin/env python3
"""Fake MailGent for await_ask transport regression (matrix E).

Synthetic only — no personal mail.

  python3 Scripts/tests/await-ask/fake_mailgent.py --self-check
  python3 Scripts/tests/await-ask/fake_mailgent.py --port 8798

Self-check covers soft budget under ~30s client timeout, allow → re-get,
dropped await (no cancel), dedupe, superseded, and unknown askId.
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
import time
import urllib.error

from harness import (
    ACCOUNT_ID,
    CLIENT_SOCKET_BUDGET,
    DEFAULT_SOFT,
    MESSAGE_ID,
    PLACEMENT,
    AskHTTPServer,
    ScriptedAskMailGent,
    mcp_call,
    tool_text_payload,
)

REPORT = "/tmp/await-ask-fake-mailgent.json"


def _fail(msg: str, detail: object | None = None) -> int:
    print(f"self-check failed: {msg}", file=sys.stderr)
    if detail is not None:
        print(detail, file=sys.stderr)
    return 1


def self_check() -> int:
    report: dict = {"cases": []}

    # --- E1: soft poll timeout=25 under ~30s client socket budget ---
    script = ScriptedAskMailGent()
    server = AskHTTPServer(script)
    url = server.start()
    try:
        opened = tool_text_payload(
            mcp_call(
                url,
                "test",
                "tools/call",
                {
                    "name": "get",
                    "arguments": {
                        "accountID": ACCOUNT_ID,
                        "placement": PLACEMENT,
                        "id": MESSAGE_ID,
                    },
                },
                timeout=CLIENT_SOCKET_BUDGET,
            )
        )
        if opened.get("status") != "awaiting_user" or not opened.get("askId"):
            return _fail("open get missing awaiting_user", opened)
        ask_id = opened["askId"]
        t0 = time.monotonic()
        soft = tool_text_payload(
            mcp_call(
                url,
                "test",
                "tools/call",
                {
                    "name": "await_ask",
                    "arguments": {"askId": ask_id, "timeout": DEFAULT_SOFT},
                },
                timeout=CLIENT_SOCKET_BUDGET,
            )
        )
        elapsed = time.monotonic() - t0
        if soft.get("status") != "awaiting_user":
            return _fail("soft poll did not return awaiting_user", soft)
        if elapsed >= CLIENT_SOCKET_BUDGET:
            return _fail(
                f"soft wait elapsed {elapsed:.1f}s ≥ client budget {CLIENT_SOCKET_BUDGET}",
                soft,
            )
        report["cases"].append({"name": "soft_budget", "elapsed": round(elapsed, 3), "ok": True})

        # --- E3: abort mid-await — Ask still pending; later await works ---
        def _abort_await() -> None:
            try:
                mcp_call(
                    url,
                    "test",
                    "tools/call",
                    {"name": "await_ask", "arguments": {"askId": ask_id, "timeout": 2}},
                    timeout=0.001,
                )
            except (TimeoutError, urllib.error.URLError, OSError):
                pass

        threading.Thread(target=_abort_await, daemon=True).start()
        time.sleep(0.05)
        snap = script.snapshot(ask_id)
        if not snap or not snap["isPending"]:
            return _fail("dropped await cancelled pending Ask", snap)
        later = tool_text_payload(
            mcp_call(
                url,
                "test",
                "tools/call",
                {"name": "await_ask", "arguments": {"askId": ask_id, "timeout": 1}},
                timeout=CLIENT_SOCKET_BUDGET,
            )
        )
        if later.get("status") != "awaiting_user":
            return _fail("later await after drop failed", later)
        report["cases"].append({"name": "no_cancel_on_drop", "ok": True})

        # --- E4: dedupe identical opens ---
        second = tool_text_payload(
            mcp_call(
                url,
                "test",
                "tools/call",
                {
                    "name": "get",
                    "arguments": {
                        "accountID": ACCOUNT_ID,
                        "placement": PLACEMENT,
                        "id": MESSAGE_ID,
                    },
                },
            )
        )
        if second.get("askId") != ask_id:
            return _fail("dedupe failed", {"first": ask_id, "second": second})
        report["cases"].append({"name": "dedupe", "ok": True})

        # --- E2: allow after soft → terminal allow → re-get body ---
        if not script.resolve(ask_id, "allow"):
            return _fail("resolve allow failed")
        terminal = tool_text_payload(
            mcp_call(
                url,
                "test",
                "tools/call",
                {"name": "await_ask", "arguments": {"askId": ask_id, "timeout": 1}},
            )
        )
        if terminal.get("outcome") != "allow":
            return _fail("expected allow outcome", terminal)
        body = tool_text_payload(
            mcp_call(
                url,
                "test",
                "tools/call",
                {
                    "name": "get",
                    "arguments": {
                        "accountID": ACCOUNT_ID,
                        "placement": PLACEMENT,
                        "id": MESSAGE_ID,
                    },
                },
            )
        )
        if body.get("body") != "Please pay" or body.get("status") != "ok":
            return _fail("re-get after allow missing body", body)
        report["cases"].append({"name": "allow_reget", "ok": True})
    finally:
        server.stop()

    # --- E5: superseded → re-get opens new evaluation ---
    script2 = ScriptedAskMailGent()
    open1 = script2.open_get(
        {"accountID": ACCOUNT_ID, "placement": PLACEMENT, "id": MESSAGE_ID}
    )
    ask1 = open1["askId"]
    if not script2.supersede(ask1):
        return _fail("supersede failed")
    outcome = script2.await_ask({"askId": ask1, "timeout": 1})
    if outcome.get("outcome") != "superseded":
        return _fail("expected superseded", outcome)
    open2 = script2.open_get(
        {"accountID": ACCOUNT_ID, "placement": PLACEMENT, "id": MESSAGE_ID}
    )
    if open2.get("status") != "awaiting_user" or open2.get("askId") == ask1:
        return _fail("superseded re-get did not open new ask", open2)
    report["cases"].append({"name": "superseded", "ok": True})

    # --- E6: unknown askId ---
    script3 = ScriptedAskMailGent()
    unknown = script3.await_ask({"askId": "does-not-exist", "timeout": 1})
    if not unknown.get("isError"):
        return _fail("unknown askId should error", unknown)
    report["cases"].append({"name": "unknown_askId", "ok": True})

    # Default soft when timeout omitted
    open_default = script3.open_get(
        {"accountID": ACCOUNT_ID, "placement": PLACEMENT, "id": "2"}
    )
    # Inject a second message body path via open — still awaiting
    omitted = script3.await_ask({"askId": open_default["askId"]})
    if omitted.get("status") != "awaiting_user":
        return _fail("default soft timeout path failed", omitted)
    report["cases"].append({"name": "default_soft_25_omitted", "ok": True})

    report["ok"] = True
    with open(REPORT, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
    print("self-check passed")
    print(json.dumps(report, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Fake MailGent for await_ask transport checks.")
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--port", type=int, default=0, help="Leave server up (0 = ephemeral).")
    parser.add_argument(
        "--allow-delay",
        type=float,
        default=2.0,
        help="Seconds until scripted Allow (port mode). 0 = never auto-allow.",
    )
    args = parser.parse_args()
    if args.self_check:
        return self_check()
    script = ScriptedAskMailGent(allow_delay=args.allow_delay)
    server = AskHTTPServer(script, port=args.port or 8798)
    url = server.start()
    print(
        f"Fake MailGent await_ask at {url} (any bearer). "
        f"Scripted Allow after {args.allow_delay:g}s. Ctrl-C to stop."
    )
    print("Point fake_agent at this URL:")
    print(f"  python3 Scripts/tests/await-ask/fake_agent.py --url {url}")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        server.stop()
        return 0


if __name__ == "__main__":
    raise SystemExit(main())

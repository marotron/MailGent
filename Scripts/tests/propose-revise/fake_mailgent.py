#!/usr/bin/env python3
"""Fake MailGent. Speaks propose_send / await_propose_send to whoever is the agent.

The human is scripted: propose_send is accepted, then the first await_propose_send
is held for a few seconds and returns attention_requested with 1 or 2 passages
from that draft. The server grades the agent's revise call.

  python3 Scripts/tests/propose-revise/fake_mailgent.py --self-check
  python3 Scripts/tests/propose-revise/fake_mailgent.py --port 8799

Point a Cursor MCP entry at http://127.0.0.1:8799/mcp (any bearer) to try a real agent.
The grade is printed here and written to the report file. Tool replies stay
protocol-shaped; they do not include the grade.
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from harness import (
    BAD_V2_BODY,
    GOOD_V2_BODY,
    PROPOSAL_ID,
    SENDER,
    SUBJECT,
    ScriptedMailGent,
    TO,
    V1_BODY,
    mcp_call,
    tool_result,
)

REPORT = "/tmp/propose-revise-fake-mailgent.json"

TOOLS = [
    {
        "name": "propose_send",
        "description": (
            "Propose a plain message. Returns awaiting_user. "
            "After attention_requested, call again with revises.proposalId and a body "
            "that changes the pinned quotes themselves."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "to": {"type": "string"},
                "sender": {"type": "string"},
                "subject": {"type": "string"},
                "body": {"type": "string"},
                "revises": {
                    "type": "object",
                    "description": "Only on the second call, after attention_requested. Same proposal, not a new mail.",
                    "properties": {
                        "proposalId": {"type": "string"},
                    },
                    "required": ["proposalId"],
                },
            },
            "required": ["to", "subject", "body"],
        },
    },
    {
        "name": "await_propose_send",
        "description": (
            "Soft-wait for the human. After propose_send, call this and hold it. "
            "A few seconds later it returns attention_requested with 1 or 2 passages to change. "
            "Then propose_send again with revises.proposalId. "
            "Keep timeout at or below 50 when talking to the real app."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "proposalId": {"type": "string"},
                "timeout": {"type": "number"},
            },
            "required": ["proposalId"],
        },
    },
]


def play(script: ScriptedMailGent, body: str) -> dict:
    """One scripted agent turn against the state machine. Returns the grade report."""
    script.propose({"to": TO, "sender": SENDER, "subject": SUBJECT, "body": V1_BODY})
    script.await_proposal({"proposalId": PROPOSAL_ID, "timeout": 45})
    script.propose({
        "to": TO,
        "sender": SENDER,
        "subject": SUBJECT,
        "body": body,
        "revises": {"proposalId": PROPOSAL_ID},
    })
    return script.report()


def self_check() -> int:
    good = play(ScriptedMailGent(), GOOD_V2_BODY)
    bad = play(ScriptedMailGent(), BAD_V2_BODY)
    ok = good["passed"] and not bad["passed"] and any("r1" in item for item in bad["failures"])
    print("good agent:", "PASS" if good["passed"] else good["failures"])
    print("bad agent (quote left untouched):", "FAIL as expected" if not bad["passed"] else "unexpected PASS")
    for item in bad["failures"]:
        print("  -", item)
    held = ScriptedMailGent(attention_delay=60)
    held.propose({"to": TO, "subject": SUBJECT, "body": V1_BODY})
    early = held.await_proposal({"proposalId": PROPOSAL_ID, "timeout": 45})
    if early.get("outcome") == "attention_requested" or early.get("status") != "awaiting_user":
        print("self-check failed: pins arrived before the delay", file=sys.stderr)
        return 1
    held.accepted_at = time.time() - 61
    late = held.await_proposal({"proposalId": PROPOSAL_ID, "timeout": 45})
    if late.get("outcome") != "attention_requested" or len(late.get("references") or []) != 2:
        print("self-check failed: pins missing after the delay", late, file=sys.stderr)
        return 1
    invented = (
        "The warehouse closes at six. "
        "Please confirm the delivery window for Thursday."
    )
    other = ScriptedMailGent()
    other.propose({"to": "pat@example.com", "subject": "Delivery", "body": invented})
    other.await_proposal({"proposalId": PROPOSAL_ID})
    quotes = [pin["quote"] for pin in other.pins]
    if not quotes or len(quotes) > 2 or any(quote not in invented for quote in quotes):
        print("self-check failed: invented mail pins", quotes, file=sys.stderr)
        return 1
    print(f"invented mail: {len(quotes)} pin(s) from that draft")
    if not ok:
        print("self-check failed", file=sys.stderr)
        return 1
    print("self-check passed")
    return 0


def serve(port: int, attention_delay: float) -> int:
    script = ScriptedMailGent(attention_delay=attention_delay)
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args) -> None:
            return

        def do_POST(self) -> None:  # noqa: N802
            if self.path.rstrip("/") != "/mcp":
                self._send(404, {"error": "not_found"})
                return
            length = int(self.headers.get("Content-Length") or "0")
            try:
                message = json.loads(self.rfile.read(length) or b"{}")
            except json.JSONDecodeError:
                self._send(400, {"error": "bad_request"})
                return
            method = message.get("method")
            req_id = message.get("id")
            params = message.get("params") or {}
            if method in {"notifications/initialized", "notifications/cancelled"}:
                self._send(202, b"")
                return
            if method == "initialize":
                self._rpc(req_id, {
                    "protocolVersion": params.get("protocolVersion") or "2025-03-26",
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "fake-mailgent", "version": "0"},
                })
                return
            if method == "tools/list":
                self._rpc(req_id, {"tools": TOOLS})
                return
            if method == "ping":
                self._rpc(req_id, {})
                return
            if method != "tools/call":
                self._send(400, {"error": "unknown_method"})
                return
            name = params.get("name")
            arguments = params.get("arguments") or {}
            sleep_for = 0.0
            with lock:
                if name == "propose_send":
                    outcome = script.propose(arguments)
                elif name == "await_propose_send":
                    sleep_for = _await_hold(script, arguments)
                    outcome = None if sleep_for > 0 else script.await_proposal(arguments)
                else:
                    outcome = {"isError": True, "message": f"Unknown tool {name}"}
                if outcome is not None:
                    report = script.report()
            if sleep_for > 0:
                print(f"[..] holding await {sleep_for:.0f}s, then pins")
                time.sleep(sleep_for)
                with lock:
                    outcome = script.await_proposal(arguments)
                    report = script.report()
            _write_report(report)
            _print_report(report)
            if outcome.get("isError"):
                self._rpc_error(req_id, outcome["message"])
                return
            self._rpc(req_id, {"content": [{"type": "text", "text": json.dumps(outcome)}]})

        def _rpc(self, req_id, result: dict) -> None:
            self._send(200, {"jsonrpc": "2.0", "id": req_id, "result": result})

        def _rpc_error(self, req_id, message: str) -> None:
            self._send(200, {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": message}],
                    "isError": True,
                },
            })

        def _send(self, status: int, body) -> None:
            if isinstance(body, (dict, list)):
                raw = json.dumps(body).encode("utf-8")
                content_type = "application/json"
            elif isinstance(body, bytes):
                raw = body
                content_type = "text/plain"
            else:
                raw = str(body).encode("utf-8")
                content_type = "text/plain"
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Fake MailGent on http://127.0.0.1:{port}/mcp")
    print(
        f"Accepts one propose_send. The first await is held {attention_delay:.0f}s, "
        "then returns 1 or 2 passages from that draft."
    )
    print(f"Report: {REPORT}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print()
        return 0


def _await_hold(script: ScriptedMailGent, arguments: dict) -> float:
    remaining = script.attention_wait_remaining()
    if remaining <= 0:
        return 0.0
    try:
        cap = float(arguments.get("timeout") if arguments.get("timeout") is not None else 45)
    except (TypeError, ValueError):
        cap = 45.0
    return min(remaining, max(0.0, cap - 1.0))


def wire_check(port: int) -> int:
    """Good agent over HTTP against one local server."""
    url = f"http://127.0.0.1:{port}/mcp"
    threading.Thread(target=serve, args=(port, 0), daemon=True).start()
    last_error = "server did not start"
    for _ in range(50):
        try:
            mcp_call(url, None, "initialize", {}, 1)
            last_error = ""
            break
        except Exception as error:  # noqa: BLE001 — probe until listen
            last_error = str(error)
            threading.Event().wait(0.05)
    if last_error:
        print(last_error, file=sys.stderr)
        return 1
    mcp_call(url, None, "tools/call", {
        "name": "propose_send",
        "arguments": {"to": TO, "subject": SUBJECT, "body": V1_BODY},
    }, 2)
    attention = tool_result(mcp_call(url, None, "tools/call", {
        "name": "await_propose_send",
        "arguments": {"proposalId": PROPOSAL_ID, "timeout": 45},
    }, 3))
    if attention.get("outcome") != "attention_requested":
        print("wire: expected attention_requested", attention, file=sys.stderr)
        return 1
    tool_result(mcp_call(url, None, "tools/call", {
        "name": "propose_send",
        "arguments": {
            "to": TO,
            "subject": SUBJECT,
            "body": GOOD_V2_BODY,
            "revises": {"proposalId": PROPOSAL_ID},
        },
    }, 4))
    report = json.loads(open(REPORT, encoding="utf-8").read())
    print("wire:", "PASS" if report["passed"] else report["failures"])
    return 0 if report["passed"] else 1


def _write_report(report: dict) -> None:
    with open(REPORT, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")


def _print_report(report: dict) -> None:
    if report["phase"] == "revised":
        status = "PASS" if report["passed"] else "FAIL"
        print(f"[{status}] revision grade")
        for item in report["failures"]:
            print("  -", item)
        return
    if report["phase"] == "attention_delivered":
        print("[..] attention sent")
        for pin in report["pins"]:
            print(f"  {pin['id']}: {pin['quote']!r} — {pin['note']}")
        return
    print(f"[..] phase {report['phase']}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Fake MailGent for the revise dogfood.")
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--wire-check", action="store_true", help="HTTP round trip of the good agent.")
    parser.add_argument("--port", type=int, default=8799)
    parser.add_argument("--delay", type=float, default=5, help="Seconds to hold the first await before pins.")
    args = parser.parse_args()
    if args.self_check:
        return self_check()
    if args.wire_check:
        return wire_check(args.port)
    return serve(args.port, args.delay)


if __name__ == "__main__":
    sys.exit(main())

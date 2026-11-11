#!/usr/bin/env python3
"""Fake agent. Speaks the revise contract to MailGent (or to fake_mailgent).

Against fake MailGent the human is already scripted, so this runs straight through:

  python3 Scripts/tests/propose-revise/fake_mailgent.py --port 8799
  python3 Scripts/tests/propose-revise/fake_agent.py --url http://127.0.0.1:8799/mcp

Against the real app you pin the two passages yourself, then this script sends
the revision that changes those words:

  export MAILGENT_BEARER="..."
  python3 Scripts/tests/propose-revise/fake_agent.py

Each await uses a 45s soft timeout so it stays under Cursor's own MCP cap.
This process is not Cursor, so the cap does not apply here. The short timeout
is what you should also use from a real agent.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import textwrap
import time

from harness import (
    CONTEXT,
    GOOD_V2_BODY,
    PINS,
    PROPOSAL_ID,
    SENDER,
    SUBJECT,
    TO,
    V1_BODY,
    grade_revision,
    mcp_call,
    tool_result,
)

REPORT = "/tmp/propose-revise-fake-agent.json"
DEFAULT_URL = "http://127.0.0.1:8788/mcp"
WIDTH = 72


class Log:
    """Sectioned terminal log. Color when stdout is a TTY and NO_COLOR is unset."""

    def __init__(self) -> None:
        self.color = sys.stdout.isatty() and not os.environ.get("NO_COLOR")

    def section(self, title: str) -> None:
        rule = "─" * max(4, WIDTH - len(title) - 1)
        print(f"\n{self._paint('1;36', title)} {self._paint('2', rule)}")

    def text(self, message: str, *, indent: str = "  ") -> None:
        print(textwrap.fill(message, width=WIDTH, initial_indent=indent, subsequent_indent=indent))

    def step(self, number: str, message: str) -> None:
        self._hang(f"  {number}  ", "     ", message, paint=("1", number))

    def kv(self, key: str, value: str) -> None:
        label = f"{key:<6}"
        self._hang(f"  {label}", "        ", value, paint=("2", label))

    def pin(self, pin_id: str, quote: str, note: str | None = None) -> None:
        tag = f"{pin_id:<4}"
        self._hang(f"  {tag}", "      ", quote, paint=("1;35", tag))
        if note:
            self.kv("note", note)

    def _hang(self, prefix: str, hang: str, message: str, *, paint: tuple[str, str] | None = None) -> None:
        lines = textwrap.wrap(message, width=max(24, WIDTH - len(prefix))) or [""]
        head = prefix.replace(paint[1], self._paint(paint[0], paint[1]), 1) if paint else prefix
        print(f"{head}{lines[0]}")
        for line in lines[1:]:
            print(f"{hang}{line}")

    def change(self, before: str, after: str) -> None:
        self.text(before, indent="  ")
        self.text(f"→ {after}", indent="    ")

    def status(self, word: str, detail: str = "") -> None:
        tone = {"PASS": "1;32", "FAIL": "1;31", "wait": "33", "open": "1;32"}.get(word, "1")
        painted = self._paint(tone, word)
        print(f"  {painted}  {detail}".rstrip())

    def fail(self, message: str, payload: object | None = None) -> None:
        print(self._paint("1;31", f"FAIL  {message}"), file=sys.stderr)
        if payload is not None:
            print(json.dumps(payload, indent=2, ensure_ascii=False), file=sys.stderr)

    def _paint(self, code: str, text: str) -> str:
        if not self.color:
            return text
        return f"\033[{code}m{text}\033[0m"


def main() -> int:
    parser = argparse.ArgumentParser(description="Fake agent for the revise dogfood.")
    parser.add_argument("--url", default=os.environ.get("MAILGENT_URL", DEFAULT_URL))
    parser.add_argument("--bearer", default=os.environ.get("MAILGENT_BEARER"))
    parser.add_argument(
        "--sender",
        default=os.environ.get("MAILGENT_SENDER", SENDER),
        help="From address. Defaults to email.json; MAILGENT_SENDER overrides it.",
    )
    parser.add_argument("--timeout", type=int, default=45, help="Soft await seconds. Keep ≤ 50 for Cursor.")
    parser.add_argument(
        "--wait-minutes",
        type=float,
        default=10,
        help="How long to wait for MailGent startup and your pins.",
    )
    args = parser.parse_args()

    log = Log()
    fake = "8799" in args.url or "fake" in args.url
    if not fake and not args.bearer:
        log.fail("Set MAILGENT_BEARER or pass --bearer. Real MailGent rejects an empty token.")
        return 1

    req_id = 1

    def call(method: str, params: dict) -> dict:
        nonlocal req_id
        req_id += 1
        return mcp_call(args.url, args.bearer, method, params, req_id)

    log.section("fake agent")
    log.kv("url", args.url)
    log.kv("mail", f"{TO} · {SUBJECT}")
    log.kv("case", CONTEXT["caseLabel"])

    if not fake and not _wait_until_ready(log, call, args.wait_minutes):
        return 1

    sender = args.sender
    if fake:
        sender = sender or SENDER
    elif not sender:
        accounts_payload = tool_result(call("tools/call", {
            "name": "list_accounts",
            "arguments": {},
        }))
        senders = [
            str(account["email"]).strip()
            for account in accounts_payload.get("accounts", [])
            if account.get("email") and str(account["email"]).strip()
        ]
        if len(senders) != 1:
            available = ", ".join(senders) if senders else "none"
            log.fail(f"Choose a sender with --sender or MAILGENT_SENDER (available: {available}).")
            return 1
        sender = senders[0]

    log.kv("from", sender)

    if not fake:
        log.section("you")
        log.text("Turn on Settings → Experimental → Propose-send context thread.")
        log.text("In the confirm window:")
        log.step("1", "Select “server migration plan”")
        log.kv("choice", "Expand passage 1 and check “Rewrite more formally”")
        log.step("2", "Select “I'll send the detailed timeline tomorrow, and the rollback checklist by Friday.”")
        log.kv("choice", "Expand passage 2 and check “Make this shorter”")
        log.step("3", "Select “we're moving to Phase 2 next Tuesday”")
        log.kv("choice", "Expand passage 3 and check “Check this is accurate and up to date”")
        log.step("4", "Click Ask agent to look")
        log.text("Leave the window open. This script sends v2 on the same proposalId.")

    opened = tool_result(call("tools/call", {
        "name": "propose_send",
        "arguments": {
            "to": TO,
            "sender": sender,
            "subject": SUBJECT,
            "body": V1_BODY,
            "context": CONTEXT,
        },
    }))
    proposal_id = opened.get("proposalId")
    if opened.get("status") != "awaiting_user" or not proposal_id:
        log.fail("propose_send did not open a confirm.", opened)
        return 1
    log.section("propose")
    log.status("open", proposal_id)

    attention = _wait_for_attention(log, call, proposal_id, args.timeout, args.wait_minutes)
    if attention is None:
        return 1
    _check_pins(log, attention, proposal_id)
    results = _instruction_results(attention)

    revised = tool_result(call("tools/call", {
        "name": "propose_send",
        "arguments": {
            "to": TO,
            "sender": sender,
            "subject": SUBJECT,
            "body": GOOD_V2_BODY,
            "context": CONTEXT,
            "revises": {"proposalId": proposal_id, "results": results},
        },
    }))
    if revised.get("status") != "awaiting_user" or revised.get("proposalId") != proposal_id:
        log.fail("revise was not accepted.", revised)
        return 1

    failures = grade_revision(GOOD_V2_BODY, proposal_id, proposal_id)
    report = {
        "url": args.url,
        "proposalId": proposal_id,
        "attention": attention,
        "revise": revised,
        "passed": not failures,
        "failures": failures,
    }
    with open(REPORT, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")

    log.section("revise")
    log.status("open", f"v2 on {proposal_id}")
    log.change("server migration plan", "server migration initiative")
    log.change(
        "I'll send the detailed timeline tomorrow, and the rollback checklist by Friday.",
        "Timeline and rollback checklist by Friday.",
    )
    if fake:
        log.section("grade")
        if report["passed"]:
            log.status("PASS", "pinned words changed")
        else:
            log.status("FAIL", "revision missed a pin")
            for item in failures:
                log.text(item)
        log.kv("report", REPORT)
        return 0 if report["passed"] else 1

    log.section("window")
    log.text("Same confirm, still open:")
    log.step("•", "version chip shows v2")
    log.step("①", "server migration plan → server migration initiative · Rewrite more formally")
    log.step("②", "the long timeline sentence → Timeline and rollback checklist by Friday. · Make this shorter")
    log.step("‹", "steps back to v1")
    log.text("Cancel the window yourself when you are done.")
    log.kv("report", REPORT)
    return 0


def _wait_until_ready(log: Log, call, wait_minutes: float) -> bool:
    log.section("startup")
    deadline = time.time() + wait_minutes * 60
    last_detail = ""
    while time.time() < deadline:
        try:
            payload = tool_result(call("tools/call", {
                "name": "status",
                "arguments": {},
            }))
            state = str(payload.get("state") or "unknown")
            if state == "ready":
                count = payload.get("indexedCount")
                detail = "index ready" if count is None else f"index ready · {count} messages"
                log.status("open", detail)
                return True
            if state == "failed":
                log.fail(str(payload.get("message") or "MailGent index failed."), payload)
                return False
            detail = str(
                payload.get("currentTask")
                or payload.get("message")
                or f"index {state}"
            )
        except Exception as error:  # noqa: BLE001 — app may still be relaunching
            detail = f"MailGent is relaunching · {error}"

        if detail != last_detail:
            log.status("wait", detail)
            last_detail = detail
        time.sleep(1)

    log.fail(f"MailGent did not become ready within {wait_minutes:g} minutes.")
    return False


def _wait_for_attention(log: Log, call, proposal_id: str, timeout: int, wait_minutes: float) -> dict | None:
    log.section("await")
    log.kv("id", proposal_id)
    deadline = time.time() + wait_minutes * 60
    polls = 0
    while time.time() < deadline:
        try:
            payload = tool_result(call("tools/call", {
                "name": "await_propose_send",
                "arguments": {"proposalId": proposal_id, "timeout": timeout},
            }))
        except Exception as error:  # noqa: BLE001 — show the MCP error and stop
            log.fail(f"await failed: {error}")
            return None
        outcome = payload.get("outcome")
        if outcome == "attention_requested":
            log.status("open", "attention_requested")
            for ref in payload.get("references") or []:
                log.pin(str(ref.get("id") or "?"), str(ref.get("quote") or ""), ref.get("note"))
            return payload
        if payload.get("status") == "awaiting_user":
            polls += 1
            log.status("wait", f"still waiting for pins · {polls}")
            continue
        log.fail(f"stopped on {outcome or 'unexpected payload'}", payload)
        return None
    log.fail("gave up waiting for pins")
    return None


def _instruction_results(attention: dict) -> list[dict]:
    """Report only declared instructions; Ask answers match their declared shape."""
    results: list[dict] = []
    for reference in attention.get("references") or []:
        reference_id = reference.get("id")
        for instruction in reference.get("instructions") or []:
            instruction_id = instruction.get("id")
            if not reference_id or not instruction_id:
                continue
            result: dict = {
                "referenceId": reference_id,
                "instructionId": instruction_id,
                "status": "pass",
            }
            shape = instruction.get("answerShape") or {}
            shape_type = shape.get("type")
            if shape_type == "yes_no":
                result["answer"] = {"type": "yes_no", "value": True}
            elif shape_type == "number":
                result["answer"] = {"type": "number", "value": 1}
            elif shape_type == "choices" and shape.get("options"):
                result["answer"] = {"type": "choice", "value": shape["options"][0]}
            elif shape_type == "text":
                result["answer"] = {"type": "text", "value": "Checked."}
            results.append(result)
    return results


def _check_pins(log: Log, attention: dict, proposal_id: str) -> None:
    if attention.get("proposalId") not in {proposal_id, PROPOSAL_ID}:
        log.text(f"warning: proposalId {attention.get('proposalId')!r}")
    got = [ref.get("quote") for ref in attention.get("references") or []]
    expected = [pin["quote"] for pin in PINS]
    if got != expected:
        log.text("warning: pins differ from the scripted pair. v2 still rewrites the scripted quotes.")
        log.kv("got", " | ".join(str(item) for item in got))
        log.kv("want", " | ".join(expected))


if __name__ == "__main__":
    sys.exit(main())

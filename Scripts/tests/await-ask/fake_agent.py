#!/usr/bin/env python3
"""Fake agent. Speaks the await_ask contract to MailGent (or to fake_mailgent).

Against fake MailGent the human is already scripted (Allow after --allow-delay),
so this runs straight through:

  python3 Scripts/tests/await-ask/fake_mailgent.py --port 8798
  python3 Scripts/tests/await-ask/fake_agent.py --url http://127.0.0.1:8798/mcp

Against the real app you Allow the conditional Ask yourself; this script soft-polls
and re-gets the body after allow:

  export MAILGENT_BEARER="..."
  python3 Scripts/tests/await-ask/fake_agent.py \\
    --account-id … --placement INBOX --id …

Each await uses a 25s soft timeout by default so it stays under Grok-class ~30s
socket budgets (and under Cursor's own MCP cap). This process is not Cursor, so
the cap does not apply here — the short timeout is what a real agent should use.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import textwrap
import time

from harness import (
    ACCOUNT_ID,
    BODY_TEXT,
    DEFAULT_SOFT,
    MESSAGE_ID,
    PLACEMENT,
    mcp_call,
    tool_text_payload,
)

REPORT = "/tmp/await-ask-fake-agent.json"
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
        label = f"{key:<10}"
        self._hang(f"  {label}", "            ", value, paint=("2", label))

    def status(self, word: str, detail: str = "") -> None:
        tone = {"PASS": "1;32", "FAIL": "1;31", "wait": "33", "open": "1;32", "allow": "1;32"}.get(
            word, "1"
        )
        painted = self._paint(tone, word)
        print(f"  {painted}  {detail}".rstrip())

    def fail(self, message: str, payload: object | None = None) -> None:
        print(self._paint("1;31", f"FAIL  {message}"), file=sys.stderr)
        if payload is not None:
            print(json.dumps(payload, indent=2, ensure_ascii=False), file=sys.stderr)

    def _hang(self, prefix: str, hang: str, message: str, *, paint: tuple[str, str] | None = None) -> None:
        lines = textwrap.wrap(message, width=max(24, WIDTH - len(prefix))) or [""]
        head = prefix.replace(paint[1], self._paint(paint[0], paint[1]), 1) if paint else prefix
        print(f"{head}{lines[0]}")
        for line in lines[1:]:
            print(f"{hang}{line}")

    def _paint(self, code: str, text: str) -> str:
        if not self.color:
            return text
        return f"\033[{code}m{text}\033[0m"


def main() -> int:
    parser = argparse.ArgumentParser(description="Fake agent for the await_ask dogfood.")
    parser.add_argument("--url", default=os.environ.get("MAILGENT_URL", DEFAULT_URL))
    parser.add_argument("--bearer", default=os.environ.get("MAILGENT_BEARER"))
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_SOFT,
        help="Soft await seconds. Keep ≤ 25 for Grok-class sockets; ≤ 50 for Cursor.",
    )
    parser.add_argument(
        "--wait-minutes",
        type=float,
        default=10,
        help="How long to wait for MailGent ready / human Allow.",
    )
    parser.add_argument("--account-id", default=os.environ.get("MAILGENT_ACCOUNT_ID", ACCOUNT_ID))
    parser.add_argument("--placement", default=os.environ.get("MAILGENT_PLACEMENT", PLACEMENT))
    parser.add_argument("--id", dest="message_id", default=os.environ.get("MAILGENT_MESSAGE_ID", MESSAGE_ID))
    args = parser.parse_args()

    log = Log()
    fake = "8798" in args.url or "fake" in args.url
    if not fake and not args.bearer:
        log.fail("Set MAILGENT_BEARER or pass --bearer. Real MailGent rejects an empty token.")
        return 1

    req_id = 1

    def call(method: str, params: dict) -> dict:
        nonlocal req_id
        req_id += 1
        return mcp_call(args.url, args.bearer, method, params, req_id)

    target = {
        "accountID": args.account_id,
        "placement": args.placement,
        "id": args.message_id,
    }

    log.section("fake agent")
    log.kv("url", args.url)
    log.kv("target", f"{target['accountID'][:8]}… / {target['placement']} / {target['id']}")
    log.kv("soft", f"{args.timeout}s")

    if not fake and not _wait_until_ready(log, call, args.wait_minutes):
        return 1

    if not fake:
        log.section("you")
        log.text("Settings → General → Allow conditional access prompts must be on.")
        log.text("Grant Desk: Body (or Attachment content) set to Ask for this agent.")
        log.step("1", "This script calls get → awaiting_user.")
        log.step("2", "Allow the Ask dialog when it appears.")
        log.step("3", "Script soft-polls await_ask, then re-gets the body.")

    opened = tool_text_payload(
        call(
            "tools/call",
            {"name": "get", "arguments": target},
        )
    )
    ask_id = opened.get("askId")
    if opened.get("status") != "awaiting_user" or not ask_id:
        # Already allowed / no Ask needed — treat as success if body present.
        if opened.get("body") or opened.get("status") == "ok":
            log.section("get")
            log.status("PASS", "no Ask needed; body already available")
            return _write_report(
                {
                    "url": args.url,
                    "target": target,
                    "opened": opened,
                    "passed": True,
                    "note": "no_ask",
                },
                log,
            )
        log.fail("get did not open an Ask (expected awaiting_user).", opened)
        return 1

    log.section("get")
    log.status("open", ask_id)
    log.kv("fields", ", ".join(opened.get("pendingFields") or []))
    if opened.get("expiresAt"):
        log.kv("expires", str(opened["expiresAt"]))

    outcome = _wait_for_decision(log, call, ask_id, args.timeout, args.wait_minutes)
    if outcome is None:
        return 1

    terminal = outcome.get("outcome")
    if terminal != "allow":
        log.fail(f"stopped on {terminal or 'unexpected payload'}", outcome)
        return 1

    log.section("re-get")
    body = tool_text_payload(
        call(
            "tools/call",
            {"name": "get", "arguments": target},
        )
    )
    got_body = body.get("body")
    if not got_body:
        log.fail("re-get after allow missing body", body)
        return 1

    log.status("allow", "lease claimed")
    log.kv("body", str(got_body)[:120])

    passed = True
    if fake and got_body != BODY_TEXT:
        passed = False
        log.status("FAIL", f"expected {BODY_TEXT!r}")

    report = {
        "url": args.url,
        "target": target,
        "askId": ask_id,
        "await": outcome,
        "reget": body,
        "passed": passed,
    }
    return _write_report(report, log)


def _write_report(report: dict, log: Log) -> int:
    with open(REPORT, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")
    log.section("grade" if report.get("passed") is not None else "done")
    if report.get("passed"):
        log.status("PASS", "get → await_ask → allow → re-get")
    elif report.get("passed") is False:
        log.status("FAIL", "body mismatch")
    log.kv("report", REPORT)
    return 0 if report.get("passed", True) else 1


def _wait_until_ready(log: Log, call, wait_minutes: float) -> bool:
    log.section("startup")
    deadline = time.time() + wait_minutes * 60
    last_detail = ""
    while time.time() < deadline:
        try:
            payload = tool_text_payload(
                call("tools/call", {"name": "status", "arguments": {}})
            )
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
                payload.get("currentTask") or payload.get("message") or f"index {state}"
            )
        except Exception as error:  # noqa: BLE001 — app may still be relaunching
            detail = f"MailGent is relaunching · {error}"

        if detail != last_detail:
            log.status("wait", detail)
            last_detail = detail
        time.sleep(1)

    log.fail(f"MailGent did not become ready within {wait_minutes:g} minutes.")
    return False


def _wait_for_decision(
    log: Log, call, ask_id: str, timeout: int, wait_minutes: float
) -> dict | None:
    log.section("await_ask")
    log.kv("askId", ask_id)
    deadline = time.time() + wait_minutes * 60
    polls = 0
    while time.time() < deadline:
        try:
            payload = tool_text_payload(
                call(
                    "tools/call",
                    {
                        "name": "await_ask",
                        "arguments": {"askId": ask_id, "timeout": timeout},
                    },
                )
            )
        except Exception as error:  # noqa: BLE001 — show the MCP error and stop
            log.fail(f"await failed: {error}")
            return None
        if payload.get("isError"):
            log.fail(str(payload.get("error") or "await_ask error"), payload)
            return None
        outcome = payload.get("outcome")
        if outcome in {"allow", "block", "expired", "superseded"}:
            log.status(str(outcome), ask_id)
            return payload
        if payload.get("status") == "awaiting_user":
            polls += 1
            log.status("wait", f"still waiting for human · poll {polls}")
            continue
        log.fail("unexpected await_ask payload", payload)
        return None
    log.fail("gave up waiting for Allow / Block")
    return None


if __name__ == "__main__":
    raise SystemExit(main())

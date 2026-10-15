#!/usr/bin/env python3
"""
Live regression test for MailGent Ask queue zombie-window bug.

Fires multiple concurrent MCP get/get_attachment calls against the local MailGent
loopback HTTP server, then leaves the Ask dialogs for the user to work through.
With the fix, every Allow/Block click dismisses the current Ask and the next queued
Ask appears; no popup becomes unresponsive.

Usage:
    export MAILGENT_BEARER="..."
    python3 Scripts/tests/ask-backlog-live-test.py

Prerequisites:
- MailGent 0.11.5+ running with index ready.
- Settings → General → "Allow conditional access prompts" is ON.
- A paired agent with Ask grants on the target account/mailbox/fields.
"""

import argparse
import json
import os
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

DEFAULT_URL = "http://127.0.0.1:8788/mcp"

# Replace with real values from `list_new` or `list_placements`.
DEFAULT_TARGETS = [
    {"accountID": "ACCOUNT_ID", "placement": "PLACEMENT", "id": "MESSAGE_ID_1"},
    {"accountID": "ACCOUNT_ID", "placement": "PLACEMENT", "id": "MESSAGE_ID_2"},
    {"accountID": "ACCOUNT_ID", "placement": "PLACEMENT", "id": "MESSAGE_ID_3"},
    {"accountID": "ACCOUNT_ID", "placement": "PLACEMENT", "id": "MESSAGE_ID_4"},
    {"accountID": "ACCOUNT_ID", "placement": "PLACEMENT", "id": "MESSAGE_ID_5"},
]


def make_request(url, bearer, tool_name, target):
    body = {
        "jsonrpc": "2.0",
        "id": target["id"],
        "method": "tools/call",
        "params": {"name": tool_name, "arguments": target},
    }
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {bearer}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return target["id"], resp.status, resp.read().decode("utf-8")[:500]
    except urllib.error.HTTPError as e:
        return target["id"], e.code, e.read().decode("utf-8")[:500]
    except Exception as e:
        return target["id"], None, str(e)


def main():
    parser = argparse.ArgumentParser(
        description="Fire concurrent MailGent MCP gets to exercise the Ask queue."
    )
    parser.add_argument("--url", default=os.environ.get("MAILGENT_URL", DEFAULT_URL))
    parser.add_argument("--bearer", default=os.environ.get("MAILGENT_BEARER"))
    parser.add_argument(
        "--tool", default="get", choices=["get", "get_attachment"]
    )
    parser.add_argument(
        "--count", type=int, default=5, help="Number of concurrent calls to fire."
    )
    parser.add_argument(
        "--targets", help="JSON array of target objects (accountID, placement, id)."
    )
    parser.add_argument(
        "--wait", action="store_true", help="Pause for Enter before firing."
    )
    args = parser.parse_args()

    if not args.bearer:
        print("Set MAILGENT_BEARER or pass --bearer.", file=sys.stderr)
        sys.exit(1)

    if args.targets:
        targets = json.loads(args.targets)
    else:
        targets = DEFAULT_TARGETS
        if targets[0]["accountID"] == "ACCOUNT_ID":
            print(
                "WARNING: using placeholder targets. Replace DEFAULT_TARGETS in this script, "
                "or pass --targets with a JSON array.",
                file=sys.stderr,
            )

    if args.tool == "get_attachment":
        for t in targets:
            t.setdefault("filename", "attachment.pdf")

    # Duplicate/repeat targets up to --count.
    calls = (targets * ((args.count // len(targets)) + 1))[: args.count]

    print(f"Firing {len(calls)} concurrent '{args.tool}' calls to {args.url}...")
    if args.wait:
        input("Press Enter when you're ready...")

    with ThreadPoolExecutor(max_workers=len(calls)) as executor:
        future_to_id = {
            executor.submit(make_request, args.url, args.bearer, args.tool, t): t["id"]
            for t in calls
        }
        for future in as_completed(future_to_id):
            msg_id, status, snippet = future.result()
            prefix = f"[{status}]" if status is not None else "[ERR]"
            print(f"{prefix} {msg_id}: {snippet.replace(chr(10), ' ')}")

    print(
        "\nDone. Work through the Ask backlog in MailGent; every click should dismiss and show the next."
    )


if __name__ == "__main__":
    main()

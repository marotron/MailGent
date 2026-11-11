#!/usr/bin/env python3
"""In-process scripted MailGent Ask protocol for await_ask transport checks.

Synthetic fixtures only — no personal mail. Mirrors the propose-revise harness shape.
"""

from __future__ import annotations

import json
import socket
import threading
import time
import urllib.error
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

ACCOUNT_ID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
PLACEMENT = "INBOX"
MESSAGE_ID = "1"
FILENAME = "statement.pdf"
BODY_TEXT = "Please pay"
DEFAULT_SOFT = 25
CLIENT_SOCKET_BUDGET = 30


def tool_text_payload(rpc: dict) -> dict:
    """Decode MCP tools/call result content[0].text JSON."""
    result = rpc.get("result") or {}
    if result.get("isError"):
        content = result.get("content") or []
        text = content[0].get("text", "") if content else ""
        try:
            return json.loads(text) if text.startswith("{") else {"error": text, "isError": True}
        except json.JSONDecodeError:
            return {"error": text, "isError": True}
    content = result.get("content") or []
    if not content:
        return {}
    text = content[0].get("text", "")
    return json.loads(text)


def mcp_call(
    url: str,
    bearer: str | None,
    method: str,
    params: dict,
    req_id: int = 1,
    timeout: float = CLIENT_SOCKET_BUDGET,
) -> dict:
    body = json.dumps(
        {"jsonrpc": "2.0", "id": req_id, "method": method, "params": params}
    ).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if bearer:
        headers["Authorization"] = f"Bearer {bearer}"
    request = urllib.request.Request(url, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


class ScriptedAskMailGent:
    """Minimal get / get_attachment / await_ask state machine."""

    def __init__(self, hard_timeout: float = 3600.0, allow_delay: float = 0.0) -> None:
        self._lock = threading.Lock()
        self._asks: dict[str, dict[str, Any]] = {}
        self._fp_index: dict[str, str] = {}
        self.hard_timeout = hard_timeout
        # When > 0, fake "human" Allows after this many seconds (dogfood / fake_agent).
        self.allow_delay = allow_delay
        self.bodies: dict[str, str] = {MESSAGE_ID: BODY_TEXT}
        self.opened: list[str] = []

    def _fingerprint(
        self,
        *,
        agent: str,
        account_id: str,
        placement: str,
        message_id: str,
        fields: list[str],
        filename: str | None,
    ) -> str:
        parts = [agent, account_id, placement, message_id, ",".join(sorted(fields))]
        if filename:
            parts.append(filename)
        return "|".join(parts)

    def open_get(
        self,
        arguments: dict,
        *,
        agent: str = "agent-1",
        fields: list[str] | None = None,
    ) -> dict:
        fields = fields or ["Body"]
        account_id = arguments.get("accountID", ACCOUNT_ID)
        placement = arguments.get("placement", PLACEMENT)
        message_id = arguments.get("id", MESSAGE_ID)
        filename = arguments.get("filename")
        fp = self._fingerprint(
            agent=agent,
            account_id=account_id,
            placement=placement,
            message_id=message_id,
            fields=fields,
            filename=filename,
        )
        with self._lock:
            if fp in self._fp_index:
                ask_id = self._fp_index[fp]
                entry = self._asks[ask_id]
                if entry["terminal"] is None:
                    return self._awaiting(entry)
            # Terminal allow lease → body. Block / expired / dismissed / superseded
            # never suppress a fresh Ask (Remember cache is out of scope for this fake).
            for entry in self._asks.values():
                if (
                    entry["fingerprint"] == fp
                    and entry["agent"] == agent
                    and entry["terminal"] == "allow"
                ):
                    return {
                        "id": message_id,
                        "accountID": account_id,
                        "placement": placement,
                        "body": self.bodies.get(message_id, BODY_TEXT),
                        "status": "ok",
                    }

            ask_id = str(uuid.uuid4())
            now = time.time()
            expires = now + self.hard_timeout
            entry = {
                "askId": ask_id,
                "agent": agent,
                "fingerprint": fp,
                "pendingFields": fields,
                "expiresAt": expires,
                "openedAt": now,
                "terminal": None,
                "filename": filename,
                "accountID": account_id,
                "placement": placement,
                "messageID": message_id,
            }
            self._asks[ask_id] = entry
            self._fp_index[fp] = ask_id
            self.opened.append(ask_id)
            return self._awaiting(entry)

    def await_ask(self, arguments: dict, *, agent: str = "agent-1") -> dict:
        ask_id = arguments.get("askId")
        soft = arguments.get("timeout")
        if soft is None:
            soft = DEFAULT_SOFT
        soft = max(1.0, min(120.0, float(soft)))
        with self._lock:
            entry = self._asks.get(ask_id)
            if entry is None or entry["agent"] != agent:
                return {"isError": True, "error": "Unknown or expired await_ask askId"}
            if entry["terminal"] == "allow":
                return {
                    "outcome": "allow",
                    "askId": ask_id,
                    "pendingFields": entry["pendingFields"],
                }
            if entry["terminal"] == "block":
                return {
                    "outcome": "block",
                    "askId": ask_id,
                    "pendingFields": entry["pendingFields"],
                }
            if entry["terminal"] == "expired":
                return {"outcome": "expired", "askId": ask_id}
            if entry["terminal"] == "superseded":
                return {"outcome": "superseded", "askId": ask_id}
            if entry["terminal"] == "dismissed":
                return {"outcome": "dismissed", "askId": ask_id}
            remaining = max(0.0, entry["expiresAt"] - time.time())
            wait = min(soft, remaining) if remaining else soft
            if self.allow_delay > 0:
                until_allow = max(0.0, entry["openedAt"] + self.allow_delay - time.time())
                wait = min(wait, until_allow)

        # Soft sleep outside the lock (dropped await must not cancel).
        # Self-check (allow_delay=0) caps sleep so matrix E stays fast; dogfood sleeps for real.
        if self.allow_delay > 0:
            time.sleep(wait)
        else:
            time.sleep(min(wait, 0.05) if wait > 0.05 else wait)

        with self._lock:
            entry = self._asks.get(ask_id)
            if entry is None or entry["agent"] != agent:
                return {"isError": True, "error": "Unknown or expired await_ask askId"}
            if (
                entry["terminal"] is None
                and self.allow_delay > 0
                and time.time() >= entry["openedAt"] + self.allow_delay
            ):
                entry["terminal"] = "allow"
            if entry["terminal"] is None:
                return self._awaiting(entry)
            terminal = entry["terminal"]
            if terminal == "allow":
                return {
                    "outcome": "allow",
                    "askId": ask_id,
                    "pendingFields": entry["pendingFields"],
                }
            if terminal == "block":
                return {
                    "outcome": "block",
                    "askId": ask_id,
                    "pendingFields": entry["pendingFields"],
                }
            if terminal == "expired":
                return {"outcome": "expired", "askId": ask_id}
            if terminal == "dismissed":
                return {"outcome": "dismissed", "askId": ask_id}
            return {"outcome": "superseded", "askId": ask_id}

    def resolve(self, ask_id: str, decision: str) -> bool:
        with self._lock:
            entry = self._asks.get(ask_id)
            if entry is None or entry["terminal"] is not None:
                return False
            entry["terminal"] = decision
            if decision != "allow":
                self._fp_index.pop(entry["fingerprint"], None)
            return True

    def supersede(self, ask_id: str) -> bool:
        return self.resolve(ask_id, "superseded")

    def snapshot(self, ask_id: str) -> dict | None:
        with self._lock:
            entry = self._asks.get(ask_id)
            if entry is None:
                return None
            return {
                "askId": ask_id,
                "isPending": entry["terminal"] is None,
                "terminal": entry["terminal"],
            }

    @staticmethod
    def _awaiting(entry: dict) -> dict:
        payload = {
            "status": "awaiting_user",
            "askId": entry["askId"],
            "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(entry["expiresAt"])),
            "pendingFields": entry["pendingFields"],
            "accountID": entry["accountID"],
            "placement": entry["placement"],
            "id": entry["messageID"],
            "message": "Waiting for human conditional access. Call await_ask with this askId; do not treat this as denied.",
        }
        if entry.get("filename"):
            payload["filename"] = entry["filename"]
        return payload


class AskHTTPServer:
    """Threading HTTP MCP surface over ScriptedAskMailGent."""

    def __init__(self, script: ScriptedAskMailGent, host: str = "127.0.0.1", port: int = 0) -> None:
        self.script = script
        self.host = host
        self.port = port
        self._httpd: ThreadingHTTPServer | None = None
        self._thread: threading.Thread | None = None

    @property
    def url(self) -> str:
        assert self._httpd is not None
        return f"http://{self.host}:{self._httpd.server_address[1]}/mcp"

    def start(self) -> str:
        script = self.script

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
                return

            def do_POST(self) -> None:  # noqa: N802
                length = int(self.headers.get("Content-Length", "0"))
                raw = self.rfile.read(length)
                try:
                    rpc = json.loads(raw.decode("utf-8"))
                except json.JSONDecodeError:
                    self._json(400, {"error": "bad json"})
                    return
                method = rpc.get("method")
                params = rpc.get("params") or {}
                req_id = rpc.get("id", 1)
                if method == "initialize":
                    self._json(
                        200,
                        {
                            "jsonrpc": "2.0",
                            "id": req_id,
                            "result": {
                                "protocolVersion": "2024-11-05",
                                "capabilities": {"tools": {}},
                                "serverInfo": {"name": "mailgent-await-ask-fake", "version": "0.0.0"},
                            },
                        },
                    )
                    return
                if method == "tools/list":
                    self._json(
                        200,
                        {
                            "jsonrpc": "2.0",
                            "id": req_id,
                            "result": {
                                "tools": [
                                    {
                                        "name": "get",
                                        "description": "Read a message. May return awaiting_user.",
                                        "inputSchema": {"type": "object"},
                                    },
                                    {
                                        "name": "get_attachment",
                                        "description": "Read attachment bytes. May return awaiting_user.",
                                        "inputSchema": {"type": "object"},
                                    },
                                    {
                                        "name": "await_ask",
                                        "description": (
                                            "Soft-wait for conditional Ask. Pass timeout below "
                                            "client socket budget (default 25; Grok ~30)."
                                        ),
                                        "inputSchema": {
                                            "type": "object",
                                            "properties": {
                                                "askId": {"type": "string"},
                                                "timeout": {"type": "number"},
                                            },
                                            "required": ["askId"],
                                        },
                                    },
                                ]
                            },
                        },
                    )
                    return
                if method != "tools/call":
                    self._json(
                        200,
                        {
                            "jsonrpc": "2.0",
                            "id": req_id,
                            "error": {"code": -32601, "message": "Method not found"},
                        },
                    )
                    return
                name = params.get("name")
                arguments = params.get("arguments") or {}
                if name == "get":
                    payload = script.open_get(arguments)
                elif name == "get_attachment":
                    payload = script.open_get(
                        arguments, fields=["Attachment content"]
                    )
                elif name == "await_ask":
                    payload = script.await_ask(arguments)
                else:
                    payload = {"isError": True, "error": f"Unknown tool {name}"}
                is_error = bool(payload.get("isError"))
                text = json.dumps(
                    {"error": payload["error"]} if is_error and "error" in payload else payload
                )
                self._json(
                    200,
                    {
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "result": {
                            "content": [{"type": "text", "text": text}],
                            "isError": is_error,
                        },
                    },
                )

            def _json(self, code: int, obj: dict) -> None:
                data = json.dumps(obj).encode("utf-8")
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self._httpd = ThreadingHTTPServer((self.host, self.port), Handler)
        self._thread = threading.Thread(target=self._httpd.serve_forever, daemon=True)
        self._thread.start()
        return self.url

    def stop(self) -> None:
        if self._httpd is not None:
            self._httpd.shutdown()
            self._httpd.server_close()
            self._httpd = None


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]

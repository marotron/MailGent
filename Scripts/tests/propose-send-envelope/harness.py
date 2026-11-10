#!/usr/bin/env python3
"""In-process scripted MailGent propose_send envelope guards.

Synthetic fixtures only — no personal mail. Mirrors await-ask harness shape.
"""

from __future__ import annotations

import json
import socket
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.request import Request, urlopen

DEFAULT_SOFT = 60
CLIENT_SOCKET_BUDGET = 70
HARD_TIMEOUT = 3600.0


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
    request = Request(url, data=body, headers=headers, method="POST")
    with urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def envelope_key(
    *,
    to: list[str],
    cc: list[str],
    bcc: list[str],
    sender: str | None,
    subject: str,
) -> str:
    def norm(s: str) -> str:
        return s.strip().lower()

    def list_norm(values: list[str]) -> str:
        return "\x1e".join(norm(v) for v in values)

    return "\x1f".join(
        [
            list_norm(to),
            list_norm(cc),
            list_norm(bcc),
            norm(sender or ""),
            norm(subject),
        ]
    )


def _as_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value] if value.strip() else []
    if isinstance(value, list):
        return [str(v) for v in value]
    return [str(value)]


class ScriptedProposeMailGent:
    """Minimal propose_send / await_propose_send envelope state machine."""

    def __init__(
        self,
        hard_timeout: float = HARD_TIMEOUT,
        send_delay: float = 0.0,
        agent_names: dict[str, str] | None = None,
    ) -> None:
        self._lock = threading.Lock()
        self._entries: dict[str, dict[str, Any]] = {}
        self._envelope_open: dict[str, str] = {}
        self._envelope_sent: dict[str, dict[str, Any]] = {}
        self.hard_timeout = hard_timeout
        self.send_delay = send_delay
        self.agent_names = agent_names or {
            "test": "Cursor",
            "other": "Admin",
        }
        self.opened: list[str] = []

    def agent_for(self, bearer: str | None) -> tuple[str, str]:
        token = bearer or "test"
        name = self.agent_names.get(token, token)
        return token, name

    def propose_send(self, arguments: dict, *, bearer: str | None = "test") -> dict:
        agent_id, agent_name = self.agent_for(bearer)
        to = _as_list(arguments.get("to"))
        cc = _as_list(arguments.get("cc"))
        bcc = _as_list(arguments.get("bcc"))
        sender = arguments.get("sender")
        subject = str(arguments.get("subject") or "")
        body = str(arguments.get("body") or "")
        key = envelope_key(to=to, cc=cc, bcc=bcc, sender=sender if isinstance(sender, str) else None, subject=subject)
        now = time.time()

        with self._lock:
            terminal = self._envelope_sent.get(key)
            if terminal and terminal["retainUntil"] > now:
                return {
                    "status": "already_sent",
                    "proposalId": terminal["proposalId"],
                    "outcome": "send",
                    "subject": terminal["subject"],
                    "to": terminal["to"],
                    "message": (
                        "This envelope was already sent. Do not propose it again; "
                        "check Sent or use a different subject if you need a new message."
                    ),
                }

            existing_id = self._envelope_open.get(key)
            if existing_id:
                entry = self._entries.get(existing_id)
                if entry and entry["decision"] is None and not entry["expired"]:
                    if entry["agentID"] != agent_id:
                        return {
                            "status": "conflict",
                            "proposalId": existing_id,
                            "agentName": entry["agentName"],
                            "expiresAt": time.strftime(
                                "%Y-%m-%dT%H:%M:%SZ", time.gmtime(entry["expiresAt"])
                            ),
                            "message": (
                                f"Another agent already has an open confirm for this envelope "
                                f"({entry['agentName']}). Await that proposalId or wait for it "
                                "to finish — do not open a second window."
                            ),
                        }
                    return {
                        "status": "awaiting_user",
                        "proposalId": existing_id,
                        "expiresAt": time.strftime(
                            "%Y-%m-%dT%H:%M:%SZ", time.gmtime(entry["expiresAt"])
                        ),
                        "message": (
                            "Confirm already open for this envelope. Call await_propose_send "
                            "with this proposalId; do not open a new proposal."
                        ),
                    }

            proposal_id = str(uuid.uuid4())
            expires = now + self.hard_timeout
            entry = {
                "proposalId": proposal_id,
                "agentID": agent_id,
                "agentName": agent_name,
                "envelopeKey": key,
                "to": to,
                "cc": cc,
                "bcc": bcc,
                "sender": sender,
                "subject": subject,
                "body": body,
                "expiresAt": expires,
                "openedAt": now,
                "decision": None,
                "expired": False,
            }
            self._entries[proposal_id] = entry
            self._envelope_open[key] = proposal_id
            self.opened.append(proposal_id)
            return {
                "status": "awaiting_user",
                "proposalId": proposal_id,
                "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(expires)),
                "message": (
                    "Waiting for human confirmation. Call await_propose_send with this "
                    "proposalId; do not bare re-propose the same envelope "
                    "(to/cc/bcc/sender/subject)."
                ),
            }

    def await_propose_send(self, arguments: dict, *, bearer: str | None = "test") -> dict:
        agent_id, _ = self.agent_for(bearer)
        proposal_id = arguments.get("proposalId")
        soft = arguments.get("timeout")
        if soft is None:
            soft = DEFAULT_SOFT
        soft = max(1.0, min(120.0, float(soft)))

        with self._lock:
            entry = self._entries.get(proposal_id)
            if entry is None:
                return {"isError": True, "error": "Unknown or expired propose_send proposalId."}
            if entry["agentID"] != agent_id:
                return {"isError": True, "error": "Unknown or expired propose_send proposalId."}
            if entry["expired"]:
                return {"outcome": "expired"}
            if entry["decision"] == "send":
                return {"outcome": "send"}
            if entry["decision"] == "cancel":
                return {"outcome": "cancelled"}
            if entry["decision"] == "openInMail":
                return {"outcome": "opened_in_mail"}
            remaining = max(0.0, entry["expiresAt"] - time.time())
            wait = min(soft, remaining) if remaining else soft
            if self.send_delay > 0:
                until_send = max(0.0, entry["openedAt"] + self.send_delay - time.time())
                wait = min(wait, until_send)

        if self.send_delay > 0:
            time.sleep(wait)
        else:
            time.sleep(min(wait, 0.05) if wait > 0.05 else wait)

        with self._lock:
            entry = self._entries.get(proposal_id)
            if entry is None or entry["agentID"] != agent_id:
                return {"isError": True, "error": "Unknown or expired propose_send proposalId."}
            if (
                entry["decision"] is None
                and not entry["expired"]
                and self.send_delay > 0
                and time.time() >= entry["openedAt"] + self.send_delay
            ):
                self._mark_decision_locked(entry, "send")
            if entry["expired"]:
                return {"outcome": "expired"}
            if entry["decision"] == "send":
                return {"outcome": "send"}
            if entry["decision"] == "cancel":
                return {"outcome": "cancelled"}
            if entry["decision"] == "openInMail":
                return {"outcome": "opened_in_mail"}
            return {
                "status": "awaiting_user",
                "proposalId": proposal_id,
                "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(entry["expiresAt"])),
                "message": (
                    "Still waiting for human confirmation. Keep calling await_propose_send "
                    "with this same proposalId — do not bare re-propose."
                ),
            }

    def resolve(self, proposal_id: str, decision: str) -> bool:
        with self._lock:
            entry = self._entries.get(proposal_id)
            if entry is None or entry["decision"] is not None or entry["expired"]:
                return False
            self._mark_decision_locked(entry, decision)
            return True

    def _mark_decision_locked(self, entry: dict[str, Any], decision: str) -> None:
        entry["decision"] = decision
        self._envelope_open.pop(entry["envelopeKey"], None)
        if decision == "send":
            now = time.time()
            self._envelope_sent[entry["envelopeKey"]] = {
                "proposalId": entry["proposalId"],
                "subject": entry["subject"],
                "to": entry["to"],
                "retainUntil": now + self.hard_timeout,
            }

    def snapshot(self, proposal_id: str) -> dict | None:
        with self._lock:
            entry = self._entries.get(proposal_id)
            if entry is None:
                return None
            return {
                "proposalId": proposal_id,
                "isPending": entry["decision"] is None and not entry["expired"],
                "decision": entry["decision"],
                "body": entry["body"],
            }


class ProposeHTTPServer:
    """Threading HTTP MCP surface over ScriptedProposeMailGent."""

    def __init__(
        self, script: ScriptedProposeMailGent, host: str = "127.0.0.1", port: int = 0
    ) -> None:
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
                bearer = None
                auth = self.headers.get("Authorization") or ""
                if auth.lower().startswith("bearer "):
                    bearer = auth[7:].strip()

                if method == "initialize":
                    self._json(
                        200,
                        {
                            "jsonrpc": "2.0",
                            "id": req_id,
                            "result": {
                                "protocolVersion": "2024-11-05",
                                "capabilities": {"tools": {}},
                                "serverInfo": {
                                    "name": "mailgent-propose-send-envelope-fake",
                                    "version": "0.0.0",
                                },
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
                                        "name": "propose_send",
                                        "description": (
                                            "Propose mail. Envelope dedupe / already_sent / conflict."
                                        ),
                                        "inputSchema": {
                                            "type": "object",
                                            "properties": {
                                                "to": {"type": "string"},
                                                "subject": {"type": "string"},
                                                "body": {"type": "string"},
                                                "cc": {"type": "string"},
                                                "bcc": {"type": "string"},
                                                "sender": {"type": "string"},
                                            },
                                            "required": ["to", "subject", "body"],
                                        },
                                    },
                                    {
                                        "name": "await_propose_send",
                                        "description": (
                                            "Soft-wait for propose_send. Keep the same proposalId."
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
                if name == "propose_send":
                    payload = script.propose_send(arguments, bearer=bearer)
                elif name == "await_propose_send":
                    payload = script.await_propose_send(arguments, bearer=bearer)
                else:
                    payload = {"isError": True, "error": f"Unknown tool {name}"}
                is_error = bool(payload.get("isError"))
                text = json.dumps(
                    {"error": payload["error"]}
                    if is_error and "error" in payload
                    else payload
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

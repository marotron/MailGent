"""Shared contract for the propose_send revise dogfood.

MailGent owns the confirm window, the pins, and the outcome payloads.
The agent owns the next tool call: read the pins, change those quotes,
and call propose_send again with revises.proposalId.

A pin chip is drawn only when the pinned quote overlaps a diff hunk
(the quote is inside the hunk, or the hunk is inside the quote).
Rewriting the sentence around an unchanged quote leaves the quote in the
stable middle, so the chip is dropped. The grader fails that case.
"""

from __future__ import annotations

import json
import re
import time
import urllib.error
import urllib.request
from pathlib import Path

EMAIL = json.loads(Path(__file__).with_name("email.json").read_text(encoding="utf-8"))
PROPOSAL_ID = "P-DOGFOOD-1"
SENDER = EMAIL["sender"]
TO = EMAIL["to"]
SUBJECT = EMAIL["subject"]
V1_BODY = EMAIL["body"]
CONTEXT = EMAIL["context"]
# Changes the pinned spans themselves.
GOOD_V2_BODY = EMAIL["revisedBody"]
# Live miss: the sentence around pin 1 changed; the pinned words did not.
BAD_V2_BODY = (
    "Hi Dana,\n\n"
    "I'm writing to update you on the server migration plan. "
    "We're moving to Phase 2 next Tuesday. "
    "I'll send the timeline tomorrow and the rollback checklist by Friday.\n\n"
    "Best,\nAlex"
)

PINS = [
    {
        "id": "r1",
        "quote": "server migration plan",
        "note": "Rewrite more formally",
        "shorter": False,
    },
    {
        "id": "r2",
        "quote": "I'll send the detailed timeline tomorrow, and the rollback checklist by Friday.",
        "note": "Make this shorter",
        "shorter": True,
        "needles": ("timeline", "checklist"),
    },
]

_GREETING = re.compile(
    r"^(hi|hello|hey|dear|best|thanks|thank you|regards|cheers)\b[,!]?\s*$",
    re.IGNORECASE,
)


def attention_text(count: int) -> str:
    noun = "passage" if count == 1 else "passages"
    return (
        f"The user pinned {count} {noun} for your attention. "
        "Change each quoted passage so it follows its note. "
        "Call propose_send with revises.proposalId and the full updated body. "
        "Do not open a new proposal."
    )


def pins_for_body(body: str) -> list[dict]:
    """Dana's two quotes when they are in the draft. Otherwise 1 or 2 spans from the text."""
    if all(pin["quote"].lower() in body.lower() for pin in PINS):
        return [dict(pin) for pin in PINS]
    parts = re.split(r"\n+|(?<=[.!?])\s+", body.strip())
    chunks: list[str] = []
    for part in parts:
        text = part.strip()
        if len(text) < 16 or _GREETING.match(text):
            continue
        chunks.append(text)
    if not chunks:
        fallback = " ".join(body.split())
        if len(fallback) > 160:
            fallback = fallback[:160].rsplit(" ", 1)[0]
        chunks = [fallback] if fallback else []
    notes = ("Rewrite more formally", "Make this shorter")
    return [
        {
            "id": f"r{index + 1}",
            "quote": quote,
            "note": notes[index],
            "shorter": index == 1,
        }
        for index, quote in enumerate(chunks[:2])
    ]


def attention_payload(proposal_id: str = PROPOSAL_ID, pins: list[dict] | None = None) -> dict:
    chosen = PINS if pins is None else pins
    return {
        "outcome": "attention_requested",
        "proposalId": proposal_id,
        "instructionText": attention_text(len(chosen)),
        "references": [
            {"id": pin["id"], "quote": pin["quote"], "note": pin["note"], "stale": False}
            for pin in chosen
        ],
    }


def grade_revision(
    body: str,
    revises_id: str | None,
    proposal_id: str = PROPOSAL_ID,
    pins: list[dict] | None = None,
    original: str | None = None,
) -> list[str]:
    """Return human-readable failures. Empty list means the agent did its job."""
    chosen = PINS if pins is None else pins
    baseline = V1_BODY if original is None else original
    failures: list[str] = []
    if not revises_id:
        failures.append("called propose_send without revises.proposalId (that opens a second window)")
        return failures
    if revises_id != proposal_id:
        failures.append(f"revises.proposalId is {revises_id!r}, expected {proposal_id!r}")
    if body.strip() == baseline.strip():
        failures.append("body is unchanged")
        return failures
    for pin in chosen:
        quote = pin["quote"]
        if quote.lower() in body.lower():
            failures.append(
                f"{pin['id']} quote still in the draft ({quote!r}). "
                "Change those words. Editing around them does not attach the chip."
            )
            continue
        needles = pin.get("needles")
        if pin.get("shorter") and needles:
            replacement = _sentence_with(body, tuple(needles))
            if replacement is None:
                failures.append(f"{pin['id']} dropped the timeline passage instead of shortening it")
            elif len(replacement) >= len(quote):
                failures.append(
                    f"{pin['id']} replacement is not shorter ({len(replacement)} vs {len(quote)} chars)"
                )
    return failures


def _sentence_with(body: str, needles: tuple[str, ...]) -> str | None:
    for raw in body.replace("\n", " ").split("."):
        sentence = raw.strip()
        if sentence and any(n in sentence.lower() for n in needles):
            return sentence
    return None


class ScriptedMailGent:
    """One proposal. The first await waits, then returns pins taken from that draft."""

    def __init__(self, attention_delay: float = 0) -> None:
        self.proposal_id = PROPOSAL_ID
        self.body = ""
        self.original_body = ""
        self.pins: list[dict] = []
        self.phase = "idle"
        self.failures: list[str] = []
        self.calls: list[dict] = []
        self.attention_delay = attention_delay
        self.accepted_at: float | None = None

    def attention_wait_remaining(self) -> float:
        if self.phase != "awaiting" or self.accepted_at is None:
            return 0.0
        return max(0.0, self.accepted_at + self.attention_delay - time.time())

    def propose(self, arguments: dict) -> dict:
        self.calls.append({"tool": "propose_send", "arguments": arguments})
        revises = arguments.get("revises") or {}
        revises_id = revises.get("proposalId") if isinstance(revises, dict) else None
        body = arguments.get("body")
        if not isinstance(body, str) or not arguments.get("to") or not arguments.get("subject"):
            return self._error("propose_send needs to, subject, and body")
        if self.phase == "idle":
            if revises_id:
                self.failures.append("revises on the first propose_send; nothing is open yet")
                return self._error("No open proposal to revise.")
            chosen = pins_for_body(body)
            if not chosen:
                return self._error("propose_send body has no passage to pin. Write a sentence.")
            self.body = body
            self.original_body = body
            self.pins = chosen
            self.accepted_at = time.time()
            self.phase = "awaiting"
            return {
                "status": "awaiting_user",
                "proposalId": self.proposal_id,
                "expiresAt": "2026-11-05T23:58:11Z",
                "message": (
                    "Waiting for human confirmation. "
                    "Call await_propose_send with this proposalId and hold it. "
                    "Pins arrive after a few seconds. Do not re-propose the same mail."
                ),
            }
        if self.phase in {"attention_delivered", "revised"}:
            if not revises_id:
                self.failures.append("new propose_send while a revision was expected")
                return self._error(
                    "This proposal is open. Call propose_send with revises.proposalId, "
                    "do not start another mail."
                )
            found = grade_revision(
                body,
                revises_id,
                self.proposal_id,
                pins=self.pins,
                original=self.original_body,
            )
            self.failures.extend(found)
            self.body = body
            self.phase = "revised"
            return {
                "status": "awaiting_user",
                "proposalId": self.proposal_id,
                "expiresAt": "2026-11-05T23:58:11Z",
                "message": (
                    "Updated the open confirm with this draft. "
                    "Call await_propose_send with the same proposalId."
                ),
            }
        return self._error("propose_send is not valid in this phase. Call await_propose_send.")

    def await_proposal(self, arguments: dict) -> dict:
        self.calls.append({"tool": "await_propose_send", "arguments": arguments})
        proposal_id = arguments.get("proposalId")
        if proposal_id != self.proposal_id or self.phase == "idle":
            return self._error("Unknown or expired propose_send proposalId.")
        if self.phase == "awaiting":
            if self.attention_wait_remaining() > 0:
                return {
                    "status": "awaiting_user",
                    "proposalId": self.proposal_id,
                    "message": (
                        "The user has not pinned passages yet. "
                        "Call await_propose_send again. Do not propose a new mail."
                    ),
                }
            self.phase = "attention_delivered"
            return attention_payload(self.proposal_id, self.pins)
        if self.phase == "attention_delivered":
            return {
                "status": "awaiting_user",
                "proposalId": self.proposal_id,
                "message": "Still waiting. Read the pins and propose_send with revises.proposalId.",
            }
        return {
            "status": "awaiting_user",
            "proposalId": self.proposal_id,
            "expiresAt": "2026-11-05T23:58:11Z",
            "message": "Revision is in the open confirm. Stop. The harness already graded it.",
        }

    def report(self) -> dict:
        return {
            "proposalId": self.proposal_id,
            "phase": self.phase,
            "passed": self.phase == "revised" and not self.failures,
            "failures": self.failures,
            "body": self.body,
            "originalBody": self.original_body,
            "pins": [
                {"id": pin["id"], "quote": pin["quote"], "note": pin["note"]}
                for pin in self.pins
            ],
        }

    @staticmethod
    def _error(message: str) -> dict:
        return {"isError": True, "message": message}


def mcp_call(url: str, bearer: str | None, method: str, params: dict, req_id: int) -> dict:
    payload = {"jsonrpc": "2.0", "id": req_id, "method": method, "params": params}
    headers = {"Content-Type": "application/json"}
    if bearer:
        headers["Authorization"] = f"Bearer {bearer}"
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=50) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {error.code}: {detail}") from error
    if not raw.strip():
        return {}
    return json.loads(raw)


def tool_result(rpc: dict) -> dict:
    if "error" in rpc:
        raise RuntimeError(json.dumps(rpc["error"]))
    result = rpc.get("result") or {}
    content = result.get("content") or []
    text = ""
    if content and isinstance(content[0], dict):
        text = content[0].get("text") or ""
    if result.get("isError"):
        raise RuntimeError(text or "tool error")
    parsed = json.loads(text) if text else {}
    if isinstance(parsed, dict) and parsed.get("isError"):
        raise RuntimeError(parsed.get("message") or text)
    return parsed

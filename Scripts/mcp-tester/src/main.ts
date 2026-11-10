import { invoke } from "@tauri-apps/api/core";
import { idChip, idPrefix, identiconNode, looksLikeIdKey } from "./identicon";

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };

interface McpTool {
  name: string;
  description: string;
  inputSchema: Json;
}

interface ConnectResult {
  serverInfo: Json;
  tools: McpTool[];
  initialize: Json;
}

interface CallResult {
  rpc: Json;
  payload: Json;
  isError: boolean;
  elapsedMs: number;
}

interface Defaults {
  url: string;
  bearer: string;
}

interface HistoryEntry {
  id: number;
  tool: string;
  arguments: Record<string, Json>;
  ok: boolean;
  preview: string;
  elapsedMs: number;
  payload: Json;
  rpc: Json;
  at: string; // ISO-8601
}

interface SessionExport {
  format: "mailgent-mcp-tester-session/v1";
  exportedAt: string;
  url: string;
  serverLabel: string;
  connected: boolean;
  summary: {
    total: number;
    passed: number;
    failed: number;
    ok: boolean;
    verdict: "PASS" | "FAIL" | "EMPTY";
  };
  calls: Array<{
    seq: number;
    at: string;
    tool: string;
    arguments: Record<string, Json>;
    ok: boolean;
    elapsedMs: number;
    preview: string;
    payload: Json;
    rpc: Json;
  }>;
}

interface MessageHit {
  accountID: string;
  placement: string;
  id: string;
  subject: string;
  from: string;
  date: string;
  raw: Record<string, Json>;
}

const SOFT_DEFAULTS: Record<string, number> = {
  await_ask: 25,
  await_propose_send: 60,
};

const HIT_LIST_TOOLS = new Set(["list", "search", "list_new"]);
const ID_FORM_KEYS = new Set(["accountID", "accountId", "id", "askId", "proposalId"]);

let tools: McpTool[] = [];
let selectedTool: string | null = null;
let connected = false;
let inFlight = false;
let history: HistoryEntry[] = [];
let historyId = 0;
let lastAskId: string | null = null;
let lastProposalId: string | null = null;
let syncingForm = false;
let showRawHits = false;
let lastRenderedTool: string | null = null;
let lastRenderedPayload: Json = null;

const el = {
  url: () => document.querySelector("#url") as HTMLInputElement,
  bearer: () => document.querySelector("#bearer") as HTMLInputElement,
  connect: () => document.querySelector("#connect") as HTMLButtonElement,
  connStatus: () => document.querySelector("#conn-status") as HTMLElement,
  toolFilter: () => document.querySelector("#tool-filter") as HTMLInputElement,
  toolList: () => document.querySelector("#tool-list") as HTMLUListElement,
  selectedTool: () => document.querySelector("#selected-tool") as HTMLElement,
  schemaForm: () => document.querySelector("#schema-form") as HTMLElement,
  argsJson: () => document.querySelector("#args-json") as HTMLTextAreaElement,
  call: () => document.querySelector("#call") as HTMLButtonElement,
  copy: () => document.querySelector("#copy-response") as HTMLButtonElement,
  response: () => document.querySelector("#response") as HTMLElement,
  callMeta: () => document.querySelector("#call-meta") as HTMLElement,
  history: () => document.querySelector("#history") as HTMLUListElement,
  historySummary: () => document.querySelector("#history-summary") as HTMLElement,
  exportSession: () => document.querySelector("#export-session") as HTMLButtonElement,
  copySession: () => document.querySelector("#copy-session") as HTMLButtonElement,
  clearHistory: () => document.querySelector("#clear-history") as HTMLButtonElement,
  exportStatus: () => document.querySelector("#export-status") as HTMLElement,
  idStrip: () => document.querySelector("#id-strip") as HTMLElement,
};

let serverLabel = "";
let persistTimer: number | null = null;

function pretty(value: Json): string {
  return JSON.stringify(value, null, 2);
}

function truncate(text: string, n = 96): string {
  const one = text.replace(/\s+/g, " ").trim();
  return one.length <= n ? one : `${one.slice(0, n - 1)}…`;
}

function parseArgs(): Record<string, Json> {
  const raw = el.argsJson().value.trim() || "{}";
  const parsed = JSON.parse(raw) as Json;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Arguments must be a JSON object");
  }
  return parsed as Record<string, Json>;
}

function setArgsObject(obj: Record<string, Json>) {
  syncingForm = true;
  el.argsJson().value = pretty(obj);
  syncingForm = false;
  rebuildSchemaForm();
  refreshIdStrip(obj);
}

function connection() {
  return {
    url: el.url().value.trim(),
    bearer: el.bearer().value.trim() || null,
  };
}

function setConnected(ok: boolean, message: string) {
  connected = ok;
  const status = el.connStatus();
  status.textContent = message;
  status.classList.toggle("ok", ok);
  status.classList.toggle("err", !ok && message !== "Not connected");
  el.toolFilter().disabled = !ok;
  el.call().disabled = !ok || !selectedTool || inFlight;
  document.querySelectorAll<HTMLButtonElement>("[data-shortcut]").forEach((btn) => {
    const name = btn.dataset.shortcut!;
    if (name === "await_ask") {
      btn.disabled = !ok || !lastAskId || inFlight;
    } else if (name === "await_propose_send") {
      btn.disabled = !ok || !lastProposalId || inFlight;
    } else if (name === "search") {
      btn.disabled = !ok || inFlight || !tools.some((t) => t.name === "search");
    } else {
      btn.disabled = !ok || inFlight || !tools.some((t) => t.name === name);
    }
  });
}

function setInFlight(next: boolean, label = "") {
  inFlight = next;
  el.connect().disabled = next;
  el.call().disabled = !connected || !selectedTool || next;
  el.call().textContent = next ? "Calling…" : "Call";
  el.callMeta().textContent = label;
  document.querySelectorAll<HTMLButtonElement>("[data-shortcut]").forEach((btn) => {
    btn.disabled = next || !connected;
  });
  if (!next) {
    setConnected(connected, el.connStatus().textContent || "");
  }
}

function renderTools() {
  const filter = el.toolFilter().value.trim().toLowerCase();
  const list = el.toolList();
  list.innerHTML = "";
  for (const tool of tools) {
    if (
      filter &&
      !tool.name.toLowerCase().includes(filter) &&
      !tool.description.toLowerCase().includes(filter)
    ) {
      continue;
    }
    const li = document.createElement("li");
    li.classList.toggle("active", tool.name === selectedTool);
    li.innerHTML = `<div class="tool-name">${escapeHtml(tool.name)}</div><div class="tool-desc">${escapeHtml(tool.description || "")}</div>`;
    li.addEventListener("click", () => selectTool(tool.name));
    list.appendChild(li);
  }
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function selectTool(name: string, seed?: Record<string, Json>) {
  selectedTool = name;
  el.selectedTool().textContent = name;
  const base: Record<string, Json> = seed ? { ...seed } : {};
  if (SOFT_DEFAULTS[name] != null && base.timeout == null) {
    base.timeout = SOFT_DEFAULTS[name];
  }
  if (name === "await_ask" && lastAskId && base.askId == null) {
    base.askId = lastAskId;
  }
  if (name === "await_propose_send" && lastProposalId && base.proposalId == null) {
    base.proposalId = lastProposalId;
  }
  setArgsObject(base);
  renderTools();
  el.call().disabled = !connected || inFlight;
  el.call().classList.add("primary");
}

function schemaProperties(
  tool: McpTool | undefined,
): Record<string, { type?: string; description?: string }> {
  const schema = tool?.inputSchema;
  if (!schema || typeof schema !== "object" || Array.isArray(schema)) return {};
  const props = (schema as { properties?: unknown }).properties;
  if (!props || typeof props !== "object" || Array.isArray(props)) return {};
  return props as Record<string, { type?: string; description?: string }>;
}

function rebuildSchemaForm() {
  const form = el.schemaForm();
  form.innerHTML = "";
  if (!selectedTool) return;
  const tool = tools.find((t) => t.name === selectedTool);
  const props = schemaProperties(tool);
  let args: Record<string, Json> = {};
  try {
    args = parseArgs();
  } catch {
    return;
  }

  for (const [key, def] of Object.entries(props)) {
    const type = Array.isArray(def.type) ? def.type[0] : def.type;
    if (type && !["string", "number", "integer", "boolean"].includes(type)) continue;

    const label = document.createElement("label");
    label.className = "field";
    const caption = document.createElement("span");
    caption.textContent = key;
    label.appendChild(caption);

    if (type === "boolean") {
      const input = document.createElement("input");
      input.type = "checkbox";
      input.checked = Boolean(args[key]);
      input.addEventListener("change", () => {
        const next = { ...parseSafeArgs(), [key]: input.checked };
        setArgsObject(next);
      });
      label.appendChild(input);
    } else {
      const row = document.createElement("div");
      row.className = "id-input-row";
      const showIcon = ID_FORM_KEYS.has(key) || looksLikeIdKey(key);
      let iconSlot: HTMLSpanElement | null = null;
      if (showIcon) {
        iconSlot = document.createElement("span");
        iconSlot.className = "id-input-icon";
        const val = args[key];
        if (typeof val === "string" && val) {
          iconSlot.appendChild(identiconNode(val, 18));
        } else {
          iconSlot.classList.add("empty");
        }
        row.appendChild(iconSlot);
      }
      const input = document.createElement("input");
      input.type = type === "number" || type === "integer" ? "number" : "text";
      const current = args[key];
      input.value = current == null ? "" : String(current);
      input.placeholder = def.description || "";
      input.addEventListener("input", () => {
        const next = { ...parseSafeArgs() };
        const raw = input.value;
        if (raw === "") {
          delete next[key];
        } else if (type === "number" || type === "integer") {
          next[key] = Number(raw);
        } else {
          next[key] = raw;
        }
        if (iconSlot) {
          iconSlot.innerHTML = "";
          if (raw) {
            iconSlot.appendChild(identiconNode(raw, 18));
            iconSlot.classList.remove("empty");
          } else {
            iconSlot.classList.add("empty");
          }
        }
        syncingForm = true;
        el.argsJson().value = pretty(next);
        syncingForm = false;
        refreshIdStrip(next);
      });
      row.appendChild(input);
      label.appendChild(row);
    }
    form.appendChild(label);
  }
}

function parseSafeArgs(): Record<string, Json> {
  try {
    return parseArgs();
  } catch {
    return {};
  }
}

function refreshIdStrip(args?: Record<string, Json>) {
  const strip = el.idStrip();
  strip.innerHTML = "";
  const obj = args ?? parseSafeArgs();
  const pairs: Array<[string, string]> = [];
  for (const key of ["accountID", "id", "askId", "proposalId"]) {
    const v = obj[key];
    if (typeof v === "string" && v) pairs.push([key, v]);
  }
  if (lastAskId && !pairs.some(([k]) => k === "askId")) {
    pairs.push(["askId (last)", lastAskId]);
  }
  if (!pairs.length) {
    strip.classList.add("empty");
    return;
  }
  strip.classList.remove("empty");
  for (const [label, value] of pairs) {
    const item = document.createElement("div");
    item.className = "id-strip-item";
    const name = document.createElement("span");
    name.className = "muted";
    name.textContent = label;
    item.appendChild(name);
    item.appendChild(idChip(value, idPrefix(value)));
    strip.appendChild(item);
  }
}

function rememberIds(payload: Json) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return;
  const obj = payload as Record<string, Json>;
  if (typeof obj.askId === "string") lastAskId = obj.askId;
  if (typeof obj.proposalId === "string") lastProposalId = obj.proposalId;
  refreshIdStrip();
}

function extractHits(payload: Json): MessageHit[] {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return [];
  const obj = payload as Record<string, Json>;
  const messages = obj.items ?? obj.messages ?? obj.results;
  if (!Array.isArray(messages)) return [];
  const hits: MessageHit[] = [];
  for (const m of messages) {
    if (!m || typeof m !== "object" || Array.isArray(m)) continue;
    const row = m as Record<string, Json>;
    const id = row.id ?? row.messageID ?? row.messageId;
    if (id == null) continue;
    hits.push({
      accountID: String(row.accountID ?? row.accountId ?? ""),
      placement: String(row.placement ?? ""),
      id: String(id),
      subject: String(row.subject ?? "(no subject)"),
      from: String(row.from ?? ""),
      date: String(row.date ?? ""),
      raw: row,
    });
  }
  return hits;
}

function showResponse(payload: Json, isError: boolean, toolName?: string | null, elapsedMs?: number) {
  lastRenderedPayload = payload;
  lastRenderedTool = toolName ?? selectedTool;
  el.copy().disabled = false;
  if (elapsedMs != null) {
    el.callMeta().textContent = `${elapsedMs} ms`;
  }

  const hits = !isError ? extractHits(payload) : [];
  const fromHitTool =
    (toolName && HIT_LIST_TOOLS.has(toolName)) ||
    (selectedTool != null && HIT_LIST_TOOLS.has(selectedTool)) ||
    hits.length > 0;

  if (fromHitTool && hits.length > 0 && !showRawHits) {
    renderHitList(hits, payload);
    return;
  }

  renderJsonResponse(payload, isError, toolName);
}

function renderJsonResponse(payload: Json, isError: boolean, toolName?: string | null) {
  const node = el.response();
  node.className = "response" + (isError ? " error" : "");
  node.textContent = "";

  if (
    !isError &&
    payload &&
    typeof payload === "object" &&
    !Array.isArray(payload) &&
    (payload as Record<string, Json>).status === "awaiting_user"
  ) {
    node.appendChild(renderAwaitingBanner(payload as Record<string, Json>));
  }

  const pre = document.createElement("pre");
  pre.className = "response-json";
  pre.textContent = pretty(payload);
  node.appendChild(pre);

  if (!isError && extractHits(payload).length > 0) {
    const toggle = document.createElement("button");
    toggle.type = "button";
    toggle.className = "linkish";
    toggle.textContent = "Show as hit list";
    toggle.addEventListener("click", () => {
      showRawHits = false;
      showResponse(payload, false, toolName);
    });
    node.prepend(toggle);
  }
}

function renderAwaitingBanner(payload: Record<string, Json>): HTMLElement {
  const ban = document.createElement("div");
  ban.className = "await-banner";
  const title = document.createElement("div");
  title.className = "await-title";
  title.textContent = "awaiting_user — compare IDs with the Ask dialog";
  ban.appendChild(title);

  const chips = document.createElement("div");
  chips.className = "await-chips";
  if (typeof payload.askId === "string") {
    const wrap = document.createElement("div");
    wrap.appendChild(document.createTextNode("askId "));
    wrap.appendChild(idChip(payload.askId));
    chips.appendChild(wrap);
  }
  if (typeof payload.accountID === "string") {
    const wrap = document.createElement("div");
    wrap.appendChild(document.createTextNode("account "));
    wrap.appendChild(idChip(payload.accountID));
    chips.appendChild(wrap);
  }
  if (typeof payload.id === "string" || typeof payload.messageID === "string") {
    const mid = String(payload.id ?? payload.messageID);
    const wrap = document.createElement("div");
    wrap.appendChild(document.createTextNode("message "));
    wrap.appendChild(idChip(mid));
    chips.appendChild(wrap);
  }
  if (typeof payload.placement === "string") {
    const wrap = document.createElement("div");
    wrap.className = "placement-pill";
    wrap.textContent = payload.placement;
    chips.appendChild(wrap);
  }
  ban.appendChild(chips);

  const actions = document.createElement("div");
  actions.className = "hit-actions";
  if (typeof payload.askId === "string") {
    const awaitBtn = document.createElement("button");
    awaitBtn.type = "button";
    awaitBtn.textContent = "Await ask";
    awaitBtn.addEventListener("click", () => {
      void fireAwaitAsk(payload.askId as string);
    });
    actions.appendChild(awaitBtn);
  }
  const reget = document.createElement("button");
  reget.type = "button";
  reget.className = "primary";
  reget.textContent = "Re-get";
  reget.addEventListener("click", () => {
    const accountID = String(payload.accountID ?? "");
    const placement = String(payload.placement ?? "");
    const id = String(payload.id ?? "");
    void fireGet({ accountID, placement, id });
  });
  actions.appendChild(reget);
  ban.appendChild(actions);
  return ban;
}

function renderHitList(hits: MessageHit[], payload: Json) {
  const node = el.response();
  node.className = "response hit-list";
  node.textContent = "";

  const header = document.createElement("div");
  header.className = "hit-list-header";
  const left = document.createElement("div");
  left.innerHTML = `<strong>${hits.length}</strong> <span class="muted">hits — Get fires immediately</span>`;
  header.appendChild(left);
  const right = document.createElement("div");
  right.className = "hit-list-header-actions";
  const rawBtn = document.createElement("button");
  rawBtn.type = "button";
  rawBtn.className = "linkish";
  rawBtn.textContent = "Raw JSON";
  rawBtn.addEventListener("click", () => {
    showRawHits = true;
    showResponse(payload, false, lastRenderedTool);
  });
  right.appendChild(rawBtn);
  header.appendChild(right);
  node.appendChild(header);

  if (
    payload &&
    typeof payload === "object" &&
    !Array.isArray(payload) &&
    typeof (payload as Record<string, Json>).nextCursor === "string"
  ) {
    const cursor = document.createElement("div");
    cursor.className = "muted hit-cursor";
    cursor.textContent = `nextCursor: ${(payload as Record<string, Json>).nextCursor}`;
    node.appendChild(cursor);
  }

  for (const hit of hits) {
    node.appendChild(buildHitRow(hit));
  }
}

function buildHitRow(hit: MessageHit): HTMLElement {
  const row = document.createElement("div");
  row.className = "hit-row";

  const icons = document.createElement("div");
  icons.className = "hit-icons";
  icons.appendChild(identiconNode(hit.accountID || "?", 22));
  icons.appendChild(identiconNode(hit.id || "?", 22));
  row.appendChild(icons);

  const body = document.createElement("div");
  body.className = "hit-body";
  const subject = document.createElement("div");
  subject.className = "hit-subject";
  subject.textContent = hit.subject;
  body.appendChild(subject);

  const meta = document.createElement("div");
  meta.className = "hit-meta";
  meta.appendChild(idChip(hit.accountID));
  const place = document.createElement("span");
  place.className = "placement-pill";
  place.textContent = hit.placement || "?";
  meta.appendChild(place);
  meta.appendChild(idChip(hit.id, hit.id));
  if (hit.from) {
    const from = document.createElement("span");
    from.className = "muted";
    from.textContent = hit.from;
    meta.appendChild(from);
  }
  if (hit.date) {
    const date = document.createElement("span");
    date.className = "muted";
    date.textContent = hit.date;
    meta.appendChild(date);
  }
  body.appendChild(meta);
  row.appendChild(body);

  const actions = document.createElement("div");
  actions.className = "hit-actions";
  const getBtn = document.createElement("button");
  getBtn.type = "button";
  getBtn.className = "primary";
  getBtn.textContent = "Get";
  getBtn.title = "Call get with this account / placement / id";
  getBtn.addEventListener("click", (ev) => {
    ev.stopPropagation();
    void fireGet(hit);
  });
  const fillBtn = document.createElement("button");
  fillBtn.type = "button";
  fillBtn.textContent = "Fill";
  fillBtn.title = "Only fill get args";
  fillBtn.addEventListener("click", (ev) => {
    ev.stopPropagation();
    selectTool("get", {
      accountID: hit.accountID,
      placement: hit.placement,
      id: hit.id,
    });
  });
  const openBtn = document.createElement("button");
  openBtn.type = "button";
  openBtn.textContent = "Open";
  openBtn.title = "Call open_in_mail";
  openBtn.addEventListener("click", (ev) => {
    ev.stopPropagation();
    void fireOpen(hit);
  });
  actions.appendChild(getBtn);
  actions.appendChild(fillBtn);
  actions.appendChild(openBtn);
  row.appendChild(actions);

  row.addEventListener("dblclick", () => void fireGet(hit));
  return row;
}

async function fireGet(hit: { accountID: string; placement: string; id: string }) {
  const args = {
    accountID: hit.accountID,
    placement: hit.placement,
    id: hit.id,
  };
  selectTool("get", args);
  await callTool("get", args);
}

async function fireOpen(hit: { accountID: string; placement: string; id: string }) {
  const args = {
    accountID: hit.accountID,
    placement: hit.placement,
    id: hit.id,
  };
  selectTool("open_in_mail", args);
  await callTool("open_in_mail", args);
}

async function fireAwaitAsk(askId: string) {
  const args = { askId, timeout: SOFT_DEFAULTS.await_ask };
  selectTool("await_ask", args);
  await callTool("await_ask", args);
}

function pushHistory(entry: Omit<HistoryEntry, "id" | "at">) {
  const full: HistoryEntry = {
    ...entry,
    id: ++historyId,
    at: new Date().toISOString(),
  };
  history.unshift(full);
  history = history.slice(0, 50);
  renderHistory(full.id);
  schedulePersist();
}

function historySummary() {
  const total = history.length;
  const failed = history.filter((h) => !h.ok).length;
  const passed = total - failed;
  const verdict: SessionExport["summary"]["verdict"] =
    total === 0 ? "EMPTY" : failed === 0 ? "PASS" : "FAIL";
  return {
    total,
    passed,
    failed,
    ok: total > 0 && failed === 0,
    verdict,
  };
}

function buildSessionExport(): SessionExport {
  const chronological = [...history].reverse();
  return {
    format: "mailgent-mcp-tester-session/v1",
    exportedAt: new Date().toISOString(),
    url: el.url().value.trim(),
    serverLabel,
    connected,
    summary: historySummary(),
    calls: chronological.map((item, i) => ({
      seq: i + 1,
      at: item.at,
      tool: item.tool,
      arguments: item.arguments,
      ok: item.ok,
      elapsedMs: item.elapsedMs,
      preview: item.preview,
      payload: item.payload,
      rpc: item.rpc,
    })),
  };
}

function sessionJson(): string {
  return JSON.stringify(buildSessionExport(), null, 2);
}

function schedulePersist() {
  if (persistTimer != null) window.clearTimeout(persistTimer);
  persistTimer = window.setTimeout(() => {
    persistTimer = null;
    void persistSession(false);
  }, 400);
}

async function persistSession(stamp: boolean): Promise<string | null> {
  const json = sessionJson();
  const stampName = stamp
    ? `session-${new Date().toISOString().replace(/[:.]/g, "-")}.json`
    : null;
  try {
    const path = await invoke<string>("save_session_export", {
      json,
      stampName,
    });
    const s = historySummary();
    el.exportStatus().textContent = stamp
      ? `Exported ${s.verdict} → ${path}`
      : `Auto-saved ${s.verdict} (${s.passed}/${s.total} ok)`;
    return path;
  } catch (err) {
    el.exportStatus().textContent = `Export failed: ${err}`;
    return null;
  }
}

async function exportSession() {
  const path = await persistSession(true);
  if (path) {
    try {
      await navigator.clipboard.writeText(sessionJson());
    } catch {
      /* clipboard optional */
    }
  }
}

async function copySessionLog() {
  const json = sessionJson();
  await navigator.clipboard.writeText(json);
  const s = historySummary();
  el.exportStatus().textContent = `Copied ${s.verdict} log (${s.total} calls)`;
  void persistSession(false);
}

function clearHistory() {
  history = [];
  historyId = 0;
  renderHistory();
  el.response().textContent = "History cleared.";
  el.callMeta().textContent = "";
  schedulePersist();
}

function renderHistory(activeId?: number) {
  const list = el.history();
  list.innerHTML = "";
  const s = historySummary();
  el.historySummary().textContent =
    s.total === 0 ? "" : `${s.verdict} · ${s.passed}/${s.total}`;
  el.historySummary().classList.toggle("fail", s.verdict === "FAIL");
  el.historySummary().classList.toggle("pass", s.verdict === "PASS");

  for (const item of history) {
    const li = document.createElement("li");
    li.classList.toggle("error", !item.ok);
    li.classList.toggle("active", item.id === activeId);
    const title = document.createElement("div");
    title.className = "tool-name";
    const clock = new Date(item.at).toLocaleTimeString();
    title.textContent = `${item.ok ? "✓" : "✗"} ${item.tool} · ${item.elapsedMs}ms · ${clock}`;
    li.appendChild(title);

    const hits = extractHits(item.payload);
    if (hits.length > 0) {
      const preview = document.createElement("div");
      preview.className = "history-preview history-hits";
      const first = hits[0];
      preview.appendChild(identiconNode(first.accountID || "?", 12));
      preview.appendChild(identiconNode(first.id || "?", 12));
      const label = document.createElement("span");
      label.textContent = `${hits.length} hits · ${truncate(first.subject, 40)}`;
      preview.appendChild(label);
      li.appendChild(preview);
    } else {
      const preview = document.createElement("div");
      preview.className = "history-preview";
      if (item.payload && typeof item.payload === "object" && !Array.isArray(item.payload)) {
        const p = item.payload as Record<string, Json>;
        if (typeof p.askId === "string") {
          const row = document.createElement("div");
          row.className = "history-hits";
          row.appendChild(identiconNode(p.askId, 12));
          row.appendChild(document.createTextNode(truncate(item.preview, 60)));
          preview.appendChild(row);
        } else {
          preview.textContent = item.preview;
        }
      } else {
        preview.textContent = item.preview;
      }
      li.appendChild(preview);
    }

    li.addEventListener("click", () => {
      showRawHits = false;
      showResponse(item.payload, !item.ok, item.tool, item.elapsedMs);
      renderHistory(item.id);
    });
    list.appendChild(li);
  }
}

async function connect() {
  const { url, bearer } = connection();
  if (!url) {
    setConnected(false, "URL required");
    return;
  }
  setInFlight(true, "Connecting…");
  try {
    const result = await invoke<ConnectResult>("mcp_connect", { url, bearer });
    tools = (result.tools || []).map((t) => ({
      name: t.name,
      description: t.description || "",
      inputSchema: t.inputSchema ?? { type: "object" },
    }));
    tools.sort((a, b) => a.name.localeCompare(b.name));
    const info = result.serverInfo as { name?: string; version?: string } | null;
    const label = info?.name
      ? `${info.name}${info.version ? ` ${info.version}` : ""} · ${tools.length} tools`
      : `Connected · ${tools.length} tools`;
    serverLabel = label;
    setConnected(true, label);
    if (!selectedTool && tools.length) {
      selectTool(tools[0].name);
    } else {
      renderTools();
      rebuildSchemaForm();
    }
    showResponse(result.initialize, false, "initialize");
  } catch (err) {
    setConnected(false, String(err));
    showResponse({ error: String(err) }, true);
  } finally {
    setInFlight(false);
  }
}

async function callTool(name: string, argumentsObj: Record<string, Json>) {
  const { url, bearer } = connection();
  const soft =
    typeof argumentsObj.timeout === "number" ? argumentsObj.timeout : SOFT_DEFAULTS[name];
  const timeoutSecs = soft != null ? Math.max(35, Number(soft) + 10) : 35;
  const started = performance.now();
  setInFlight(true, "0.0s");
  const tick = window.setInterval(() => {
    el.callMeta().textContent = `${((performance.now() - started) / 1000).toFixed(1)}s`;
  }, 100);

  try {
    showRawHits = false;
    const result = await invoke<CallResult>("mcp_call", {
      url,
      bearer,
      name,
      arguments: argumentsObj,
      timeoutSecs,
    });
    rememberIds(result.payload);
    showResponse(result.payload, result.isError, name, result.elapsedMs);
    pushHistory({
      tool: name,
      arguments: argumentsObj,
      ok: !result.isError,
      preview: truncate(pretty(result.payload)),
      elapsedMs: result.elapsedMs,
      payload: result.payload,
      rpc: result.rpc,
    });
  } catch (err) {
    const payload = { error: String(err) };
    showResponse(payload, true, name, Math.round(performance.now() - started));
    pushHistory({
      tool: name,
      arguments: argumentsObj,
      ok: false,
      preview: truncate(String(err)),
      elapsedMs: Math.round(performance.now() - started),
      payload,
      rpc: null,
    });
  } finally {
    window.clearInterval(tick);
    setInFlight(false);
  }
}

async function onCall() {
  if (!selectedTool) return;
  let args: Record<string, Json>;
  try {
    args = parseArgs();
  } catch (err) {
    showResponse({ error: String(err) }, true);
    return;
  }
  await callTool(selectedTool, args);
}

async function onShortcut(name: string) {
  if (name === "await_ask") {
    if (!lastAskId) return;
    await fireAwaitAsk(lastAskId);
    return;
  }
  if (name === "await_propose_send") {
    if (!lastProposalId) return;
    const args = {
      proposalId: lastProposalId,
      timeout: SOFT_DEFAULTS.await_propose_send,
    };
    selectTool("await_propose_send", args);
    await callTool("await_propose_send", args);
    return;
  }
  if (name === "propose_send") {
    const args: Record<string, Json> = {
      to: "alex@example.com",
      subject: "Envelope dogfood",
      body: "Hello from mcp-tester",
    };
    selectTool("propose_send", args);
    await callTool("propose_send", args);
    return;
  }
  if (name === "search") {
    const q = window.prompt("search query", "");
    if (q == null) return;
    const args = { query: q };
    selectTool("search", args);
    await callTool("search", args);
    return;
  }
  selectTool(name, {});
  await callTool(name, {});
}

window.addEventListener("DOMContentLoaded", async () => {
  try {
    const defaults = await invoke<Defaults>("get_defaults");
    el.url().value = defaults.url;
    el.bearer().value = defaults.bearer;
  } catch {
    el.url().value = "http://127.0.0.1:8788/mcp";
  }

  el.connect().addEventListener("click", () => void connect());
  el.call().addEventListener("click", () => void onCall());
  el.copy().addEventListener("click", async () => {
    const text =
      lastRenderedPayload != null ? pretty(lastRenderedPayload) : el.response().textContent || "";
    await navigator.clipboard.writeText(text);
  });
  el.toolFilter().addEventListener("input", renderTools);
  el.argsJson().addEventListener("input", () => {
    if (!syncingForm) {
      rebuildSchemaForm();
      refreshIdStrip();
    }
  });
  document.querySelectorAll<HTMLButtonElement>("[data-shortcut]").forEach((btn) => {
    btn.addEventListener("click", () => void onShortcut(btn.dataset.shortcut!));
  });
  el.exportSession().addEventListener("click", () => void exportSession());
  el.copySession().addEventListener("click", () => void copySessionLog());
  el.clearHistory().addEventListener("click", clearHistory);

  el.call().classList.add("primary");
  setConnected(false, "Not connected");
  refreshIdStrip();
  renderHistory();
});

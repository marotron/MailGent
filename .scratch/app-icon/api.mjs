#!/usr/bin/env node
/**
 * MailGent icon tweaker — localhost API + CLI.
 * Bind 127.0.0.1 only. Writes under .scratch/app-icon/ only.
 *
 *   node .scratch/app-icon/api.mjs
 *   open http://127.0.0.1:8765/
 */
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import * as engine from "./engine.mjs";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const CAND = path.join(DIR, "candidates");
const PICK = path.join(DIR, "pick.json");
const HOST = "127.0.0.1";
const PORT = Number(process.env.PORT) || 8765;

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".json": "application/json; charset=utf-8",
  ".md": "text/markdown; charset=utf-8",
  ".zip": "application/zip",
};

function json(res, code, body) {
  const raw = JSON.stringify(body, null, 2);
  res.writeHead(code, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(raw);
}

function text(res, code, body, type = "text/plain; charset=utf-8") {
  res.writeHead(code, { "content-type": type, "cache-control": "no-store" });
  res.end(body);
}

async function readJson(req) {
  const chunks = [];
  let n = 0;
  for await (const c of req) {
    n += c.length;
    if (n > 1_000_000) throw new Error("body too large");
    chunks.push(c);
  }
  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) return {};
  return JSON.parse(raw);
}

function resolveState(body = {}) {
  const base = body.state || body.base || engine.slimState(engine.defaults());
  let state = engine.hydrate(base);
  if (body.patch) state = engine.applyPatch(state, body.patch);
  return state;
}

function rasterize(svgPath, pngPath) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "mailgent-icon-"));
  const r = spawnSync("qlmanage", ["-t", "-s", "1024", "-o", tmp, svgPath], { encoding: "utf8" });
  const produced = fs.existsSync(tmp) ? fs.readdirSync(tmp).find((f) => f.endsWith(".png")) : null;
  if (r.status !== 0 || !produced) {
    fs.rmSync(tmp, { recursive: true, force: true });
    throw new Error(`qlmanage failed: ${r.stderr || r.stdout || "no png"}`);
  }
  fs.copyFileSync(path.join(tmp, produced), pngPath);
  fs.rmSync(tmp, { recursive: true, force: true });
}

function saveCandidate({ slug, state, note = "" }) {
  fs.mkdirSync(CAND, { recursive: true });
  const id = engine.candidateId(slug);
  const svg = engine.buildSvg(state);
  const templateSvg = engine.buildSvg(state, { appearance: "template" });
  const jsonPath = path.join(CAND, `${id}.json`);
  const svgPath = path.join(CAND, `${id}.svg`);
  const templatePath = path.join(CAND, `${id}-template.svg`);
  const pngPath = path.join(CAND, `${id}.png`);
  const templatePng = path.join(CAND, `${id}-template.png`);
  fs.writeFileSync(svgPath, svg);
  fs.writeFileSync(templatePath, templateSvg);
  fs.writeFileSync(jsonPath, JSON.stringify(engine.packVersion({ slug: id, state, note }), null, 2));
  let pngError = null;
  try { rasterize(svgPath, pngPath); } catch (e) { pngError = String(e.message); }
  try { rasterize(templatePath, templatePng); } catch (e) { pngError = pngError || String(e.message); }
  return {
    slug: id,
    note,
    pngError,
    files: {
      svg: `.scratch/app-icon/candidates/${id}.svg`,
      png: fs.existsSync(pngPath) ? `.scratch/app-icon/candidates/${id}.png` : null,
      templateSvg: `.scratch/app-icon/candidates/${id}-template.svg`,
      templatePng: fs.existsSync(templatePng) ? `.scratch/app-icon/candidates/${id}-template.png` : null,
      json: `.scratch/app-icon/candidates/${id}.json`,
    },
  };
}

function listCandidates() {
  if (!fs.existsSync(CAND)) return [];
  const names = fs.readdirSync(CAND).filter((f) => f.endsWith(".json") && !f.endsWith("-SHIP.md"));
  return names.map((f) => {
    const slug = f.replace(/\.json$/, "");
    const has = (ext) => fs.existsSync(path.join(CAND, slug + ext));
    let note = "";
    try {
      note = JSON.parse(fs.readFileSync(path.join(CAND, f), "utf8")).note || "";
    } catch { /* ignore */ }
    return {
      slug,
      note,
      hasPng: has(".png"),
      hasTemplate: has("-template.svg"),
      pngUrl: has(".png") ? `/candidates/${slug}.png` : null,
      templateUrl: has("-template.svg") ? `/candidates/${slug}-template.svg` : `/api/render-file?slug=${encodeURIComponent(slug)}&appearance=template`,
    };
  }).sort((a, b) => b.slug.localeCompare(a.slug));
}

function loadCandidate(slug) {
  const id = engine.sanitizeSlug(slug);
  const jsonPath = path.join(CAND, `${id}.json`);
  if (!fs.existsSync(jsonPath)) return null;
  const loaded = engine.unpackVersion(fs.readFileSync(jsonPath, "utf8"));
  return { slug: id, note: loaded.note || "", state: loaded.state, slim: engine.slimState(loaded.state) };
}

function writePick({ slug, intent, note, state }) {
  const record = engine.pickRecord({ slug, intent, note, state });
  const brief = engine.shipBrief({ slug, intent, note, state });
  fs.writeFileSync(PICK, JSON.stringify(record, null, 2));
  fs.writeFileSync(path.join(CAND, `${slug}-SHIP.md`), brief);
  return { pick: record, brief };
}

function packZip(slug) {
  const loaded = loadCandidate(slug);
  if (!loaded) throw new Error("unknown slug");
  const briefPath = path.join(CAND, `${loaded.slug}-SHIP.md`);
  if (!fs.existsSync(briefPath)) {
    fs.writeFileSync(briefPath, engine.shipBrief({ slug: loaded.slug, intent: "favorite", note: loaded.note, state: loaded.state }));
  }
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "mailgent-pack-"));
  const folder = path.join(tmp, loaded.slug);
  fs.mkdirSync(folder);
  for (const name of [
    `${loaded.slug}.svg`,
    `${loaded.slug}.png`,
    `${loaded.slug}-template.svg`,
    `${loaded.slug}-template.png`,
    `${loaded.slug}.json`,
    `${loaded.slug}-SHIP.md`,
  ]) {
    const src = path.join(CAND, name);
    if (fs.existsSync(src)) fs.copyFileSync(src, path.join(folder, name));
  }
  const zipPath = path.join(tmp, `${loaded.slug}-pack.zip`);
  const r = spawnSync("ditto", ["-c", "-k", "--norsrc", "--noextattr", folder, zipPath], { encoding: "utf8" });
  if (r.status !== 0 || !fs.existsSync(zipPath)) {
    fs.rmSync(tmp, { recursive: true, force: true });
    throw new Error(`zip failed: ${r.stderr || r.stdout || "ditto"}`);
  }
  const buf = fs.readFileSync(zipPath);
  fs.rmSync(tmp, { recursive: true, force: true });
  return { filename: `${loaded.slug}-pack.zip`, buf };
}

function safeCandidateFile(name) {
  if (!/^[a-z0-9][a-z0-9._-]*\.(svg|png|json|md)$/i.test(name)) return null;
  const resolved = path.resolve(CAND, name);
  if (!resolved.startsWith(CAND + path.sep)) return null;
  if (!fs.existsSync(resolved)) return null;
  return resolved;
}

async function handleApi(req, res, url) {
  const p = url.pathname;
  if (p === "/api/health" && req.method === "GET") {
    return json(res, 200, { ok: true, port: PORT });
  }
  if (p === "/api/schema" && req.method === "GET") {
    return json(res, 200, engine.apiSchema());
  }
  if (p === "/api/defaults" && req.method === "GET") {
    const state = engine.defaults();
    return json(res, 200, { state: engine.slimState(state), svg: engine.buildSvg(state), templateSvg: engine.buildSvg(state, { appearance: "template" }) });
  }
  if (p === "/api/render" && req.method === "POST") {
    const body = await readJson(req);
    const state = resolveState(body);
    const appearance = body.appearance === "template" ? "template" : "color";
    return json(res, 200, {
      state: engine.slimState(state),
      appearance,
      svg: engine.buildSvg(state, { appearance }),
      templateSvg: engine.buildSvg(state, { appearance: "template" }),
    });
  }
  if (p === "/api/save" && req.method === "POST") {
    const body = await readJson(req);
    if (!body.slug) throw new Error("slug required");
    const saved = saveCandidate({ slug: body.slug, state: resolveState(body), note: body.note || "" });
    return json(res, 200, saved);
  }
  if (p === "/api/variants" && req.method === "POST") {
    const body = await readJson(req);
    const expanded = engine.expandVariants({
      base: body.base || body.state,
      palettes: body.palettes,
      envelopes: body.envelopes,
      variants: body.variants,
    });
    const saved = expanded.map((v) => saveCandidate({ slug: v.slug, state: v.state, note: v.note }));
    return json(res, 200, { count: saved.length, candidates: saved });
  }
  if (p === "/api/candidates" && req.method === "GET") {
    return json(res, 200, { candidates: listCandidates() });
  }
  if (p.startsWith("/api/candidates/") && req.method === "GET") {
    const slug = decodeURIComponent(p.slice("/api/candidates/".length));
    const loaded = loadCandidate(slug);
    if (!loaded) return json(res, 404, { error: "unknown slug" });
    return json(res, 200, {
      ...loaded,
      svg: engine.buildSvg(loaded.state),
      templateSvg: engine.buildSvg(loaded.state, { appearance: "template" }),
    });
  }
  if (p === "/api/pick" && req.method === "GET") {
    if (!fs.existsSync(PICK)) {
      res.writeHead(204);
      return res.end();
    }
    return json(res, 200, JSON.parse(fs.readFileSync(PICK, "utf8")));
  }
  if (p === "/api/pick" && req.method === "POST") {
    const body = await readJson(req);
    if (!body.slug) throw new Error("slug required");
    const loaded = loadCandidate(body.slug);
    if (!loaded) throw new Error("save the candidate first");
    const intent = body.intent === "ship" ? "ship" : "favorite";
    return json(res, 200, writePick({ slug: loaded.slug, intent, note: body.note || loaded.note, state: loaded.state }));
  }
  if (p.startsWith("/api/ship/") && req.method === "GET") {
    const slug = decodeURIComponent(p.slice("/api/ship/".length));
    const loaded = loadCandidate(slug);
    if (!loaded) return json(res, 404, { error: "unknown slug" });
    const brief = engine.shipBrief({ slug: loaded.slug, intent: "ship", note: loaded.note, state: loaded.state });
    return text(res, 200, brief, "text/markdown; charset=utf-8");
  }
  if (p.startsWith("/api/pack/") && req.method === "GET") {
    const slug = decodeURIComponent(p.slice("/api/pack/".length));
    const { filename, buf } = packZip(slug);
    res.writeHead(200, {
      "content-type": "application/zip",
      "content-disposition": `attachment; filename="${filename}"`,
    });
    return res.end(buf);
  }
  return json(res, 404, { error: "unknown endpoint", schema: "/api/schema" });
}

function serveStatic(res, filePath) {
  const ext = path.extname(filePath);
  const data = fs.readFileSync(filePath);
  res.writeHead(200, { "content-type": MIME[ext] || "application/octet-stream", "cache-control": "no-store" });
  res.end(data);
}

function serve() {
  fs.mkdirSync(CAND, { recursive: true });
  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, `http://${HOST}:${PORT}`);
      if (url.pathname.startsWith("/api/")) return await handleApi(req, res, url);
      if (url.pathname.startsWith("/candidates/")) {
        const name = decodeURIComponent(url.pathname.slice("/candidates/".length));
        const file = safeCandidateFile(name);
        if (!file) return json(res, 404, { error: "not found" });
        return serveStatic(res, file);
      }
      if (url.pathname === "/" || url.pathname === "/tweaker.html") {
        return serveStatic(res, path.join(DIR, "tweaker.html"));
      }
      if (url.pathname === "/engine.mjs") {
        return serveStatic(res, path.join(DIR, "engine.mjs"));
      }
      json(res, 404, { error: "not found" });
    } catch (e) {
      json(res, 400, { error: String(e.message || e) });
    }
  });
  server.listen(PORT, HOST, () => {
    console.log(`MailGent icon tweaker  http://${HOST}:${PORT}/`);
    console.log(`API schema             http://${HOST}:${PORT}/api/schema`);
  });
}

function arg(flag, rest) {
  const i = rest.indexOf(flag);
  if (i < 0) return null;
  return rest[i + 1] ?? "";
}

function readStateArg(rest) {
  const p = arg("--state", rest);
  if (!p) return engine.slimState(engine.defaults());
  const raw = p === "-" ? fs.readFileSync(0, "utf8") : fs.readFileSync(p, "utf8");
  return engine.slimState(engine.unpackVersion(raw).state);
}

function cli(argv) {
  const [cmd = "serve", ...rest] = argv;
  if (cmd === "serve" || cmd === "help" || cmd === "-h" || cmd === "--help") {
    if (cmd !== "serve") {
      console.log(`Usage:
  node .scratch/app-icon/api.mjs serve
  node .scratch/app-icon/api.mjs render [--appearance color|template] [--state file|-]
  node .scratch/app-icon/api.mjs save --slug NAME [--state file] [--note TEXT]
  node .scratch/app-icon/api.mjs load FILE.json [--slug NAME]
  node .scratch/app-icon/api.mjs variants --palettes all|dusk,forest [--envelopes shadow-only]
  node .scratch/app-icon/api.mjs list
  node .scratch/app-icon/api.mjs pick SLUG [--intent ship|favorite]
  node .scratch/app-icon/api.mjs brief SLUG
  node .scratch/app-icon/api.mjs pack SLUG
`);
      return;
    }
    return serve();
  }
  if (cmd === "render") {
    const state = engine.hydrate(readStateArg(rest));
    const appearance = arg("--appearance", rest) === "template" ? "template" : "color";
    process.stdout.write(engine.buildSvg(state, { appearance }));
    return;
  }
  if (cmd === "save") {
    const slug = arg("--slug", rest);
    if (!slug) throw new Error("--slug required");
    const out = saveCandidate({ slug, state: engine.hydrate(readStateArg(rest)), note: arg("--note", rest) || "" });
    console.log(JSON.stringify(out, null, 2));
    return;
  }
  if (cmd === "load") {
    const file = rest.find((s) => !s.startsWith("--") && s !== "load") || arg("--file", rest);
    if (!file) throw new Error("path to version json required");
    const loaded = engine.unpackVersion(fs.readFileSync(file, "utf8"));
    const slug = arg("--slug", rest) || loaded.slug || "loaded";
    const out = saveCandidate({ slug, state: loaded.state, note: loaded.note || "" });
    console.log(JSON.stringify(out, null, 2));
    return;
  }
  if (cmd === "variants") {
    const palRaw = arg("--palettes", rest) || "all";
    const palettes = palRaw === "all" ? "all" : palRaw.split(",").map((s) => s.trim()).filter(Boolean);
    const envRaw = arg("--envelopes", rest);
    const envelopes = envRaw ? envRaw.split(",").map((s) => s.trim()).filter(Boolean) : undefined;
    const expanded = engine.expandVariants({
      base: readStateArg(rest),
      palettes,
      envelopes,
    });
    const saved = expanded.map((v) => saveCandidate({ slug: v.slug, state: v.state, note: v.note }));
    console.log(JSON.stringify({ count: saved.length, candidates: saved }, null, 2));
    return;
  }
  if (cmd === "list") {
    console.log(JSON.stringify({ candidates: listCandidates() }, null, 2));
    return;
  }
  if (cmd === "pick") {
    const slug = rest.find((s) => !s.startsWith("--")) || arg("--slug", rest);
    if (!slug) throw new Error("slug required");
    const loaded = loadCandidate(slug);
    if (!loaded) throw new Error("unknown slug — save first");
    const intent = arg("--intent", rest) === "favorite" ? "favorite" : "ship";
    console.log(JSON.stringify(writePick({ slug: loaded.slug, intent, note: loaded.note, state: loaded.state }), null, 2));
    return;
  }
  if (cmd === "brief") {
    const slug = rest.find((s) => !s.startsWith("--"));
    const loaded = loadCandidate(slug);
    if (!loaded) throw new Error("unknown slug");
    process.stdout.write(engine.shipBrief({ slug: loaded.slug, intent: "ship", note: loaded.note, state: loaded.state }));
    return;
  }
  if (cmd === "pack") {
    const slug = rest.find((s) => !s.startsWith("--"));
    const { filename, buf } = packZip(slug);
    const dest = path.join(CAND, filename);
    fs.writeFileSync(dest, buf);
    console.log(dest);
    return;
  }
  throw new Error(`unknown command ${cmd}`);
}

const argv = process.argv.slice(2);
try {
  if (argv.length === 0) serve();
  else cli(argv);
} catch (e) {
  console.error(e.message || e);
  process.exit(1);
}

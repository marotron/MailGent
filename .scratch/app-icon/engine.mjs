/** Shared MailGent icon tweaker engine. Browser + Node. No fs. */

export const KEYLINE = 824 / 712;
export const SCHEMA = 1;
export const LAYER_IDS = [
  "plate", "overcast", "body", "flap", "bowl", "field",
  "sparkleLg", "sparkleMid", "sparkleSm",
];
export const SPARKLE_IDS = ["sparkleLg", "sparkleMid", "sparkleSm"];
export const PULSE_LAYER_IDS = LAYER_IDS.filter((id) => id !== "plate");

export const ICONSET_SLOTS = [
  ["icon_16x16.png", 16],
  ["icon_16x16_2x.png", 32],
  ["icon_32x32.png", 32],
  ["icon_32x32_2x.png", 64],
  ["icon_128x128.png", 128],
  ["icon_128x128_2x.png", 256],
  ["icon_256x256.png", 256],
  ["icon_256x256_2x.png", 512],
  ["icon_512x512.png", 512],
  ["icon_512x512_2x.png", 1024],
];

export const PATHS = {
  overcast: "M235.9,378.9 L788.1,378.9 A49.2,49.2 0 0 1 837.3,428.2 L837.3,766.3 A49.2,49.2 0 0 1 788.1,815.5 L235.9,815.5 A49.2,49.2 0 0 1 186.7,766.3 L186.7,428.2 A49.2,49.2 0 0 1 235.9,378.9 Z",
  body: "M254,372 L770,372 A46,46 0 0 1 816,418 L816,734 A46,46 0 0 1 770,780 L254,780 A46,46 0 0 1 208,734 L208,418 A46,46 0 0 1 254,372 Z",
  flap: "M224.1,372 L512,598 L799.9,372 Z",
  bowl: "M243,472 L244,532 L248,563 L256,596 L262,615 L275,646 L294,681 L310,705 L339,740 L369,769 L396,791 L446,824 L473,839 L511,857 L513,857 L546,842 L579,824 L630,790 L660,765 L687,738 L718,699 L737,669 L752,639 L762,614 L771,584 L777,555 L780,527 L780,472 L513,671 L510,671 L244,472 Z",
  field: "M512,179 L534,199 L566,222 L588,235 L632,256 L666,268 L695,276 L738,284 L780,288 L780,398 L512,598 L243,398 L243,288 L285,284 L320,278 L364,266 L394,255 L428,239 L454,224 L480,206 L511,179 Z",
  sparkleLg: "M459.8,236.8 C471.4,366.5 471.4,366.5 585.8,380.8 C471.4,389 471.4,389 459.8,516.8 C451.4,388.4 451.4,388.4 335.8,374.8 C451.4,366 451.4,366 459.8,236.8 Z",
  sparkleMid: "M565.5,384.5 C573.5,454.7 573.5,454.7 641.5,458.5 C573.5,467.1 573.5,467.1 565.5,538.5 C561.7,466.9 561.7,466.9 493.5,456.5 C561.7,454.5 561.7,454.5 565.5,384.5 Z",
  sparkleSm: "M599,324.2 C606,371.2 606,371.2 655,372.2 C606.2,379.5 606.2,379.5 601,428.2 C597.8,380 597.8,380 549,378.2 C597.6,371.6 597.6,371.6 599,324.2 Z",
};

export const PALETTES = {
  "after-tweaks": {
    label: "After tweaks (slate)",
    c0: "#4B617F", c1: "#7A8EAA", angle: 0,
    cream: "#F8EED8", cream1: "#E4D4B4", overcast: "#3D4C5F",
  },
  dusk: {
    label: "Dusk (blue → violet)",
    c0: "#2F6BB5", c1: "#5A2D8C", angle: 135,
    cream: "#F4EFE6", cream1: "#E2D4C0", overcast: "#1E2A4A",
  },
  midnight: {
    label: "Midnight",
    c0: "#1B2838", c1: "#3D5A80", angle: 0,
    cream: "#EDE6D6", cream1: "#D9CDB6", overcast: "#0F1722",
  },
  forest: {
    label: "Forest",
    c0: "#2F4F3E", c1: "#6B8F71", angle: 15,
    cream: "#F3EBD4", cream1: "#E0D0AE", overcast: "#1E3329",
  },
  copper: {
    label: "Copper",
    c0: "#5C3A2E", c1: "#C4894A", angle: 20,
    cream: "#F7EFE0", cream1: "#E8D5B5", overcast: "#3A241C",
  },
};

export const ENVELOPES = ["none", "shadow-only", "body", "body+flap"];

function layerIdOf(item) {
  return typeof item === "string" ? item : item && item.id;
}

function clonePulse(spec) {
  return {
    fadeMs: spec.fadeMs,
    steps: spec.steps.map(normalizeStep),
  };
}

/** Old stagger model → explicit steps. staggerMs 0 = all sparkles in one step. */
export function stepKeep(step) {
  return !step || step.keep !== false;
}

export function cascadeSteps({ fill, staggerMs, holdMs, keep = true }) {
  const color = String(fill).toUpperCase();
  if (!staggerMs) {
    return [{ holdMs, fill: color, layers: SPARKLE_IDS.slice(), keep }];
  }
  return SPARKLE_IDS.map((_, i) => ({
    holdMs: i < SPARKLE_IDS.length - 1 ? staggerMs : holdMs,
    fill: color,
    layers: SPARKLE_IDS.slice(0, i + 1),
    keep,
  }));
}

export function defaultMenuBar() {
  return {
    success: {
      fadeMs: 280,
      steps: cascadeSteps({ fill: "#30D158", staggerMs: 140, holdMs: 260 }),
    },
    error: {
      fadeMs: 280,
      steps: cascadeSteps({ fill: "#FF9F0A", staggerMs: 0, holdMs: 420 }),
    },
  };
}

function invertDarkStored(mb) {
  if (!mb) return null;
  if (mb.invertDark === true) return true;
  if (mb.invertDark === false) return false;
  return null;
}

/** Dark-bar preview: explicit invertDark, else invert unless mixed ink. */
export function invertDarkOf(state) {
  const stored = invertDarkStored(state && state.menuBar);
  if (stored !== null) return stored;
  return !templateUsesTwoTone(state);
}

function msOr(v, fallback) {
  return typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : fallback;
}

function normalizeStep(raw) {
  if (!raw || typeof raw !== "object") return { holdMs: 0, fill: "#30D158", layers: [], keep: true };
  const holdMs = msOr(raw.holdMs, 0);
  const list = Array.isArray(raw.layers) ? raw.layers : [];
  let fillRaw = raw.fill;
  if (!hexOk(fillRaw)) {
    const hit = list.find((item) => item && hexOk(item.fill));
    fillRaw = hit ? hit.fill : "#30D158";
  }
  const fill = String(fillRaw).toUpperCase();
  const layers = [];
  const seen = new Set();
  for (const item of list) {
    const id = layerIdOf(item);
    if (!PULSE_LAYER_IDS.includes(id) || seen.has(id)) continue;
    seen.add(id);
    layers.push(id);
  }
  return { holdMs, fill, layers, keep: stepKeep(raw) };
}

export function pulseDuration(spec) {
  if (!spec || !Array.isArray(spec.steps)) return 0;
  const hold = spec.steps.reduce((n, s) => n + Math.max(0, Number(s.holdMs) || 0), 0);
  return hold + Math.max(0, Number(spec.fadeMs) || 0);
}

export function pulseStepOverlays(step, opacity = 1) {
  const out = {};
  if (!step || !Array.isArray(step.layers) || !opacity) return out;
  const fill = hexOk(step.fill) ? step.fill.toUpperCase() : "#30D158";
  const keep = stepKeep(step);
  for (const item of step.layers) {
    const id = layerIdOf(item);
    if (!PULSE_LAYER_IDS.includes(id)) continue;
    out[id] = { fill, opacity, keep };
  }
  return out;
}

/** Overlay map `{ [layerId]: { fill, opacity } }` at tMs from pulse start. */
export function pulseAt(tMs, spec) {
  const steps = spec && Array.isArray(spec.steps) ? spec.steps : [];
  if (!steps.length) return {};
  let t = 0;
  let last = steps[0];
  for (const step of steps) {
    const hold = Math.max(0, Number(step.holdMs) || 0);
    if (tMs < t + hold) return pulseStepOverlays(step, 1);
    t += hold;
    last = step;
  }
  const fadeMs = Math.max(0, Number(spec.fadeMs) || 0);
  if (fadeMs > 0 && tMs < t + fadeMs) {
    return pulseStepOverlays(last, Math.max(0, 1 - (tMs - t) / fadeMs));
  }
  return {};
}

function mergePulse(base, extra) {
  if (!extra || typeof extra !== "object") return clonePulse(base);
  if (Array.isArray(extra.steps)) {
    const steps = extra.steps.map(normalizeStep);
    return {
      fadeMs: msOr(extra.fadeMs, base.fadeMs),
      steps: steps.length ? steps : clonePulse(base).steps,
    };
  }
  const legacy = extra.sparkleFill != null || extra.staggerMs != null || extra.holdMs != null;
  if (!legacy) {
    return {
      fadeMs: msOr(extra.fadeMs, base.fadeMs),
      steps: clonePulse(base).steps,
    };
  }
  const fill = hexOk(extra.sparkleFill)
    ? extra.sparkleFill.toUpperCase()
    : (base.steps[0]?.fill || "#30D158");
  return {
    fadeMs: msOr(extra.fadeMs, base.fadeMs),
    steps: cascadeSteps({
      fill,
      staggerMs: msOr(extra.staggerMs, 0),
      holdMs: msOr(extra.holdMs, 260),
    }),
  };
}

const LAYER_KEYS = ["visible", "fillMode", "c0", "c1", "angle", "opacity", "matchPlate", "menuBarInk"];

function layer(partial) {
  return Object.assign({
    visible: true,
    fillMode: "solid",
    c0: "#888888",
    c1: "#cccccc",
    angle: 0,
    opacity: 1,
    matchPlate: false,
    menuBarInk: "black",
    inGlyph: true,
    kind: "path",
  }, partial);
}

/** AppKit gray steps: black, darkGray (⅓), gray (½), lightGray (⅔), white. */
export const MENU_BAR_INKS = [
  { id: "black", hex: "#000000", label: "Black" },
  { id: "darkGray", hex: "#555555", label: "Dark gray" },
  { id: "gray", hex: "#808080", label: "Gray" },
  { id: "lightGray", hex: "#AAAAAA", label: "Light gray" },
  { id: "white", hex: "#FFFFFF", label: "White" },
];

const MENU_BAR_INK_IDS = new Set(MENU_BAR_INKS.map((x) => x.id));

export function menuBarInkOf(layer) {
  const v = layer && layer.menuBarInk;
  return MENU_BAR_INK_IDS.has(v) ? v : "black";
}

function menuBarInkHex(layer) {
  return MENU_BAR_INKS.find((x) => x.id === menuBarInkOf(layer)).hex;
}

function isHoleSparkle(layer) {
  return !!(layer && SPARKLE_IDS.includes(layer.id) && layer.matchPlate);
}

/** Mixed idle glyph (any non-black ink). Auto dark-bar preview stays as painted unless invertDark is set. */
export function templateUsesTwoTone(state) {
  return state.layers.some((l) =>
    l.visible && l.id !== "plate" && menuBarInkOf(l) !== "black" && !isHoleSparkle(l));
}

export function defaults() {
  return {
    scale: KEYLINE,
    menuBar: defaultMenuBar(),
    layers: [
      layer({ id: "plate", name: "Plate", tag: "canvas", kind: "rect", inGlyph: false, fillMode: "gradient", c0: "#4B617F", c1: "#7A8EAA", angle: 0, opacity: 1 }),
      layer({ id: "overcast", name: "Overcast shadow", tag: "envelope", d: PATHS.overcast, c0: "#3D4C5F", c1: "#2A3544", opacity: 0.28 }),
      layer({ id: "body", name: "Envelope body", tag: "optional", d: PATHS.body, c0: "#3D4C5F", c1: "#2A3544", opacity: 0.42, visible: false }),
      layer({ id: "flap", name: "Envelope flap", tag: "optional", d: PATHS.flap, c0: "#3D4C5F", c1: "#2A3544", opacity: 0.5, visible: false }),
      layer({ id: "bowl", name: "Cream bowl", tag: "charge", d: PATHS.bowl, c0: "#F8EED8", c1: "#E4D4B4", opacity: 1 }),
      layer({ id: "field", name: "Cream field", tag: "charge", d: PATHS.field, c0: "#F8EED8", c1: "#E4D4B4", opacity: 1 }),
      layer({ id: "sparkleLg", name: "Sparkle large", tag: "hole", d: PATHS.sparkleLg, c0: "#4B617F", c1: "#7A8EAA", matchPlate: true }),
      layer({ id: "sparkleMid", name: "Sparkle mid", tag: "hole", d: PATHS.sparkleMid, c0: "#4B617F", c1: "#7A8EAA", matchPlate: true }),
      layer({ id: "sparkleSm", name: "Sparkle small", tag: "hole", d: PATHS.sparkleSm, c0: "#4B617F", c1: "#7A8EAA", matchPlate: true }),
    ],
  };
}

export function slimState(state) {
  const mb = state.menuBar || defaultMenuBar();
  const invertDark = invertDarkStored(mb);
  return {
    schema: SCHEMA,
    scale: state.scale,
    menuBar: {
      ...(invertDark === null ? {} : { invertDark }),
      success: clonePulse(mb.success),
      error: clonePulse(mb.error),
    },
    layers: state.layers.map(({ id, visible, fillMode, c0, c1, angle, opacity, matchPlate, menuBarInk }) =>
      ({ id, visible, fillMode, c0, c1, angle, opacity, matchPlate, menuBarInk: menuBarInkOf({ menuBarInk }) })),
  };
}

export function hydrate(slim) {
  const base = defaults();
  if (!slim || typeof slim !== "object") return base;
  if (typeof slim.scale === "number") base.scale = slim.scale;
  if (slim.menuBar) {
    const invertDark = invertDarkStored(slim.menuBar);
    if (invertDark !== null) base.menuBar.invertDark = invertDark;
    else delete base.menuBar.invertDark;
    base.menuBar.success = mergePulse(base.menuBar.success, slim.menuBar.success);
    base.menuBar.error = mergePulse(base.menuBar.error, slim.menuBar.error);
  }
  if (Array.isArray(slim.layers)) {
    for (const l of base.layers) {
      const hit = slim.layers.find((x) => x.id === l.id);
      if (!hit) continue;
      for (const k of LAYER_KEYS) {
        if (hit[k] === undefined) continue;
        l[k] = k === "menuBarInk" ? menuBarInkOf(hit) : hit[k];
      }
    }
    base.layers = orderLayers(base.layers, slim.layers.map((x) => x && x.id));
  }
  return base;
}

export function packVersion({ slug, state, note = "" }) {
  return {
    kind: "mailgent-icon-version",
    schema: SCHEMA,
    slug: slug || "",
    savedAt: new Date().toISOString(),
    note,
    state: slimState(state),
  };
}

export function unpackVersion(raw) {
  const data = typeof raw === "string" ? JSON.parse(raw) : raw;
  if (!data || typeof data !== "object") throw new Error("not a MailGent icon version");
  if (data.kind === "mailgent-icon-version" && data.state) {
    return { slug: data.slug || "", note: data.note || "", state: hydrate(data.state) };
  }
  if (data.state && Array.isArray(data.state.layers)) {
    return { slug: data.slug || "", note: data.note || "", state: hydrate(data.state) };
  }
  if (Array.isArray(data.layers)) {
    return { slug: data.slug || "", note: data.note || "", state: hydrate(data) };
  }
  throw new Error("not a MailGent icon version");
}

export function findLayer(state, id) {
  return state.layers.find((l) => l.id === id);
}

/** `ids` is back → front. Unknown / duplicate ids ignored; omitted layers stay at the end. */
export function orderLayers(layers, ids) {
  const byId = new Map(layers.map((l) => [l.id, l]));
  const seen = new Set();
  const out = [];
  for (const id of ids) {
    const l = byId.get(id);
    if (!l || seen.has(id)) continue;
    out.push(l);
    seen.add(id);
  }
  for (const l of layers) {
    if (!seen.has(l.id)) out.push(l);
  }
  return out;
}

/** `delta` −1 = send back (up the list), +1 = bring forward (down the list). */
export function moveLayer(state, id, delta) {
  const i = state.layers.findIndex((l) => l.id === id);
  const j = i + delta;
  if (i < 0 || j < 0 || j >= state.layers.length) return state;
  const next = state.layers.slice();
  [next[i], next[j]] = [next[j], next[i]];
  state.layers = next;
  return state;
}

export function setEnvelope(state, mode) {
  const overcast = findLayer(state, "overcast");
  const body = findLayer(state, "body");
  const flap = findLayer(state, "flap");
  if (mode === "none") {
    overcast.visible = false;
    body.visible = false;
    flap.visible = false;
  } else if (mode === "shadow-only") {
    overcast.visible = true;
    body.visible = false;
    flap.visible = false;
  } else if (mode === "body") {
    overcast.visible = true;
    body.visible = true;
    flap.visible = false;
  } else if (mode === "body+flap") {
    overcast.visible = true;
    body.visible = true;
    flap.visible = true;
  }
  return state;
}

export function applyPalette(state, pal) {
  if (typeof pal === "string") pal = PALETTES[pal];
  if (!pal) throw new Error("unknown palette");
  const plate = findLayer(state, "plate");
  plate.fillMode = "gradient";
  plate.c0 = pal.c0;
  plate.c1 = pal.c1;
  plate.angle = pal.angle ?? 0;
  for (const id of ["bowl", "field"]) {
    const l = findLayer(state, id);
    l.c0 = pal.cream;
    l.c1 = pal.cream1 ?? pal.cream;
  }
  const oc = findLayer(state, "overcast");
  oc.c0 = pal.overcast;
  oc.c1 = pal.overcast;
  for (const id of ["body", "flap"]) {
    const l = findLayer(state, id);
    l.c0 = pal.overcast;
    l.c1 = pal.overcast;
  }
  return state;
}

export function applyPatch(state, patch = {}) {
  const next = hydrate(slimState(state));
  if (patch.palette) applyPalette(next, patch.palette);
  if (typeof patch.scale === "number") next.scale = patch.scale;
  if (patch.envelope) setEnvelope(next, patch.envelope);
  if (patch.menuBar && typeof patch.menuBar === "object") {
    const invertDark = invertDarkStored(patch.menuBar);
    if (invertDark !== null) next.menuBar.invertDark = invertDark;
    if (patch.menuBar.success) {
      next.menuBar.success = mergePulse(next.menuBar.success, patch.menuBar.success);
    }
    if (patch.menuBar.error) {
      next.menuBar.error = mergePulse(next.menuBar.error, patch.menuBar.error);
    }
  }
  if (patch.layers && typeof patch.layers === "object") {
    for (const [id, partial] of Object.entries(patch.layers)) {
      const l = findLayer(next, id);
      if (!l || !partial) continue;
      for (const k of LAYER_KEYS) {
        if (partial[k] === undefined) continue;
        l[k] = k === "menuBarInk" ? menuBarInkOf(partial) : partial[k];
      }
    }
  }
  if (Array.isArray(patch.layerOrder)) {
    next.layers = orderLayers(next.layers, patch.layerOrder);
  }
  return next;
}

export function todayISO(d = new Date()) {
  return d.toISOString().slice(0, 10);
}

export function sanitizeSlug(raw) {
  const s = String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
  if (!s) throw new Error("empty slug");
  return s;
}

export function candidateId(slug, date = todayISO()) {
  const s = sanitizeSlug(slug);
  if (/^\d{4}-\d{2}-\d{2}-/.test(s)) return s;
  return `${date}-${s}`;
}

function hexOk(v) {
  return typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v);
}

function gradVec(deg) {
  const r = (deg * Math.PI) / 180;
  const dx = Math.sin(r);
  const dy = -Math.cos(r);
  return { x1: 0.5 - dx / 2, y1: 0.5 - dy / 2, x2: 0.5 + dx / 2, y2: 0.5 + dy / 2 };
}

function plate(state) {
  return findLayer(state, "plate");
}

function resolved(state, layer) {
  if (!layer.matchPlate) return layer;
  const p = plate(state);
  return { ...layer, fillMode: p.fillMode, c0: p.c0, c1: p.c1, angle: p.angle };
}

export function buildSvg(state, opts = {}) {
  const appearance = opts.appearance === "template" ? "template" : "color";
  const pfx = opts.idPrefix || "i";
  if (appearance === "template") {
    return buildTemplateSvg(state, pfx, overlaysFromOpts(opts));
  }
  const defs = [];
  const parts = [];
  const glyphBuf = [];
  const xf = glyphTransform(state);
  const flushGlyph = () => {
    if (!glyphBuf.length) return;
    parts.push(`<g transform="${xf}">
  ${glyphBuf.join("\n  ")}
  </g>`);
    glyphBuf.length = 0;
  };
  for (const raw of state.layers) {
    if (!raw.visible) continue;
    const l = resolved(state, raw);
    let fill = hexOk(l.c0) ? l.c0 : "#888888";
    if (l.fillMode === "gradient") {
      const v = gradVec(Number(l.angle) || 0);
      const c0 = hexOk(l.c0) ? l.c0 : "#888888";
      const c1 = hexOk(l.c1) ? l.c1 : "#cccccc";
      defs.push(`<linearGradient id="${pfx}-g-${l.id}" x1="${v.x1}" y1="${v.y1}" x2="${v.x2}" y2="${v.y2}"><stop offset="0" stop-color="${c0}"/><stop offset="1" stop-color="${c1}"/></linearGradient>`);
      fill = `url(#${pfx}-g-${l.id})`;
    }
    const op = l.opacity === 1 ? "" : ` fill-opacity="${l.opacity}"`;
    let node;
    if (l.kind === "rect") {
      node = `<rect width="1024" height="1024" rx="229" fill="${fill}"${op}/>`;
    } else {
      node = `<path fill="${fill}"${op} d="${l.d}"/>`;
    }
    if (l.inGlyph) glyphBuf.push(node);
    else {
      flushGlyph();
      parts.push(node);
    }
  }
  flushGlyph();
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>${defs.join("")}</defs>
  ${parts.join("\n  ")}
</svg>`;
}

/** macOS menu-bar glyph: no plate. Per-layer gray ramp; matchPlate sparkles stay holes. */
function glyphTransform(state) {
  return `translate(512 512) scale(${state.scale}) translate(-512 -518)`;
}

function overlaysFromOpts(opts) {
  if (opts.overlays && typeof opts.overlays === "object") return opts.overlays;
  const out = {};
  const fill = hexOk(opts.sparkleFill) ? opts.sparkleFill.toUpperCase() : "#30D158";
  const ops = opts.sparkleOpacities || {};
  for (const id of SPARKLE_IDS) {
    const op = ops[id];
    if (!op) continue;
    out[id] = { fill, opacity: op };
  }
  return out;
}

function fxPath(raw, fx) {
  if (!fx || !fx.opacity || !raw.d) return "";
  const fill = hexOk(fx.fill) ? fx.fill : "#30D158";
  const keep = fx.keep !== false ? " mb-fx-keep" : "";
  return `<path class="mb-fx-layer${keep}" fill="${fill}" fill-opacity="${fx.opacity}" fill-rule="nonzero" d="${raw.d}"/>`;
}

function buildTemplateSvg(state, pfx, overlays = {}) {
  const holes = SPARKLE_IDS
    .map((id) => findLayer(state, id))
    .filter((l) => l.visible && isHoleSparkle(l));
  const body = [];
  const holeFx = [];
  for (const raw of state.layers) {
    if (!raw.visible || raw.id === "plate" || raw.kind === "rect" || !raw.d) continue;
    const fx = fxPath(raw, overlays[raw.id]);
    if (isHoleSparkle(raw)) {
      if (fx) holeFx.push(fx);
      continue;
    }
    const op = raw.opacity === 1 ? "" : ` fill-opacity="${raw.opacity}"`;
    body.push(`<path fill="${menuBarInkHex(raw)}"${op} d="${raw.d}"/>`);
    if (fx) body.push(fx);
  }
  const xf = glyphTransform(state);
  const hid = `${pfx}-holes`;
  const mask = holes.length === 0 ? "" : `<mask id="${hid}" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
      <rect width="1024" height="1024" fill="#fff"/>
      <g transform="${xf}">
      ${holes.map((l) => `<path fill="#000" fill-rule="nonzero" d="${l.d}"/>`).join("\n      ")}
      </g>
    </mask>`;
  const maskAttr = holes.length ? ` mask="url(#${hid})"` : "";
  const twoTone = templateUsesTwoTone(state) ? " mb-twotone" : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>${mask}</defs>
  <g class="mb-template${twoTone}"${maskAttr}>
  <g transform="${xf}">
  ${body.join("\n  ")}
  </g>
  </g>
  <g class="mb-fx" transform="${xf}">
  ${holeFx.join("\n  ")}
  </g>
</svg>`;
}

export function sparkleMode(state) {
  const holes = ["sparkleLg", "sparkleMid", "sparkleSm"].every((id) => findLayer(state, id).matchPlate);
  return holes ? "holes" : "custom-fill";
}

export function envelopeMode(state) {
  const o = findLayer(state, "overcast").visible;
  const b = findLayer(state, "body").visible;
  const f = findLayer(state, "flap").visible;
  if (!o && !b && !f) return "none";
  if (o && b && f) return "body+flap";
  if (o && b) return "body";
  if (o) return "shadow-only";
  return "custom";
}

export function expandVariants({ base, palettes, envelopes, variants }) {
  const root = hydrate(base);
  const out = [];
  const extra = Array.isArray(variants) ? variants : [];
  let palNames = palettes;
  if (palNames === "all") palNames = Object.keys(PALETTES);
  if (!Array.isArray(palNames)) palNames = palNames ? [palNames] : [];
  let envNames = envelopes;
  if (!Array.isArray(envNames) || envNames.length === 0) envNames = [envelopeMode(root)];

  if (palNames.length === 0 && extra.length === 0) {
    throw new Error("pass palettes and/or variants[]");
  }

  for (const pal of palNames) {
    for (const env of envNames) {
      const slug = env === envelopeMode(root) || envNames.length === 1
        ? String(pal)
        : `${pal}-${env.replace("+", "-plus-")}`;
      out.push({
        slug,
        note: `${PALETTES[pal]?.label ?? pal} · envelope ${env}`,
        state: applyPatch(root, { palette: pal, envelope: env }),
      });
    }
  }
  for (const v of extra) {
    if (!v || !v.slug) throw new Error("each variants[] item needs slug");
    out.push({
      slug: v.slug,
      note: v.note || v.slug,
      state: applyPatch(v.base ? hydrate(v.base) : root, v.patch || {}),
    });
  }
  return out;
}

export function apiSchema() {
  return {
    schema: SCHEMA,
    keyline: "full-1024",
    stampFromPng: false,
    layerIds: LAYER_IDS,
    palettes: Object.fromEntries(Object.entries(PALETTES).map(([id, p]) => [id, p.label])),
    appearances: ["color", "mono", "template"],
    menuBarPulses: ["idle", "success", "error"],
    pulseLayerIds: PULSE_LAYER_IDS,
    menuBarInk: "black | darkGray | gray | lightGray | white per non-plate layer (AppKit gray steps). Color/Mono ignore it. matchPlate sparkles stay holes.",
    menuBar: {
      invertDark: "bool. Invert the gray ramp on a dark menu bar. Omit = invert unless mixed ink.",
      success: "{ fadeMs, steps: [{ holdMs, fill, layers: [layerId], keep?: bool }] }. keep (default true) = do not invert this fill on a dark bar.",
      error: "same. Old sparkleFill + staggerMs + holdMs + fadeMs still hydrates.",
    },
    envelopes: ENVELOPES,
    patch: {
      scale: "number (default 824/712 ≈ 1.157)",
      palette: "palette id or {c0,c1,angle,cream,cream1,overcast}",
      envelope: ENVELOPES.join(" | "),
      layers: "{ [layerId]: { visible, fillMode: solid|gradient, c0, c1, angle, opacity, matchPlate, menuBarInk: black|darkGray|gray|lightGray|white } }",
      layerOrder: "[layerId] back → front. Omitted ids stay at the end in prior relative order.",
    },
    endpoints: {
      "GET /api/health": "server up",
      "GET /api/schema": "this document",
      "GET /api/defaults": "after-tweaks state",
      "POST /api/render": "{ state | patch, base?, appearance?: color|template } → { svg, templateSvg, state }",
      "POST /api/save": "{ slug, state? | patch?, base?, note? } → candidate files (color + template + version json)",
      "POST /api/variants": "{ base?, palettes: 'all'|ids[], envelopes?: ids[], variants?: [{slug, patch, note}] }",
      "GET /api/candidates": "saved sketches",
      "GET /api/candidates/:slug": "one sketch",
      "POST /api/pick": "{ slug, intent: favorite|ship, note? } → pick.json + SHIP.md",
      "GET /api/pick": "current pick (204 if none)",
      "GET /api/ship/:slug": "markdown brief for the agent",
      "GET /api/pack/:slug": "zip: svg + png + template + json + SHIP.md",
    },
    cli: "node .scratch/app-icon/api.mjs [serve|render|save|load|variants|list|pick|brief|pack]",
  };
}

export function shipBrief({ slug, intent = "favorite", note = "", state }) {
  const holes = sparkleMode(state);
  const env = envelopeMode(state);
  const slots = ICONSET_SLOTS.map(([n, px]) => `- ${n} (${px}px)`).join("\n");
  const shipNow = intent === "ship";
  return `# Ship candidate \`${slug}\`

${shipNow
    ? "The user chose this in the icon tweaker **to add to the app**. Follow the checklist below now."
    : "The user marked this as a favorite. Do **not** write AppIcon until they also say **ship this**."}

${note ? `Note: ${note}\n` : ""}
## Files (already in repo)

- SVG \`.scratch/app-icon/candidates/${slug}.svg\` — **full 1024 plate**, glyph already on the 824 keyline
- PNG \`.scratch/app-icon/candidates/${slug}.png\`
- Template (menu bar) \`.scratch/app-icon/candidates/${slug}-template.svg\` + \`-template.png\` — per-layer grayscale, alpha holes, no plate
- State \`.scratch/app-icon/candidates/${slug}.json\`
- Pick \`.scratch/app-icon/pick.json\`

## Hard rules

- Master is **full-1024**. Resize appiconset slots from the PNG. **Do not** run \`Scripts/AppIcon/stamp_from_png.swift\` (double inset ≈ 66% crop).
- Do not use Icon Composer MCP \`export_preview\`.
- Sparkles in this candidate: **${holes}**. Envelope: **${env}**.
- This tweaker is **flat**. Do not invent a glass \`.icon\` rewrite unless the user asks for glass after this ship.
- Canonical procedure: \`docs/agents/app-icon.md\`.

## Checklist (only if shipping)

1. Confirm \`pick.json\` slug is \`${slug}\`.
2. Resize \`${slug}.png\` into \`MailGent/Assets.xcassets/AppIcon.appiconset/\` (same filenames, no extra keyline):
${slots}
3. Pack icns: copy those PNGs into a temp \`.iconset\` named \`icon_*.png\`, then \`iconutil -c icns\` → \`MailGent/Resources/AppIcon.icns\`.
4. Skip \`Design/IconPack/MailGent.icon\` / \`AppIcon.icon\` unless the user asked for Liquid Glass on this mark.
5. Skip \`test_app_icon.swift\` — that test is for glyph-in-keyline Era A masters; a full-bleed plate will fail it on purpose.
6. Do not run Liquid Composer / \`export-mailgent.mjs\` for this flat candidate.
7. Menu-bar template + \`menuBar\` pulse spec in the JSON are **preview + pack only**. Live app still uses SF Symbol \`tray.full\` (\`MenuBarIcon.swift\`). Do not swap the status item unless the user asks. Each of Success/Error is a step timeline: layers + fill + hold, then fade.

## Do not

- Stamp, MCP preview, or compile a different candidate than \`${slug}\`.
`;
}

export function pickRecord({ slug, intent, note, state }) {
  return {
    schema: SCHEMA,
    intent,
    slug,
    pickedAt: new Date().toISOString(),
    keyline: "full-1024",
    stampFromPng: false,
    sparkles: sparkleMode(state),
    envelope: envelopeMode(state),
    note: note || "",
    files: {
      svg: `.scratch/app-icon/candidates/${slug}.svg`,
      png: `.scratch/app-icon/candidates/${slug}.png`,
      templateSvg: `.scratch/app-icon/candidates/${slug}-template.svg`,
      templatePng: `.scratch/app-icon/candidates/${slug}-template.png`,
      json: `.scratch/app-icon/candidates/${slug}.json`,
      brief: `.scratch/app-icon/candidates/${slug}-SHIP.md`,
    },
  };
}

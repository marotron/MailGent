/** Tiny geometric identicon from a string — same seed → same face (compare IDs at a glance). */

function hash32(input: string): number {
  let h = 2166136261;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

function hsl(h: number, s: number, l: number): string {
  return `hsl(${h % 360} ${s}% ${l}%)`;
}

/** Short visual prefix like MailGent Ask chrome (`0CC9826F`). */
export function idPrefix(id: string, n = 8): string {
  const cleaned = id.replace(/[^0-9A-Za-z]/g, "");
  return (cleaned || id).slice(0, n).toUpperCase();
}

export function identiconSvg(seed: string, size = 16): string {
  const h = hash32(seed || "?");
  const hue = h % 360;
  const bg = hsl(hue, 42, 88);
  const fg = hsl(hue, 55, 38);
  const cells: string[] = [];
  // 5×5 mirrored grid (GitHub-style)
  for (let y = 0; y < 5; y++) {
    for (let x = 0; x < 3; x++) {
      const bit = (h >>> (y * 3 + x)) & 1;
      if (!bit) continue;
      const mirror = 4 - x;
      cells.push(
        `<rect x="${x}" y="${y}" width="1" height="1" fill="${fg}"/>`,
        x !== mirror ? `<rect x="${mirror}" y="${y}" width="1" height="1" fill="${fg}"/>` : "",
      );
    }
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 5 5" shape-rendering="crispEdges"><rect width="5" height="5" fill="${bg}"/>${cells.join("")}</svg>`;
}

export function identiconNode(seed: string, size = 16): HTMLSpanElement {
  const wrap = document.createElement("span");
  wrap.className = "identicon";
  wrap.title = seed;
  wrap.innerHTML = identiconSvg(seed, size);
  return wrap;
}

export function idChip(seed: string, label?: string): HTMLSpanElement {
  const chip = document.createElement("span");
  chip.className = "id-chip";
  chip.appendChild(identiconNode(seed, 14));
  const text = document.createElement("code");
  text.textContent = label ?? idPrefix(seed);
  text.title = seed;
  chip.appendChild(text);
  return chip;
}

export function looksLikeIdKey(key: string): boolean {
  const k = key.toLowerCase();
  return (
    k === "id" ||
    k === "accountid" ||
    k === "askid" ||
    k === "proposalid" ||
    k.endsWith("id")
  );
}

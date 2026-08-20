#!/bin/zsh
# Generate + test AppIcon designs (Apple 824/1024 keyline).
# Usage:
#   Scripts/AppIcon/run.sh                 # design 1 → AppIcon
#   Scripts/AppIcon/run.sh 3               # design 3 → AppIcon
#   Scripts/AppIcon/run.sh --gallery       # all designs + HTML prototype
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ICONSET="$ROOT/MailGent/Assets.xcassets/AppIcon.appiconset"
RES="$ROOT/MailGent/Resources"
GEN="$ROOT/Scripts/AppIcon/generate_app_icon.swift"
TEST="$ROOT/Scripts/AppIcon/test_app_icon.swift"
GALLERY_DIR="$ROOT/Design/IconPack"
HTML="$GALLERY_DIR/index.html"

NAMES=(companion pair mono seal)
TITLES=("Companion" "Pair" "Mono" "Seal")
BLURBS=(
  "Folded letter with a companion pip"
  "Mail beside a named agent"
  "Geometric Gent G"
  "Grant seal — flap plus pip"
)
PRINCIPLES=(
  "ArchMail envelope language. Pip is the Gent. Two shapes, one idea."
  "Companion posture: mail stays, agent sits beside it."
  "Letterform as logo. No ornament."
  "Badge mark. Reads as grant / pairing."
)

install_icns() {
  local src="$1"
  local work="$ROOT/.build/AppIcon.iconset"
  rm -rf "$work"
  mkdir -p "$work" "$RES"
  cp "$src/icon_16x16.png"      "$work/icon_16x16.png"
  cp "$src/icon_16x16_2x.png"   "$work/diana.k@example.org"
  cp "$src/icon_32x32.png"      "$work/icon_32x32.png"
  cp "$src/icon_32x32_2x.png"   "$work/ivan.p@example.net"
  cp "$src/icon_128x128.png"    "$work/icon_128x128.png"
  cp "$src/icon_128x128_2x.png" "$work/wendy.h@example.net"
  cp "$src/icon_256x256.png"    "$work/icon_256x256.png"
  cp "$src/icon_256x256_2x.png" "$work/laura.c@example.net"
  cp "$src/icon_512x512.png"    "$work/icon_512x512.png"
  cp "$src/icon_512x512_2x.png" "$work/carol.w@example.org"
  iconutil -c icns "$work" -o "$RES/AppIcon.icns"
  rm -rf "$work"
  ls -la "$RES/AppIcon.icns"
}

run_one() {
  local design="$1"
  local dest="$2"
  echo "== generate ($design) → $dest =="
  mkdir -p "$dest"
  swift "$GEN" "$dest" --design "$design"
  echo "== test ($design) =="
  swift "$TEST" "$dest"
}

MODE="${1:-1}"

if [[ "$MODE" == "--gallery" || "$MODE" == "--all" ]]; then
  VAR="$ROOT/.build/icon-variants"
  rm -rf "$VAR"
  mkdir -p "$VAR" "$GALLERY_DIR"

  cards=""
  switcher=""
  for n in {1..4}; do
    name="${NAMES[$n]}"
    title="${TITLES[$n]}"
    blurb="${BLURBS[$n]}"
    principle="${PRINCIPLES[$n]}"
    out="$VAR/$name"
    run_one "$n" "$out"
    cp "$out/icon_512x512_2x.png" "$GALLERY_DIR/preview-$name-1024.png"
    cp "$out/icon_512x512.png"    "$GALLERY_DIR/preview-$name-512.png"
    cp "$out/icon_128x128.png"    "$GALLERY_DIR/preview-$name-128.png"
    cp "$out/icon_32x32.png"      "$GALLERY_DIR/preview-$name-32.png"
    cp "$out/icon_16x16.png"      "$GALLERY_DIR/preview-$name-16.png"
    cards+="
    <article class=\"card\" data-design=\"$n\" data-name=\"$name\" data-title=\"$title\" data-blurb=\"$blurb\" data-principle=\"$principle\">
      <button type=\"button\" class=\"pick\" data-design=\"$n\" title=\"Select $title\">
        <img src=\"preview-$name-512.png\" width=\"220\" height=\"220\" alt=\"$title\" />
      </button>
      <div class=\"meta\">
        <h2><span class=\"num\">$n</span> $title</h2>
        <p>$blurb</p>
      </div>
    </article>"
    switcher+="<button type=\"button\" class=\"sw\" data-design=\"$n\" data-name=\"$name\">$n · $title</button>"
    echo
  done

  # Default ship companion into live AppIcon
  echo "== install design 1 (companion) into AppIcon =="
  cp "$VAR/companion/"*.png "$ICONSET/"
  install_icns "$ICONSET"

  cat > "$HTML" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>MailGent Logo Prototype</title>
<style>
  :root {
    --bg: #f4f2ee;
    --ink: #1a1c20;
    --muted: #6a6760;
    --line: #ddd8cf;
    --panel: #fffefb;
    --stage: #e8e4dc;
    --accent: #3d4a5c;
    --gold: #9a7b4f;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: "SF Pro Display", "Avenir Next", "Segoe UI", sans-serif;
    background:
      radial-gradient(900px 500px at 80% -10%, #ebe6dc 0%, transparent 55%),
      radial-gradient(700px 400px at 0% 100%, #e2dde8 0%, transparent 50%),
      var(--bg);
    color: var(--ink);
    min-height: 100vh;
    padding-bottom: 96px;
  }
  .proto-banner {
    background: #2a2e36;
    color: #c9c4b8;
    font-size: 0.78rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    text-align: center;
    padding: 8px 16px;
  }
  .proto-banner strong { color: #e8e0d0; font-weight: 500; }
  header {
    max-width: 1080px;
    margin: 0 auto;
    padding: 36px 28px 8px;
  }
  header .eyebrow {
    color: var(--gold);
    font-size: 0.8rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    margin: 0 0 10px;
  }
  header h1 {
    font-size: clamp(1.9rem, 3.2vw, 2.7rem);
    font-weight: 560;
    letter-spacing: -0.035em;
    margin: 0 0 10px;
  }
  header p {
    margin: 0;
    color: var(--muted);
    font-size: 1.02rem;
    max-width: 38rem;
    line-height: 1.55;
  }
  .hero {
    max-width: 1080px;
    margin: 28px auto 0;
    padding: 0 28px;
    display: grid;
    grid-template-columns: 1.1fr 1fr;
    gap: 28px;
    align-items: stretch;
  }
  @media (max-width: 820px) {
    .hero { grid-template-columns: 1fr; }
  }
  .stage {
    background: var(--stage);
    border-radius: 28px;
    border: 1px solid var(--line);
    min-height: 380px;
    display: flex;
    align-items: center;
    justify-content: center;
    position: relative;
    overflow: hidden;
  }
  .stage.dock {
    background: linear-gradient(180deg, #7a7e88, #52565e);
  }
  .stage.dark {
    background: radial-gradient(circle at 50% 40%, #2a2e38 0%, #12141a 70%);
  }
  .stage img.hero-icon {
    width: min(280px, 70%);
    height: auto;
    filter: drop-shadow(0 22px 40px rgba(0,0,0,0.28));
    transition: transform 220ms ease;
  }
  .detail {
    background: var(--panel);
    border: 1px solid var(--line);
    border-radius: 28px;
    padding: 28px 28px 24px;
    display: flex;
    flex-direction: column;
    gap: 18px;
  }
  .detail .num {
    color: var(--gold);
    font-variant-numeric: tabular-nums;
    font-size: 0.85rem;
    letter-spacing: 0.08em;
  }
  .detail h2 {
    margin: 4px 0 0;
    font-size: 1.65rem;
    font-weight: 560;
    letter-spacing: -0.03em;
  }
  .detail .blurb {
    margin: 0;
    color: var(--muted);
    line-height: 1.5;
    font-size: 1.02rem;
  }
  .detail .principle {
    margin: 0;
    padding: 14px 16px;
    background: #f7f4ee;
    border-radius: 14px;
    border: 1px solid var(--line);
    font-size: 0.92rem;
    line-height: 1.45;
    color: #3a3834;
  }
  .wordmark {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 14px 0 4px;
  }
  .wordmark img {
    width: 48px;
    height: 48px;
  }
  .wordmark .name {
    font-size: 1.55rem;
    font-weight: 560;
    letter-spacing: -0.04em;
  }
  .wordmark .tag {
    display: block;
    font-size: 0.78rem;
    color: var(--muted);
    letter-spacing: 0.02em;
    margin-top: 2px;
  }
  .sizes {
    display: flex;
    align-items: flex-end;
    gap: 18px;
    padding-top: 4px;
  }
  .sizes figure {
    margin: 0;
    text-align: center;
  }
  .sizes img {
    display: block;
    margin: 0 auto 6px;
    image-rendering: -webkit-optimize-contrast;
  }
  .sizes figcaption {
    font-size: 0.68rem;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }
  .ship {
    margin-top: auto;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.78rem;
    background: #1a1c20;
    color: #e8e6e1;
    border-radius: 10px;
    padding: 10px 12px;
  }
  .grid {
    max-width: 1080px;
    margin: 36px auto 0;
    padding: 0 28px;
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 16px;
  }
  @media (max-width: 820px) {
    .grid { grid-template-columns: repeat(2, 1fr); }
  }
  @media (max-width: 520px) {
    .grid { grid-template-columns: 1fr; }
  }
  .card {
    background: var(--panel);
    border: 1px solid var(--line);
    border-radius: 20px;
    overflow: hidden;
    transition: outline 120ms ease;
  }
  .card.selected { outline: 2px solid var(--accent); outline-offset: 2px; }
  .pick {
    display: block;
    width: 100%;
    margin: 0;
    padding: 22px 16px 10px;
    background: #ebe7df;
    border: 0;
    cursor: pointer;
  }
  .pick img {
    display: block;
    margin: 0 auto;
    width: min(160px, 72%);
    height: auto;
    filter: drop-shadow(0 12px 20px rgba(0,0,0,0.18));
    transition: transform 160ms ease;
  }
  .pick:hover img { transform: translateY(-2px) scale(1.02); }
  .meta { padding: 6px 16px 16px; }
  .meta h2 {
    margin: 0 0 4px;
    font-size: 1.05rem;
    font-weight: 560;
  }
  .meta .num { color: var(--gold); margin-right: 4px; }
  .meta p {
    margin: 0;
    color: var(--muted);
    font-size: 0.86rem;
    line-height: 1.4;
  }
  .toolbar {
    max-width: 1080px;
    margin: 18px auto 0;
    padding: 0 28px;
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
    align-items: center;
  }
  .toolbar label { color: var(--muted); font-size: 0.85rem; }
  .toolbar select {
    background: var(--panel);
    color: var(--ink);
    border: 1px solid var(--line);
    border-radius: 8px;
    padding: 7px 10px;
    font: inherit;
  }
  footer {
    max-width: 1080px;
    margin: 28px auto 0;
    padding: 0 28px;
    color: var(--muted);
    font-size: 0.88rem;
    line-height: 1.5;
  }
  footer strong { color: var(--accent); font-weight: 560; }
  .switcher {
    position: fixed;
    left: 50%;
    bottom: 20px;
    transform: translateX(-50%);
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
    justify-content: center;
    max-width: calc(100vw - 24px);
    padding: 8px;
    background: rgba(26, 28, 32, 0.92);
    backdrop-filter: blur(12px);
    border-radius: 16px;
    box-shadow: 0 12px 40px rgba(0,0,0,0.28);
    z-index: 50;
  }
  .switcher .sw {
    border: 0;
    background: transparent;
    color: #b8b4aa;
    font: inherit;
    font-size: 0.78rem;
    padding: 8px 12px;
    border-radius: 10px;
    cursor: pointer;
    white-space: nowrap;
  }
  .switcher .sw:hover { color: #fff; background: rgba(255,255,255,0.06); }
  .switcher .sw.active {
    background: #fff;
    color: #1a1c20;
    font-weight: 560;
  }
</style>
</head>
<body>
  <div class="proto-banner">PROTOTYPE — throwaway logo exploration · question: which mark best says “mail companion”?</div>
  <header>
    <p class="eyebrow">MailGent brand</p>
    <h1>Logo &amp; app icon directions</h1>
    <p>MailGent is a macOS companion to Apple Mail: on-device index, scoped agent grants. Marks follow ArchMail’s language — slate plate, cream glyph, Apple keyline <strong>824/1024</strong> — with a Gent pip instead of an archive doorway.</p>
  </header>
  <div class="toolbar">
    <label for="bg">Stage</label>
    <select id="bg">
      <option value="light" selected>Light desk</option>
      <option value="dock">Dock gray</option>
      <option value="dark">Dark</option>
    </select>
  </div>
  <section class="hero">
    <div class="stage" id="stage">
      <img class="hero-icon" id="heroIcon" src="preview-companion-512.png" width="280" height="280" alt="Selected icon" />
    </div>
    <div class="detail">
      <div>
        <div class="num" id="dNum">01</div>
        <h2 id="dTitle">Companion</h2>
      </div>
      <p class="blurb" id="dBlurb">Folded letter with a companion pip</p>
      <p class="principle" id="dPrinciple">ArchMail envelope language. Pip is the Gent. Two shapes, one idea.</p>
      <div class="wordmark">
        <img id="wmIcon" src="preview-companion-128.png" width="48" height="48" alt="" />
        <div>
          <span class="name">MailGent</span>
          <span class="tag">On-device mail companion</span>
        </div>
      </div>
      <div class="sizes" id="sizes">
        <figure><img id="s16" src="preview-companion-16.png" width="16" height="16" alt="" /><figcaption>16</figcaption></figure>
        <figure><img id="s32" src="preview-companion-32.png" width="32" height="32" alt="" /><figcaption>32</figcaption></figure>
        <figure><img id="s128" src="preview-companion-128.png" width="64" height="64" alt="" /><figcaption>128</figcaption></figure>
        <figure><img id="s512" src="preview-companion-512.png" width="96" height="96" alt="" /><figcaption>512</figcaption></figure>
      </div>
      <div class="ship" id="ship">Scripts/AppIcon/run.sh 1</div>
    </div>
  </section>
  <main class="grid">
$cards
  </main>
  <footer>
    All four variants pass Apple tile ratio <strong>0.8047 ± 0.015</strong> (corners transparent).
    Gallery install defaults to <strong>1 · Companion</strong>. Ship any: <code>Scripts/AppIcon/run.sh N</code>.
  </footer>
  <nav class="switcher" aria-label="Variant switcher">
$switcher
  </nav>
<script>
  const params = new URLSearchParams(location.search);
  let current = params.get('variant') || '1';

  function select(design) {
    current = String(design);
    const card = document.querySelector('.card[data-design=\"' + current + '\"]');
    if (!card) return;
    const name = card.dataset.name;
    const title = card.dataset.title;
    const blurb = card.dataset.blurb;
    const principle = card.dataset.principle;
    document.querySelectorAll('.card').forEach(c => c.classList.toggle('selected', c === card));
    document.querySelectorAll('.sw').forEach(b => b.classList.toggle('active', b.dataset.design === current));
    document.getElementById('heroIcon').src = 'preview-' + name + '-512.png';
    document.getElementById('wmIcon').src = 'preview-' + name + '-128.png';
    document.getElementById('s16').src = 'preview-' + name + '-16.png';
    document.getElementById('s32').src = 'preview-' + name + '-32.png';
    document.getElementById('s128').src = 'preview-' + name + '-128.png';
    document.getElementById('s512').src = 'preview-' + name + '-512.png';
    document.getElementById('dNum').textContent = String(current).padStart(2, '0');
    document.getElementById('dTitle').textContent = title;
    document.getElementById('dBlurb').textContent = blurb;
    document.getElementById('dPrinciple').textContent = principle;
    document.getElementById('ship').textContent = 'Scripts/AppIcon/run.sh ' + current;
    const url = new URL(location.href);
    url.searchParams.set('variant', current);
    history.replaceState(null, '', url);
  }

  document.querySelectorAll('.pick').forEach(btn => {
    btn.addEventListener('click', () => select(btn.dataset.design));
  });
  document.querySelectorAll('.sw').forEach(btn => {
    btn.addEventListener('click', () => select(btn.dataset.design));
  });
  document.getElementById('bg').addEventListener('change', (e) => {
    const stage = document.getElementById('stage');
    stage.classList.remove('dock', 'dark');
    if (e.target.value === 'dock') stage.classList.add('dock');
    if (e.target.value === 'dark') stage.classList.add('dark');
  });
  select(current);
</script>
</body>
</html>
EOF

  echo
  echo "ALL GREEN — gallery → $HTML"
  echo "Open: open \"$HTML\""
  exit 0
fi

run_one "$MODE" "$ICONSET"
echo "== icns =="
install_icns "$ICONSET"
echo "ALL GREEN"

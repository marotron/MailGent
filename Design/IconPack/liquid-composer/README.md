# Charge layers for Liquid Composer

Icon loop (candidates before AppIcon): `docs/agents/app-icon.md`.

Drop these into [Liquid Composer](https://liquid-composer.vercel.app/). SVG, not PNG — raster import turns glass off.

Same 1024×1024 viewBox on every file so they register. Default layer scale 80% ≈ Apple 824 keyline.

## Stack

Drop in this order. Newest layer sits on top.

1. `00-overcast.svg` — letter-envelope ghost, slightly larger, darker slate
2. `00-envelope-body.svg` — rounded rect (the paper), mid slate
3. `01-bowl.svg` — lower V
4. `02-field-solid.svg` — upper shield, no holes
5. `06-sparkle-back-large.svg` / `07-sparkle-back-mid.svg` / `08-sparkle-back-small.svg` — disc behind each sparkle
6. `03-sparkle-large.svg` / `04-sparkle-mid.svg` / `05-sparkle-small.svg`

(`00-combined.svg` and `00-envelope.svg` are convenience dumps — skip them when dropping the split stack. `00-envelope-flap.svg` is unused.)

Paint order in the `.icon` (front first, ictool 1.2): **Sparkles** → **Foreground** → **Envelope** → **Overcast**. Envelope/overcast use a slate fill, no glass, so they read as a different shade than the cream charge. Each sparkle sits on its own disc.

Background: hue **214**, tint **28**, brightness **72**, angle **90**. That is the dusty slate from shield-02.

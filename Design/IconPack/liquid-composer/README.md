# Charge layers for Liquid Composer

Drop these into [Liquid Composer](https://liquid-composer.vercel.app/). SVG, not PNG — raster import turns glass off.

Same 1024×1024 viewBox on every file so they register. Default layer scale 80% ≈ Apple 824 keyline.

## Stack (matches the pick)

Drop in this order. Newest layer sits on top.

1. `01-bowl.svg` — lower V
2. `02-field.svg` — upper shield, sparkles punched as holes

Group both. Glass stays on. Fill none (cream is in the SVG).

Background: hue **214**, tint **28**, brightness **72**, angle **90**. That is the dusty slate from shield-02.

## Optional extra glass

Drop on top of the field if you want sparkles as their own glass, not holes:

1. `01-bowl.svg`
2. `02-field-solid.svg` (no holes)
3. `03-sparkle-large.svg`
4. `04-sparkle-mid.svg`
5. `05-sparkle-small.svg`

`00-combined.svg` is one layer if you only want a single glyph.

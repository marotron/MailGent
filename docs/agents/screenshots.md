# Screenshots (fixture fake data → release strip)

How README / `docs/screenshots/` images are produced, and what Release CI does with the helpers.

## Roles

| Who | Does what |
|-----|-----------|
| **You (local)** | Capture PNGs with DEBUG fixture mail + demo grants/rules |
| **GitHub Actions** | On `v*` tags, strip screenshot-only scaffolding from the checkout, then build the DMG |

Do **not** capture screenshots on hosted runners. Do **not** ship real Mail / live grants in docs images.

## Local capture

1. Refresh fixture + plant two-account Cursor policy (Shared rules A–D → “Used on 2 placements”):

   ```bash
   make screenshots
   # or auto-write under dist/screenshots/:
   make screenshots-ci
   ```

2. App launches Debug with `MAILGENT_SCREENSHOT_POLICY=1` (backs up live `grants.json` / `rules.json`, plants demo policy on fixture accounts `work` + `personal`).

3. Capture windows (⇧⌘5 → Window) into `docs/screenshots/` as needed, e.g.:

   - `control-center.png`
   - `grant-desk-scope.png` / `grant-desk-access.png` / `grant-desk-rules.png` / `grant-desk-privacy.png`
   - `access-log.png` (optional this pass)

4. Update `README.md` screenshot captions with the version they were captured in, e.g. `<b>Menu bar</b> <i>(v0.11.5)</i> — …`.

5. Optional HQ refs: `docs/agents/assets/refs/<MARKETING_VERSION>/` (and `-hq/` if you keep originals).

5. Companion → Last ingest → **Restore real policy** (or quit after restore) so live grants/rules come back.

Manual alternate: Companion → Fixture → **Load screenshot policy** / **Restore real policy** (DEBUG card).

## What stays in git (DEBUG helpers)

Marked `SCREENSHOT_DEMO_POLICY` — kept so the next docs pass is cheap:

- `MailGent/CompanionDemoPolicy.swift` — fake grants + Shared rules A–D
- `MailGent/CompanionScreenshotDemo.swift` — scene / ready-marker for auto-capture
- `#if DEBUG` hooks in `AgentBridge`, `CompanionSession`, `CompanionWindow`, `GrantDeskView`
- `MailGentTests/CompanionDemoPolicyTests.swift`
- `Scripts/release/screenshots.sh`, `Scripts/release/capture-named-window.swift`
- `make screenshots` / `make screenshots-ci`

Fixture mail itself (`CompanionFixture`, `MailSourceID.fixture`) is general DEBUG, not screenshot-only. Release binaries already omit fixture via `#if DEBUG`.

## Release CI (strip, then DMG)

On tag push, [`.github/workflows/release.yml`](../../.github/workflows/release.yml):

1. `Scripts/release/strip-screenshot-demo-policy.sh` — deletes demo-policy sources/scripts and scrubs marked `#if DEBUG` blocks from the **runner checkout only**
2. `make dmg` — Release package (no screenshot scaffolding in that build tree)

The helpers remain on `main` / the tag commit for the next local screenshot pass. The strip does not rewrite git history.

## Retire permanently (v1 / when done)

```bash
Scripts/release/strip-screenshot-demo-policy.sh
# then commit the cleaned tree, or:
grep -rn SCREENSHOT_DEMO_POLICY .
xcodegen generate
```

`grep` should be empty aside from this doc and the strip script’s own comments (optional: delete those too).

## Do not

- Run screenshot capture as a GitHub Actions job
- Leave live account UUIDs / personal mail in committed PNGs
- Bump version solely for a screenshot refresh (docs/chore — no SemVer bump)

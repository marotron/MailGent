# Dogfood — propose-send context (experimental)

Shipped as **0.21.0 alpha** behind Settings → Experimental. Schema and UI may still change.

## Enable

1. Build & run (`make run`) or install the 0.21.0 DMG.
2. Settings → General → **Allow agents to propose sending mail** (on).
3. Settings → Experimental → **Propose-send context thread** (on).
4. **Choose…** Personal vault root (folder that contains your cases).

## Agent call

Pass optional `context` on `propose_send` (see `context-thread-brainstorm.md`). When the toggle is off, `context` is ignored.

## Expect

- With `context` + toggle on → wider confirm, thin left rail (E), expand to F full, P4 spotlight on history.
- Body preview: hover **−** / **+** bottom-trailing; Formatted | Raw top-trailing.

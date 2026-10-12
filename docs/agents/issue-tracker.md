# Issue tracker: GitHub (+ local wayfinder)

**Canonical tracker for future features, fog, and deferred work:** [GitHub Issues](https://github.com/marotron/MailGent/issues) on `marotron/MailGent`.

Same pattern as QuotAI: roadmap items live on GitHub; `.scratch/` holds active wayfinder maps, specs, prototypes, and optional local mirrors.

## Labels (required on roadmap issues)

| Label | When |
|-------|------|
| `roadmap` | From a wayfinder map / product roadmap |
| `fog` | Needs grilling / product decision |
| `next-version` | Deferred past the current ship slice |
| `enhancement` / `bug` / `question` / … | Standard type (pick one) |

Create missing labels before filing:

```bash
gh label create roadmap --repo marotron/MailGent --color 0E8A16 --description "From wayfinder map / product roadmap"
gh label create fog --repo marotron/MailGent --color BFDADC --description "Needs grilling / product decision"
gh label create next-version --repo marotron/MailGent --color FBCA04 --description "Deferred to a later release"
```

## When to file a GitHub issue

File (or update) a GitHub issue when:

- A **future feature**, deferred ticket, or product fog item should outlive the current chat
- Wayfinder map **Not yet specified** / Fog items need a durable home
- A skill says **publish to the issue tracker**

Do **not** rely on new `.scratch/.../issues/*.md` alone for deferred work — GitHub is the source of truth; local files are optional mirrors for in-flight wayfinding.

## Issue body shape

Match QuotAI:

```markdown
## Summary

One or two sentences.

## Motivation / Context

Why it matters; what exists today.

## Acceptance (sketch)

- [ ] …

## Open questions

- …

## Notes

Local wayfinder ticket: `.scratch/<effort>/issues/NN-slug.md` (if any).
Blocked by / builds on #N (if any).
```

Create with `gh`:

```bash
gh issue create --repo marotron/MailGent \
  --title "Short title" \
  --label "enhancement,roadmap,next-version" \
  --body "$(cat <<'EOF'
## Summary
…
EOF
)"
```

## Local wayfinder (still used)

Active design/build sessions may keep a local effort tree:

| Path | Role |
|------|------|
| `.scratch/<effort>/map.md` | Notes / Decisions-so-far / Fog |
| `.scratch/<effort>/spec.md` | Product lock for the effort |
| `.scratch/<effort>/issues/NN-<slug>.md` | Optional local mirror while claimed |
| `.scratch/<effort>/examples/` | HTML prototypes, etc. |

Local ticket frontmatter (when a mirror exists):

- `Type:` `research` / `prototype` / `grilling` / `task`
- `Status:` `open` / `claimed` / `resolved`
- `Blocked by:` `NN` or `—`
- `GitHub:` full issue URL (required once mirrored)

Do not invent extra frontmatter keys (e.g. `Target:`) — put deferral on the GitHub issue via `next-version` (and note it in the map).

Under map **Fog** / **Deferred** / **Not yet specified**, prefer GitHub links (and optional local path). Put open questions on the GitHub issue body; the map links them instead of duplicating:

```markdown
## Fog
- Rules-from-Ask open questions → [#N](https://github.com/marotron/MailGent/issues/N)

## Deferred
- Manual redact then Allow → [#M](https://github.com/marotron/MailGent/issues/M) · [issues/02-….md](issues/02-….md)
```

### Wayfinding ops (`/wayfinder`)

- **Frontier**: open, unblocked, unclaimed local mirrors (or open GitHub issues tagged for the effort).
- **Claim**: set local `Status: claimed` (and/or assign the GitHub issue) before work.
- **Resolve**: append `## Answer` locally if mirrored; close the GitHub issue; append a gist + link to the map’s Decisions-so-far.

## Fetching a ticket

Prefer the GitHub issue number or URL (`gh issue view N --repo marotron/MailGent`). If a local mirror path is given, read that file and follow its `GitHub:` line.

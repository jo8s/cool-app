# moetikmnjasaan 🧥 

A gloriously useless single-serving web app that answers the only question that matters: **moet ik m'n jas aan?** It reads live weather (feels-like temp, rain forecast, and how the day changes) straight from [Open-Meteo](https://open-meteo.com) in the browser, and shouts a 5-level verdict — `NEE → VESTJE → JA → JA! → BLIJF BINNEN` — plus a day-ahead note when the coat category changes later ("Over 6 uur heb je geen jas meer nodig.").

Live at **[moetikmnjasaan.nl](https://moetikmnjasaan.nl)**.

## How it works

It's a single static `index.html` — no server, no backend. The JavaScript calls Open-Meteo directly from the visitor's browser.

```
push to main       → Cloudflare Workers → moetikmnjasaan.nl   (production)
push a branch / PR → Cloudflare Workers → preview URL           (review before merge)
push / PR          → GitHub Actions     → runs the tests
```

## Files

| Path | What it is |
|------|------------|
| `index.html` | the entire app (self-contained) |
| `wrangler.jsonc` | Cloudflare Workers config: serve `./dist` as static assets |
| `tests/logic.test.mjs` | zero-dependency tests: structure + coat/day-ahead logic |
| `.github/workflows/test.yaml` | runs the tests on every push and PR |

## Develop

Open `index.html` in a browser — that's it. To run the tests:

```bash
node tests/logic.test.mjs
```

## Deploy

Hosting is a **Cloudflare Worker with static assets** (a static-assets-only Worker — no server code), connected to this GitHub repo via Workers Builds. Build configuration:

- Build command: `mkdir -p dist && cp index.html dist/`
- Deploy command: `npx wrangler deploy`

`wrangler.jsonc` tells Wrangler to serve `./dist`. Every push to `main` deploys to `moetikmnjasaan.nl`. It's free, global, always-on, and serves TLS at Cloudflare's edge — no server or cluster needed.

> Set `name` in `wrangler.jsonc` to match your Worker's name.

## Review before merging

Workers Builds produces a **preview URL** for non-production branches and pull requests. So the flow is:

1. Create a branch, make your change, push it (or open a PR).
2. GitHub Actions runs the tests; Cloudflare publishes a preview URL for the branch build.
3. Open the preview URL, check it live, and when happy, **merge to main** — which deploys to production.

# moetikmnjasaan 🧥

A gloriously useless single-serving web app that answers the only question that matters: **moet ik m'n jas aan?** It reads live weather (feels-like temperature, rain forecast, and how the day changes) straight from [Open-Meteo](https://open-meteo.com) in the browser and shouts a 5-level verdict — `NEE → VESTJE → JA → JA! → BLIJF BINNEN` — plus a note when the coat category changes later in the day ("Over 6 uur heb je geen jas meer nodig.").

Live at **[moetikmnjasaan.nl](https://moetikmnjasaan.nl)**.

## How it works

It's a single static `index.html` — no server, no backend. The JavaScript calls Open-Meteo directly from the visitor's browser, so hosting is just static files.

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

Hosting is a static-assets-only Cloudflare Worker, connected to this repo via Workers Builds: build command `mkdir -p dist && cp index.html dist/`, deploy command `npx wrangler deploy`. Every push to `main` goes live at `moetikmnjasaan.nl`.

## Contributing

`main` is production. Work on a branch and open a pull request — see [CONTRIBUTING.md](CONTRIBUTING.md).

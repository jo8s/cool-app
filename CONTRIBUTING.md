# Contributing

`main` is production — it deploys straight to **moetikmnjasaan.nl**. So never
commit to `main` directly; every change goes through a branch and a pull request
so you can review it on a live preview URL first.

## Workflow

```bash
# 1. Start from an up-to-date main
git checkout main && git pull

# 2. Create a branch
git checkout -b my-change

# 3. Make your change to index.html, then commit
git add -A && git commit -m "describe the change"

# 4. Push the branch
git push -u origin my-change
```

Then open a **Pull Request** (branch → `main`) on GitHub. Two checks appear:

- **GitHub Actions** runs the tests (`tests/logic.test.mjs`).
- **Cloudflare** builds the branch and publishes a **preview URL** — open it to
  see your change live, without touching production.

When the preview looks good and tests pass, **merge the PR into `main`**. That
deploys to production automatically.

## Run the tests locally

```bash
node tests/logic.test.mjs
```

## Golden rule

Branch → push → check the preview → merge the PR. No direct pushes to `main`.

# moetikeenjasaan 🧥

A gloriously useless single-serving web app that answers the only question that matters: **moet ik een jas aan?** It reads live weather (feels-like temp + rain forecast, via [Open-Meteo](https://open-meteo.com)) and shouts a 5-level verdict — `NEE → VESTJE → JA → JA! → BLIJF BINNEN`.

This repo is also a complete **GitOps** demo: tested and containerized by GitHub Actions, promoted through **dev → staging → prod**, and deployed by **Argo CD** into a local **kind** cluster.

## Architecture

```
 push to main ─► [test] ─► [build multi-arch :sha] ─► [deploy-dev]  (auto)
                                                            └─► [promote-staging] (auto)
                                                                   └─► [open-prod-pr] (auto)
                                                                          │
                                                    you review + merge the PR ─► prod

 Argo CD ApplicationSet ─► watches k8s/overlays/{dev,staging,prod}:
   dev      ns moetikeenjasaan-dev      · dev.localhost
   staging  ns moetikeenjasaan-staging  · staging.localhost
   prod     ns moetikeenjasaan-prod     · moetikeenjasaan.nl
```

Each environment is its own namespace + Kustomize overlay. CI writes the built image's `:<sha>` tag into the relevant overlay; Argo CD auto-syncs whatever git says. The only human gate is an **approval** on the prod-promotion workflow — Argo itself just follows git.

The image and repo are **private**, so a GitHub PAT drives the cluster's image-pull secrets and Argo CD's repo access.

## Layout

| Path | What it is |
|------|------------|
| `index.html` | the app (single self-contained file) |
| `tests/logic.test.mjs` | CI tests: structural checks + coat-logic assertions |
| `Dockerfile`, `nginx.conf` | container image (nginx + `/healthz`) |
| `.github/workflows/build.yaml` | test → build → deploy-dev → promote-staging → open prod PR |
| `k8s/base/` | shared Deployment, Service, Ingress |
| `k8s/overlays/{dev,staging,prod}/` | per-env namespace, replicas, host, image tag |
| `argocd/applicationset.yaml` | one ApplicationSet → generates the 3 env Apps |
| `argocd/ingress.yaml` | ingress for the Argo CD UI |
| `kind-config.yaml` | kind cluster with ingress port mappings (8080/8443) |
| `scripts/setup.sh` | bootstrap cluster + ingress + Argo CD + secrets + ApplicationSet |
| `scripts/teardown.sh` | delete the cluster |
| `scripts/render.sh` | stamp owner/repo into manifests (already done for `jo8s/cool-app`) |

## Prerequisites

- `kind`, `kubectl`, `argocd` CLI, and **Podman** (already installed on your machine)
- A **GitHub PAT (classic)** with scopes `repo` + `workflow` + `read:packages`

## One-time GitHub setup

1. Push the repo (first push triggers CI, which builds the image and writes the dev/staging tags):

   ```bash
   git add -A && git commit -m "GitOps: overlays + pipeline"
   git push -u origin main
   ```

2. Settings → Actions → General → Workflow permissions → **Read and write**, and tick **Allow GitHub Actions to create and approve pull requests** (the prod promotion opens a PR).

The prod gate is **PR-based** — the `promote-prod` workflow opens a pull request that bumps the prod image tag; you merge it to deploy. This needs no paid plan and works on private repos.

## Deploy locally

```bash
export GITHUB_PAT=ghp_your_token_here     # repo + workflow + read:packages
./scripts/setup.sh
```

Creates a clean kind cluster (Podman), installs ingress-nginx and Argo CD, wires the image-pull + repo secrets for all three namespaces, and applies the ApplicationSet. Argo then syncs each env.

| Env | URL |
|-----|-----|
| dev | http://dev.localhost:8080/ |
| staging | http://staging.localhost:8080/ |
| prod | http://moetikeenjasaan.nl:8080/ |

`*.localhost` resolves to loopback in Chrome/Firefox automatically. For prod's real hostname, add a hosts entry:

```bash
echo "127.0.0.1 moetikeenjasaan.nl www.moetikeenjasaan.nl" | sudo tee -a /etc/hosts
```

### Argo CD UI

Exposed via ingress at **http://argocd.localhost:8080** (user `admin`):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

## The promotion flow

1. Edit `index.html`, commit, push.
2. CI runs the tests, builds a multi-arch image, **auto-deploys to dev**, **auto-promotes to staging**, and **auto-opens a "Promote to prod" PR** with the same image.
3. Verify staging at http://staging.localhost:8080/.
4. When happy, open the **Promote to prod** PR (branch `promote-prod`), review the one-line tag diff, and **merge**. Argo CD then rolls prod out.

There's always a single rolling `promote-prod` PR that reflects the latest staging build — merging it is your manual approval. Nothing is applied by hand; every deploy is a git commit Argo reconciles.

For this to work, enable Settings → Actions → General → **Allow GitHub Actions to create and approve pull requests**.

## Going public (later)

The prod overlay is already wired for `moetikeenjasaan.nl`. A real public launch additionally needs:

- a cluster reachable from the internet (managed k8s, or kind behind a tunnel) with a real LoadBalancer / public IP;
- **DNS**: `A`/`AAAA` records for `moetikeenjasaan.nl` and `www` pointing at that IP;
- **TLS**: install `cert-manager` + a Let's Encrypt `ClusterIssuer`, then add a `tls:` block and the `cert-manager.io/cluster-issuer` annotation to the prod ingress.

## Tear down

```bash
./scripts/teardown.sh
```

# moetikeenjasaan 🧥

A gloriously useless single-serving web app that answers the only question that matters: **moet ik een jas aan?** It reads live weather (feels-like temp + rain forecast, via [Open-Meteo](https://open-meteo.com)) and shouts a 5-level verdict — `NEE → VESTJE → JA → JA! → BLIJF BINNEN`.

This repo is also a complete **GitOps** demo: containerized, built by GitHub Actions, and deployed by **Argo CD** into a local **kind** cluster.

## Architecture

```
 git push ──► GitHub Actions ──► build image ──► ghcr.io/jo8s/cool-app:<sha>
                     │
                     └─► kustomize edit set image ──► commit back to main
                                                          │
 kind cluster ◄── Argo CD (auto-sync) ◄── watches k8s/base in this repo
      │
      └─ ingress-nginx ──► http://localhost/
```

The app image and this repo are **private**, so a GitHub PAT is used for the cluster's image-pull secret and for Argo CD's repo access.

## Files

| Path | What it is |
|------|------------|
| `index.html` | the app (single self-contained file) |
| `Dockerfile`, `nginx.conf` | container image (nginx serving the static file + `/healthz`) |
| `.github/workflows/build.yaml` | CI: build → push to ghcr.io → write image tag back |
| `k8s/base/` | Kustomize manifests: Deployment, Service, Ingress |
| `argocd/application.yaml` | the Argo CD Application |
| `kind-config.yaml` | kind cluster with ingress port mappings |
| `scripts/setup.sh` | bootstrap cluster + ingress + Argo CD + secrets + app |
| `scripts/teardown.sh` | delete the cluster |
| `scripts/render.sh` | stamp owner/repo into manifests (already done for `jo8s/cool-app`) |

## Prerequisites

- `kind`, `kubectl`, `argocd` CLI, and **Podman** (already installed on your machine)
- A **GitHub PAT (classic)** with scopes `repo` + `read:packages`

## One-time: push this repo

```bash
git init -b main
git add -A
git commit -m "initial: app + GitOps setup"
git remote add origin https://github.com/jo8s/cool-app.git
git push -u origin main
```

The first push triggers the workflow, which builds `ghcr.io/jo8s/cool-app` and commits the image tag into `k8s/base/kustomization.yaml`. Make sure Actions has package permissions (Settings → Actions → General → Workflow permissions → **Read and write**).

## Deploy locally

```bash
export GITHUB_PAT=ghp_your_token_here     # repo + read:packages
./scripts/setup.sh
```

That creates a clean kind cluster (Podman), installs ingress-nginx and Argo CD, wires the private image-pull + repo secrets, and applies the Argo CD Application. Argo then syncs the app in automatically.

Open **http://localhost/**.

### Argo CD UI

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# https://localhost:8080  — user: admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### Rootless Podman note

Binding host port 80 may be blocked for rootless Podman. Allow it once:

```bash
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-kind.conf
sudo sysctl --system
```

## The GitOps loop

Edit `index.html`, then:

```bash
git commit -am "tweak the coat one-liners" && git push
```

CI rebuilds the image, writes the new `:<sha>` tag into the manifest, and Argo CD rolls it out — no `kubectl apply` by hand.

## Tear down

```bash
./scripts/teardown.sh
```

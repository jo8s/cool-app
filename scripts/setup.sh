#!/usr/bin/env bash
# One-shot local bootstrap for the dev/staging/prod GitOps setup:
#   1. create a clean kind cluster (Podman provider) with ingress port mappings
#   2. install ingress-nginx (kind variant)
#   3. install Argo CD (+ expose it via ingress in insecure mode)
#   4. create the three app namespaces + private ghcr image-pull secrets
#   5. register the private git repo with Argo CD
#   6. apply the ApplicationSet (generates dev/staging/prod Applications)
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f config.env ]]; then
  # shellcheck disable=SC1091
  source config.env
fi

: "${GITHUB_OWNER:?Set GITHUB_OWNER (config.env or env)}"
: "${GITHUB_REPO:?Set GITHUB_REPO (config.env or env)}"
: "${GITHUB_PAT:?Set GITHUB_PAT (a PAT with repo + read:packages)}"

CLUSTER="cool-app"
APP_NAMESPACES=(moetikeenjasaan-dev moetikeenjasaan-staging moetikeenjasaan-prod)

# kind + Podman: kind needs to be told to use the podman provider.
export KIND_EXPERIMENTAL_PROVIDER=podman

echo "==> [1/6] Creating kind cluster '${CLUSTER}' (Podman)"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "    cluster already exists, skipping"
else
  kind create cluster --name "$CLUSTER" --config kind-config.yaml
fi

echo "==> [2/6] Installing ingress-nginx"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
echo "    waiting for ingress controller..."
kubectl -n ingress-nginx wait --for=condition=available deployment/ingress-nginx-controller --timeout=180s || \
kubectl -n ingress-nginx wait --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s

echo "==> [3/6] Installing Argo CD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# server-side apply: the ApplicationSet CRD is too large for client-side apply.
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
echo "    waiting for Argo CD server..."
kubectl -n argocd wait --for=condition=available deployment/argocd-server --timeout=300s

echo "    exposing Argo CD via ingress (insecure mode for nginx TLS termination)"
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout status deployment argocd-server --timeout=180s
kubectl apply -f argocd/ingress.yaml

echo "==> [4/6] Creating app namespaces + ghcr image-pull secrets"
for ns in "${APP_NAMESPACES[@]}"; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$ns" create secret docker-registry ghcr-pull \
    --docker-server=ghcr.io \
    --docker-username="$GITHUB_OWNER" \
    --docker-password="$GITHUB_PAT" \
    --docker-email="unused@example.com" \
    --dry-run=client -o yaml | kubectl apply -f -
done

echo "==> [5/6] Registering private repo with Argo CD"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-${GITHUB_REPO}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git
  username: ${GITHUB_OWNER}
  password: ${GITHUB_PAT}
EOF

echo "==> [6/6] Applying Argo CD root app (app-of-apps)"
# Migrate off the old single-namespace app if it's still around.
kubectl -n argocd delete application moetikeenjasaan --ignore-not-found
kubectl delete namespace moetikeenjasaan --ignore-not-found
# The root app watches argocd/ and manages the ApplicationSet, the cloudflared
# app, and the Argo CD ingress. We only bootstrap this one Application.
kubectl apply -f argocd/root.yaml

# Cloudflare Tunnel secret (kept out of git). The cloudflared *Application* is
# managed by the root app; it just needs this secret to become healthy.
if [[ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
  echo "==> [+] Creating Cloudflare Tunnel secret"
  kubectl create namespace cloudflared --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n cloudflared create secret generic cloudflared-token \
    --from-literal=token="$CLOUDFLARE_TUNNEL_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "==> [+] No CLOUDFLARE_TUNNEL_TOKEN set — cloudflared will wait for the secret."
fi

cat <<EOF

============================================================
 Setup complete.

 Apps (after Argo syncs):
   dev      http://dev.localhost:8080/
   staging  http://staging.localhost:8080/
   prod     http://moetikmnjasaan.nl:8080/   (needs an /etc/hosts entry:)
              echo "127.0.0.1 moetikmnjasaan.nl www.moetikmnjasaan.nl" | sudo tee -a /etc/hosts

 Watch all envs:
   kubectl get pods -A -l app=moetikeenjasaan -w

 Argo CD UI (via ingress, no port-forward):
   open http://argocd.localhost:8080  (user: admin)
   password:
     kubectl -n argocd get secret argocd-initial-admin-secret \\
       -o jsonpath='{.data.password}' | base64 -d; echo

 Ingress is mapped to high ports for rootless Podman (8080/8443).
============================================================
EOF

#!/usr/bin/env bash
# One-shot local bootstrap:
#   1. create a clean kind cluster (Podman provider) with ingress port mappings
#   2. install ingress-nginx (kind variant)
#   3. install Argo CD
#   4. create the app namespace + private ghcr image-pull secret
#   5. register the private git repo with Argo CD
#   6. apply the Argo CD Application (which syncs the app in)
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
APP_NS="moetikeenjasaan"
OWNER_LC="$(printf '%s' "$GITHUB_OWNER" | tr '[:upper:]' '[:lower:]')"

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
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
echo "    waiting for Argo CD server..."
kubectl -n argocd wait --for=condition=available deployment/argocd-server --timeout=300s

echo "==> [4/6] Creating app namespace + ghcr image-pull secret"
kubectl create namespace "$APP_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$APP_NS" create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username="$GITHUB_OWNER" \
  --docker-password="$GITHUB_PAT" \
  --docker-email="unused@example.com" \
  --dry-run=client -o yaml | kubectl apply -f -

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

echo "==> [6/6] Applying Argo CD Application"
kubectl apply -f argocd/application.yaml

cat <<EOF

============================================================
 Setup complete.

 App URL (after Argo syncs):   http://localhost/

 Watch the sync:
   kubectl -n ${APP_NS} get pods -w

 Argo CD UI:
   kubectl -n argocd port-forward svc/argocd-server 8080:443
   open https://localhost:8080  (user: admin)
   password:
     kubectl -n argocd get secret argocd-initial-admin-secret \\
       -o jsonpath='{.data.password}' | base64 -d; echo

 Note (rootless Podman): if binding host port 80 fails, allow it once:
   echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-kind.conf
   sudo sysctl --system
 ...then re-run this script.
============================================================
EOF

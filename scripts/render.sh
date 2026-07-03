#!/usr/bin/env bash
# Stamp your real GitHub owner/repo into the manifests (replaces __GH_OWNER__/
# __GH_REPO__ placeholders). Run once, then commit + push the result so Argo CD
# reads the correct values from GitHub.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f config.env ]]; then
  # shellcheck disable=SC1091
  source config.env
fi

: "${GITHUB_OWNER:?Set GITHUB_OWNER (in config.env or the environment)}"
: "${GITHUB_REPO:?Set GITHUB_REPO (in config.env or the environment)}"

# ghcr.io image paths must be lowercase.
OWNER_LC="$(printf '%s' "$GITHUB_OWNER" | tr '[:upper:]' '[:lower:]')"
REPO_LC="$(printf '%s' "$GITHUB_REPO" | tr '[:upper:]' '[:lower:]')"

FILES=(
  "k8s/base/kustomization.yaml"
  "argocd/application.yaml"
)

for f in "${FILES[@]}"; do
  # repoURL keeps original case; image path uses lowercase.
  sed -i.bak \
    -e "s|__GH_OWNER__/__GH_REPO__.git|${GITHUB_OWNER}/${GITHUB_REPO}.git|g" \
    -e "s|ghcr.io/__GH_OWNER__/__GH_REPO__|ghcr.io/${OWNER_LC}/${REPO_LC}|g" \
    -e "s|__GH_OWNER__|${GITHUB_OWNER}|g" \
    -e "s|__GH_REPO__|${GITHUB_REPO}|g" \
    "$f"
  rm -f "$f.bak"
  echo "rendered: $f"
done

echo
echo "Done. Review the changes, then commit and push:"
echo "  git add -A && git commit -m 'chore: set owner/repo' && git push"

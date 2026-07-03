#!/usr/bin/env bash
# Delete the local kind cluster and everything in it.
set -euo pipefail
export KIND_EXPERIMENTAL_PROVIDER=podman
CLUSTER="cool-app"
echo "==> Deleting kind cluster '${CLUSTER}'"
kind delete cluster --name "$CLUSTER"
echo "Done."

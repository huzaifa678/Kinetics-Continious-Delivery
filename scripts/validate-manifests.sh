#!/usr/bin/env bash
# Strict manifest validation with CUE.
#
# 1. Renders the training-job Helm chart (both default and FSx-enabled) and
#    vets every rendered document against cue/schema.cue#Resource.
# 2. Vets all static GitOps manifests the same way.
#
# Any unknown field, wrong type, or missing required key fails the build.
# Requires: helm, cue.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_DIR="$ROOT/cue"
CHART="$ROOT/helm/training-job"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Drop empty/comment-only documents (helm emits a null doc per rendered file)
# then vet each remaining document against #Resource.
vet() { # <file>
  local clean="$TMP/clean-$(basename "$1")"
  python3 -c "import sys,yaml; yaml.safe_dump_all([d for d in yaml.safe_load_all(open(sys.argv[1])) if d], sys.stdout)" "$1" > "$clean"
  # Skip files that reduced to nothing.
  [ -s "$clean" ] || { echo "  skip $1 (no resources)"; return 0; }
  echo "  vet $1"
  cue vet "$SCHEMA_DIR/schema.cue" "$clean" -d '#Resource' -p manifests
}

echo "==> Rendering Helm chart (default values)"
helm template kinetics "$CHART" > "$TMP/render-default.yaml"
vet "$TMP/render-default.yaml"

echo "==> Rendering Helm chart (FSx PV/PVC enabled)"
helm template kinetics "$CHART" \
  --set data.fsx.create=true \
  --set data.fsx.fsxId=fs-0123456789abcdef0 \
  --set data.fsx.mountName=abcdefgh \
  --set data.fsx.dnsName=fs-0123456789abcdef0.fsx.us-east-1.amazonaws.com \
  > "$TMP/render-fsx.yaml"
vet "$TMP/render-fsx.yaml"

echo "==> Rendering in-repo Karpenter config chart"
helm template karpenter-config "$ROOT/gitops/config/karpenter" > "$TMP/render-karpenter-config.yaml"
vet "$TMP/render-karpenter-config.yaml"

echo "==> Rendering in-repo HyperPod Karpenter config chart"
helm template hyperpod-karpenter "$ROOT/gitops/config/hyperpod-karpenter" > "$TMP/render-hyperpod-karpenter.yaml"
vet "$TMP/render-hyperpod-karpenter.yaml"

echo "==> Rendering in-repo Seldon experiment chart (Server + Models + Experiment)"
helm template seldon-experiment "$ROOT/gitops/config/seldon-experiment" > "$TMP/render-seldon-experiment.yaml"
vet "$TMP/render-seldon-experiment.yaml"

echo "==> Linting in-repo inference-service chart"
helm lint "$ROOT/helm/inference-service"
helm lint "$ROOT/helm/inference-service" --set seldon.enabled=false

# The etl-shards chart now emits an Argo WorkflowTemplate (+ ServiceAccount).
# Render and vet it against #Resource (which includes #WorkflowTemplate).
echo "==> Rendering + vetting in-repo etl-shards chart"
helm template etl-shards "$ROOT/helm/etl-shards" > "$TMP/render-etl-shards.yaml"
vet "$TMP/render-etl-shards.yaml"

echo "==> Vetting bootstrap ApplicationSet + standalone Applications"
for f in "$ROOT"/gitops/bootstrap/*.yaml "$ROOT"/gitops/apps/*.yaml; do
  vet "$f"
done

# NOTE: gitops/environments/**/env.yaml and gitops/<category>/<app>/app.yaml are
# ApplicationSet *input data* (not Kubernetes manifests) and are intentionally
# NOT vetted against #Resource.

echo "All manifests valid."

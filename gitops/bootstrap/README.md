# ArgoCD bootstrap

One-time, out-of-band setup that points ArgoCD at this repo. Everything after is
GitOps-managed. Run against a cluster whose EKS API you can reach (prod is locked
to the VPN egress, so run from the VPN — or from the VPC self-hosted runner).

Terraform owns the EKS cluster, IAM, and AWS-side Pod Identity associations. With
`manage_argocd = true` (needs the VPC runner), **Terraform now installs ArgoCD +
the in-cluster env Secret + the app-of-apps**, so steps 0–2 below are only needed
when bootstrapping ArgoCD manually (`manage_argocd = false`).

## Manual bootstrap order (when not TF-managed)

```bash
# 0. Install ArgoCD (once). Bake in the submodule fix Terraform sets automatically:
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argocd argo/argo-cd -n argocd --create-namespace \
  --set-string 'repoServer.env[0].name=ARGOCD_GIT_MODULES_ENABLED' \
  --set-string 'repoServer.env[0].value=false'

# 1. Register the in-cluster with its environment label (the ApplicationSet's
#    clusters generator matches this; without it, zero Applications generate).
kubectl apply -f gitops/bootstrap/clusters/prod.yaml     # or dev.yaml

# 2. Apply the app-of-apps (ApplicationSet + standalone root). Non-recursive, so
#    the clusters/ and secrets/ subdirs are intentionally skipped.
kubectl apply -f gitops/bootstrap/
```

## Image Updater git write credential (required for image bumps)

ArgoCD Image Updater commits image-tag bumps back to this repo (the workload Apps
use `write-back-method: git`). Give it a write credential once:

```bash
cp gitops/bootstrap/secrets/cd-repo-write-creds.example.yaml /tmp/creds.yaml
# fill username + a GitHub token with repo contents:write, then:
kubectl apply -f /tmp/creds.yaml
```

## The VPC self-hosted runner (infra repo)

The runner that lets CI reach the locked EKS API is bootstrapped from the infra
repo (`kinetics-pipeline`), not here:

```bash
RUNNER_PAT=github_pat_xxx ./scripts/bootstrap-runner.sh   # ENVIRONMENT=prod default
```

## Verify

```bash
kubectl -n argocd get applicationset          # kinetics-platform
kubectl -n argocd get applications.argoproj.io   # infra/* + apps/* generate + sync
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=cluster --show-labels
```

If Applications show `ComparisonError` / repo-not-accessible, apply the repo
credential above (private repo, or Image Updater needs write).

## Contents

| Path | Purpose |
|---|---|
| `applicationset.yaml` | Generates an Application per chart under `gitops/infra/*` and `gitops/observability/*`. |
| `root-apps.yaml` | App-of-apps for the standalone Applications under `gitops/apps/`. |
| `clusters/<env>.yaml` | In-cluster registration Secret carrying the `environment` label (step 1). |
| `secrets/cd-repo-write-creds.example.yaml` | Template for the ArgoCD repo write credential (Image Updater). |

# ArgoCD Image Updater — opt-in usage

This is installed **capability-only**. By default the CI push pipeline
(`docker-build.yml` → `update-gitops.yml`) is the active writer of every image
tag, and Image Updater does nothing.

> **One writer per field.** A given `.image.tag` can be bumped by *either* CI *or*
> Image Updater — never both, or they fight (oscillating git commits). To adopt
> Image Updater for an app, add the annotations below **and** disable that app's
> CI bump job in `docker-build.yml` (e.g. comment out `bump-inference`).

It only watches **container images**. The Seldon `Model` `storageUri`s (model
versions from the MLflow registry) are not images — keep resolving those with
`training/deploy/resolve_seldon_uri.py` + `update-gitops.yml` regardless.

## Opt in per app

Add to the relevant ArgoCD `Application` `metadata.annotations`. Tags are SHA-based
(not semver), so use the `newest-build` strategy with a per-prefix `allow-tags`
regex. Write-back is to git (keeps GitOps as source of truth).

### inference edge (`serve-` tag)
```yaml
argocd-image-updater.argoproj.io/image-list: edge=533267178572.dkr.ecr.us-east-1.amazonaws.com/kinetics-training
argocd-image-updater.argoproj.io/edge.update-strategy: newest-build
argocd-image-updater.argoproj.io/edge.allow-tags: regexp:^serve-
argocd-image-updater.argoproj.io/edge.helm.image-name: image.repository
argocd-image-updater.argoproj.io/edge.helm.image-tag: image.tag
argocd-image-updater.argoproj.io/write-back-method: git
```

### seldon server (`seldon-` tag) — kinetics-experiment app
Same as above with `allow-tags: regexp:^seldon-` (the chart now uses the same
`.image.{repository,tag}` keys).

### training (`sha-` tag) — kinetics-training app
Same with `allow-tags: regexp:^sha-`. Note this app is **manual-sync**, so a tag
bump is only *recorded* (no GPU run launches) — Image Updater's git write-back
respects that.

## Verify before relying on it

- **AWS CLI in the runtime.** The ECR auth script calls `aws`. Confirm the
  `argocd-image-updater` image has the AWS CLI; if not, add it via a sidecar/init
  container, or fall back to a pull-secret refresh CronJob.
- **Pod Identity.** ECR read is granted by the EKS Pod Identity association in
  Terraform (`modules/iam` role + `modules/addons` association) bound to the
  `argocd-image-updater` SA in the `argocd` namespace — no IRSA annotation.
- **Git write-back credential.** Write-back commits to the CD repo, so the
  controller needs a git credential (reuse the GitHub App or an SSH key).

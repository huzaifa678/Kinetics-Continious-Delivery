.PHONY: tf-init tf-validate tf-plan validate-manifests validate lint \
        etl-render etl-run

TF_DIR := terraform

## Terraform
tf-init:
	cd $(TF_DIR) && terraform init

tf-validate:
	cd $(TF_DIR) && terraform fmt -recursive -check && terraform validate

tf-plan:
	cd $(TF_DIR) && terraform plan

## Strict manifest validation (helm render + gitops) against cue/schema.cue
validate-manifests:
	./scripts/validate-manifests.sh

## Everything CI should gate on
validate: tf-validate validate-manifests

lint: validate

## ETL ─────────────────────────────────────────────────────────────────────────
# ETL_NS  — Argo Workflows namespace (default: argo).
# ETL_ENV — ArgoCD environment label on the target cluster (dev or prod).
ETL_NS  ?= argo
ETL_ENV ?= dev

## Render the etl-shards Helm chart and print the WorkflowTemplate manifests.
## Useful for a dry-run review before syncing via ArgoCD.
##   make etl-render
##   make etl-render ETL_ENV=prod
etl-render:
	helm template etl-shards helm/etl-shards \
	  --namespace $(ETL_NS) \
	  -f gitops/environments/$(ETL_ENV)/values/etl-shards.yaml

## Submit an Argo Workflow from the reconciled WorkflowTemplate.
## Prerequisites: argo CLI in PATH, kubeconfig pointing at the right cluster,
##               ArgoCD has synced the etl-shards Application at least once.
##
##   make etl-run                     # dev, default params
##   make etl-run ETL_ENV=prod        # prod, full parallelism
##   make etl-run ARGO_FLAGS="--watch" # stream logs until completion
etl-run:
	argo submit \
	  --from workflowtemplate/etl-shards-build \
	  --namespace $(ETL_NS) \
	  --serviceaccount etl-shards \
	  $(ARGO_FLAGS)

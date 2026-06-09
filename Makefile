.PHONY: tf-init tf-validate tf-plan validate-manifests validate lint

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

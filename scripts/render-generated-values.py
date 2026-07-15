#!/usr/bin/env python3
"""Render gitops/environments/<env>/values/generated/<app>.yaml from the GitOps contract.

    aws ssm get-parameter --name /kinetics-pipeline/dev/gitops-contract \
        --query Parameter.Value --output text > contract.json
    python3 scripts/render-generated-values.py --env dev --contract contract.json

WHY THIS EXISTS
    Terraform knows the checkpoint / data / MLflow bucket names, the MLflow
    tracking-server ARN, the AMP remote_write URL and the prod inference edge.
    The Helm charts need them. The old path (scripts/sync-gitops-values.sh)
    mutated hand-authored values files in place with `yq` -- generated and
    hand-authored values braided into one file, needing terraform state access,
    with the desired state invisible until someone ran the script.

    So instead: Terraform publishes a *contract* (an SSM parameter, a real
    resource with an audit trail), a workflow renders it into files, and those
    files are COMMITTED and reviewed. Git stays the only thing ArgoCD reads, and
    no human ever transcribes an ARN.

    SECRETS ARE NOT IN THE CONTRACT. Secret material reaches the cluster via
    External Secrets -> Secrets Manager. This renderer only ever sees non-secret
    identifiers, so the SSM parameter is a plain String.

LAYOUT (env-major, matches gitops/environments/<env>/values/<app>.yaml)
    templates:  gitops/environments/_generated/<app>.tpl.yaml
    output:     gitops/environments/<env>/values/generated/<app>.yaml

TEMPLATE SYNTAX
    `${key}` is substituted from the contract. An unknown key is a hard error,
    not an empty string: a chart silently rendered with `url: ""` is worse than
    a failed pipeline. (Disabled features are emitted by Terraform as "" so their
    keys still exist -- see terraform/infra/gitops-contract.tf.)

    An optional first-line directive scopes a template to some environments:
        # gitops-render-envs: prod
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

PLACEHOLDER = re.compile(r"\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}")
ENV_DIRECTIVE = re.compile(r"^#\s*gitops-render-envs:\s*(.+)$", re.MULTILINE)

HEADER = """# =============================================================================
# GENERATED FILE -- DO NOT EDIT.
#
# Rendered from the GitOps contract published by terraform/infra/gitops-contract.tf
# (SSM parameter /{project}/{env}/gitops-contract) by
# scripts/render-generated-values.py.
#
# Hand edits are overwritten by the next render-and-PR run. Change the template
# at {template} instead, or change the Terraform output that feeds it.
#
# Environment: {env}
# =============================================================================
"""


def render(template_text: str, contract: dict, path: Path) -> str:
    missing: set[str] = set()

    def sub(match: re.Match[str]) -> str:
        key = match.group(1)
        if key not in contract:
            missing.add(key)
            return match.group(0)
        return str(contract[key])

    out = PLACEHOLDER.sub(sub, template_text)
    if missing:
        raise KeyError(
            f"{path}: the contract has no key(s) {sorted(missing)}. "
            f"Available: {sorted(contract)}"
        )
    return out


def envs_for(template_text: str) -> set[str] | None:
    m = ENV_DIRECTIVE.search(template_text)
    if not m:
        return None
    return {e.strip() for e in m.group(1).split(",") if e.strip()}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", required=True, choices=["dev", "prod"])
    ap.add_argument("--contract", required=True, type=Path)
    ap.add_argument("--templates", type=Path,
                    default=Path("gitops/environments/_generated"))
    ap.add_argument("--out-root", type=Path, default=Path("gitops/environments"))
    ap.add_argument("--project", default="kinetics-pipeline")
    ap.add_argument("--check", action="store_true",
                    help="Render to memory and fail if any committed file differs. Used in MR/PR pipelines.")
    args = ap.parse_args()

    contract = json.loads(args.contract.read_text())

    if contract.get("environment") != args.env:
        print(
            f"REFUSING: contract is for environment {contract.get('environment')!r} "
            f"but --env is {args.env!r}. This is the check that stops a dev "
            f"contract being rendered into prod values.",
            file=sys.stderr,
        )
        return 2

    templates = sorted(args.templates.glob("*.tpl.yaml"))
    if not templates:
        print(f"no templates under {args.templates}", file=sys.stderr)
        return 1

    out_dir = args.out_root / args.env / "values" / "generated"
    drift: list[Path] = []
    written = 0

    for tpl in templates:
        component = tpl.name[: -len(".tpl.yaml")]
        text = tpl.read_text()

        scope = envs_for(text)
        out_path = out_dir / f"{component}.yaml"

        if scope is not None and args.env not in scope:
            if out_path.exists():
                if args.check:
                    drift.append(out_path)
                else:
                    out_path.unlink()
                    print(f"  removed {out_path}  ({component} is not rendered for {args.env})")
            continue

        try:
            body = render(text, contract, tpl)
        except KeyError as exc:
            print(f"ERROR: {exc.args[0]}", file=sys.stderr)
            return 1
        header = HEADER.format(project=args.project, env=args.env, template=tpl)
        rendered = header + body

        if args.check:
            current = out_path.read_text() if out_path.exists() else ""
            if current != rendered:
                drift.append(out_path)
            continue

        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(rendered)
        written += 1
        print(f"  wrote {out_path}")

    if args.check:
        if drift:
            print("\nGenerated values are stale:", file=sys.stderr)
            for p in drift:
                print(f"  {p}", file=sys.stderr)
            print("\nRun the render-and-PR workflow, or regenerate locally.", file=sys.stderr)
            return 1
        print(f"all generated files are up to date for {args.env}")
        return 0

    print(f"\nrendered {written} file(s) for {args.env}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

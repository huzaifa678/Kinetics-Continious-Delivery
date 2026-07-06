package kubernetes

import rego.v1

ecr_img := "533267178572.dkr.ecr.us-east-1.amazonaws.com/kinetics-training:serve-1b1fcae"

test_allow_tagged_ecr_rollout if {
	obj := {
		"kind": "Rollout",
		"metadata": {"name": "inference"},
		"spec": {"template": {"spec": {"containers": [{"name": "app", "image": ecr_img}]}}},
	}
	count(deny) == 0 with input as obj
	count(warn) == 0 with input as obj
}

test_allow_sha_latest_tag if {
	img := "533267178572.dkr.ecr.us-east-1.amazonaws.com/kinetics-training:sha-latest"
	count(deny) == 0 with input as {"kind": "Job", "metadata": {"name": "etl"}, "spec": {"template": {"spec": {"containers": [{"image": img}]}}}}
}

test_deny_latest_tag if {
	img := "533267178572.dkr.ecr.us-east-1.amazonaws.com/kinetics-training:latest"
	deny with input as {"kind": "Rollout", "metadata": {"name": "x"}, "spec": {"template": {"spec": {"containers": [{"image": img}]}}}}
}

test_deny_untagged if {
	deny with input as {"kind": "Deployment", "metadata": {"name": "x"}, "spec": {"template": {"spec": {"containers": [{"image": "nginx"}]}}}}
}

test_allow_digest if {
	img := "533267178572.dkr.ecr.us-east-1.amazonaws.com/kinetics-training@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	count(deny) == 0 with input as {"kind": "Rollout", "metadata": {"name": "x"}, "spec": {"template": {"spec": {"containers": [{"image": img}]}}}}
}

test_deny_registry_port_untagged if {
	deny with input as {"kind": "Pod", "metadata": {"name": "x"}, "spec": {"containers": [{"image": "myregistry:5000/repo"}]}}
}

test_allow_awscli_init if {
	obj := {"kind": "Rollout", "metadata": {"name": "x"}, "spec": {"template": {"spec": {"initContainers": [{"image": "amazon/aws-cli:2.17.0"}]}}}}
	count(deny) == 0 with input as obj
	count(warn) == 0 with input as obj
}

test_warn_unapproved_registry if {
	obj := {"kind": "Deployment", "metadata": {"name": "x"}, "spec": {"template": {"spec": {"containers": [{"image": "docker.io/library/redis:7"}]}}}}
	warn with input as obj
	count(deny) == 0 with input as obj
}

test_deny_privileged if {
	deny with input as {"kind": "Deployment", "metadata": {"name": "x"}, "spec": {"template": {"spec": {"containers": [{"image": ecr_img, "securityContext": {"privileged": true}}]}}}}
}

test_deny_hostpath if {
	deny with input as {"kind": "Deployment", "metadata": {"name": "x"}, "spec": {"template": {"spec": {"volumes": [{"name": "h", "hostPath": {"path": "/"}}], "containers": [{"image": ecr_img}]}}}}
}

test_deny_hostnetwork if {
	deny with input as {"kind": "Deployment", "metadata": {"name": "x"}, "spec": {"template": {"spec": {"hostNetwork": true, "containers": [{"image": ecr_img}]}}}}
}

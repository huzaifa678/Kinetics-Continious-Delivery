package kubernetes

import rego.v1

approved_image_prefixes := {
	"amazon/aws-cli", 
	"public.ecr.aws/",
	"otel/opentelemetry-collector",
}


image_refs contains img if {
	walk(input, [path, value])
	path[count(path) - 1] == "image"
	is_string(value)
	img := value
}

is_ecr(img) if regex.match(`^[0-9]+\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/`, img)

is_approved(img) if is_ecr(img)

is_approved(img) if {
	some prefix in approved_image_prefixes
	startswith(img, prefix)
}

digest_pinned(img) if contains(img, "@sha256:")

image_tag(img) := tag if {
	not digest_pinned(img)
	parts := split(img, "/")
	last := parts[count(parts) - 1]
	contains(last, ":")
	seg := split(last, ":")
	tag := seg[count(seg) - 1]
}

untagged(img) if {
	not digest_pinned(img)
	parts := split(img, "/")
	last := parts[count(parts) - 1]
	not contains(last, ":")
}

deny contains msg if {
	some img in image_refs
	image_tag(img) == "latest"
	msg := sprintf("image %q uses the mutable :latest tag — GitOps requires a pinned tag", [img])
}

deny contains msg if {
	some img in image_refs
	untagged(img)
	msg := sprintf("image %q has no tag or digest — pin an explicit tag", [img])
}

deny contains msg if {
	walk(input, [path, value])
	path[count(path) - 1] == "privileged"
	value == true
	msg := sprintf("%s/%s: a container requests privileged: true", [obj_kind, obj_name])
}

deny contains msg if {
	walk(input, [path, value])
	some key in {"hostNetwork", "hostPID", "hostIPC"}
	path[count(path) - 1] == key
	value == true
	msg := sprintf("%s/%s: %s: true breaks host isolation", [obj_kind, obj_name, key])
}

deny contains msg if {
	walk(input, [path, _])
	path[count(path) - 1] == "hostPath"
	msg := sprintf("%s/%s: mounts a hostPath volume", [obj_kind, obj_name])
}

warn contains msg if {
	some img in image_refs
	not is_approved(img)
	msg := sprintf("%s/%s: image %q is not from the org ECR or the approved allowlist", [obj_kind, obj_name, img])
}

obj_kind := k if {
	k := input.kind
} else := "resource"

obj_name := n if {
	n := input.metadata.name
} else := "?"

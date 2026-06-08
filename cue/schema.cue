// Strict schemas for every Kubernetes manifest this repo produces — the
// rendered Helm chart (PyTorchJob, PV/PVC) and the GitOps manifests (ArgoCD
// Applications, Karpenter NodePool / EC2NodeClass).
//
// `cue vet` against #Resource fails the build if a manifest has an unknown
// field, a wrong-typed value, or a missing required key. See
// scripts/validate-manifests.sh.
package manifests

// ---------------------------------------------------------------------------
// Shared building blocks
// ---------------------------------------------------------------------------
#Name: string & =~"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$"

#ObjectMeta: {
	name:         #Name
	namespace?:   #Name
	labels?:      {[string]: string}
	annotations?: {[string]: string}
	finalizers?: [...string]
}

// ---------------------------------------------------------------------------
// SageMaker HyperPod training operator job (rendered by helm/training-job).
// This is the HyperPod-native CRD (group sagemaker.amazonaws.com) — NOT the
// Kubeflow PyTorchJob — so we get fault-detection + auto-resume.
// ---------------------------------------------------------------------------
#HyperPodPyTorchJob: {
	apiVersion: "sagemaker.amazonaws.com/v1"
	kind:       "HyperPodPyTorchJob"
	metadata:   #ObjectMeta
	spec: {
		nprocPerNode?: string | int
		replicaSpecs: [...#HyperPodReplicaSpec] & [_, ...] // at least one
		runPolicy?: {
			cleanPodPolicy?:   "None" | "Running" | "All"
			jobMaxRetryCount?: int & >=0
			...
		}
	}
}

#HyperPodReplicaSpec: {
	name:     string
	replicas: int & >=1
	template: {
		metadata?: {labels?: {[string]: string}, ...}
		spec: {
			nodeSelector?: {[string]: string}
			tolerations?: [...{...}]
			containers: [...#Container] & [_, ...] // at least one
			volumes?: [...{name: string, ...}]
		}
	}
}

#Container: {
	name:             string
	image:            string & =~":"
	imagePullPolicy?: "Always" | "IfNotPresent" | "Never"
	command?: [...string]
	args?: [...string]
	env?: [...{name: string, value?: string, valueFrom?: {...}}]
	resources?: {
		limits?:   {[string]: string | int}
		requests?: {[string]: string | int}
	}
	volumeMounts?: [...{name: string, mountPath: string, ...}]
}

// ---------------------------------------------------------------------------
// Core volumes (rendered when data.fsx.create = true)
// ---------------------------------------------------------------------------
#PersistentVolume: {
	apiVersion: "v1"
	kind:       "PersistentVolume"
	metadata:   #ObjectMeta
	spec: {
		capacity: storage: string
		volumeMode?: "Filesystem" | "Block"
		accessModes: [...("ReadWriteOnce" | "ReadOnlyMany" | "ReadWriteMany" | "ReadWriteOncePod")] & [_, ...]
		persistentVolumeReclaimPolicy?: "Retain" | "Delete" | "Recycle"
		storageClassName?:              string
		csi?: {driver: string, volumeHandle: string, volumeAttributes?: {[string]: string}}
	}
}

#PersistentVolumeClaim: {
	apiVersion: "v1"
	kind:       "PersistentVolumeClaim"
	metadata:   #ObjectMeta
	spec: {
		accessModes: [...string] & [_, ...]
		storageClassName?: string
		volumeName?:       string
		resources: requests: storage: string
	}
}

// ---------------------------------------------------------------------------
// ArgoCD Application
// ---------------------------------------------------------------------------
#Application: {
	apiVersion: "argoproj.io/v1alpha1"
	kind:       "Application"
	metadata:   #ObjectMeta
	spec: {
		project:     string
		source:      #AppSource
		destination: {server: string, namespace?: #Name}
		syncPolicy?: {
			automated?: {prune?: bool, selfHeal?: bool}
			syncOptions?: [...string]
			retry?: {limit?: int, backoff?: {...}}
		}
		ignoreDifferences?: [...{group?: string, kind?: string, jsonPointers?: [...string], jqPathExpressions?: [...string], ...}]
	}
}

#AppSource: {
	repoURL:        string
	targetRevision: string
	// Either a Helm chart (chart set) or a path in the repo (path set).
	chart?: string
	path?:  string
	helm?: {
		valueFiles?: [...string]
		parameters?: [...{name: string, value: string}]
	}
}

// ---------------------------------------------------------------------------
// Karpenter
// ---------------------------------------------------------------------------
#NodePool: {
	apiVersion: "karpenter.sh/v1"
	kind:       "NodePool"
	metadata:   #ObjectMeta
	spec: {
		template: spec: {
			nodeClassRef: {group: string, kind: string, name: #Name}
			requirements: [...#Requirement] & [_, ...]
			expireAfter?: string
		}
		limits?: {[string]: string | int}
		disruption?: {
			consolidationPolicy?: "WhenEmpty" | "WhenEmptyOrUnderutilized"
			consolidateAfter?:    string
		}
	}
}

#Requirement: {
	key:      string
	operator: "In" | "NotIn" | "Exists" | "DoesNotExist" | "Gt" | "Lt"
	values?: [...string]
}

#EC2NodeClass: {
	apiVersion: "karpenter.k8s.aws/v1"
	kind:       "EC2NodeClass"
	metadata:   #ObjectMeta
	spec: {
		amiSelectorTerms: [...{alias?: string, id?: string, tags?: {[string]: string}}] & [_, ...]
		role: string
		subnetSelectorTerms: [...{tags?: {[string]: string}, id?: string}] & [_, ...]
		securityGroupSelectorTerms: [...{tags?: {[string]: string}, id?: string}] & [_, ...]
		tags?: {[string]: string}
	}
}

// ---------------------------------------------------------------------------
// The disjunction every document is vetted against. Adding a manifest of an
// unlisted kind will fail validation by design — keep this list authoritative.
// ---------------------------------------------------------------------------
#Resource: #HyperPodPyTorchJob |
	#PersistentVolume |
	#PersistentVolumeClaim |
	#Application |
	#NodePool |
	#EC2NodeClass

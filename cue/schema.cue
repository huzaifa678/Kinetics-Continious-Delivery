package manifests

#Name: string & =~"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$"

#ObjectMeta: {
	name:         #Name
	namespace?:   #Name
	labels?:      {[string]: string}
	annotations?: {[string]: string}
	finalizers?: [...string]
}


#HyperPodPyTorchJob: {
	apiVersion: "sagemaker.amazonaws.com/v1"
	kind:       "HyperPodPyTorchJob"
	metadata:   #ObjectMeta
	spec: {
		nprocPerNode?: string | int
		replicaSpecs: [...#HyperPodReplicaSpec] & [_, ...] 
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
	chart?: string
	path?:  string
	ref?:   string
	helm?: {
		ignoreMissingValueFiles?: bool
		valueFiles?: [...string]
		parameters?: [...{name: string, value: string}]
		releaseName?: string
	}
}


#ApplicationSet: {
	apiVersion: "argoproj.io/v1alpha1"
	kind:       "ApplicationSet"
	metadata:   #ObjectMeta
	spec: {
		goTemplate?: bool
		generators: [...{...}] & [_, ...]
		template: {...}
		...
	}
}


#NodePool: {
	apiVersion: "karpenter.sh/v1"
	kind:       "NodePool"
	metadata:   #ObjectMeta
	spec: {
		template: spec: {
			nodeClassRef: {group: string, kind: string, name: #Name}
			requirements: [...#Requirement] & [_, ...]
			expireAfter?: string
			taints?: [...#Taint]
		}
		limits?: {[string]: string | int}
		disruption?: {
			consolidationPolicy?: "WhenEmpty" | "WhenEmptyOrUnderutilized"
			consolidateAfter?:    string
		}
	}
}

#Taint: {
	key:    string
	value?: string
	effect: "NoSchedule" | "PreferNoSchedule" | "NoExecute"
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

// HyperPod managed-Karpenter NodeClass. Maps to pre-created HyperPod instance
// groups (count 0); Karpenter provisions GPU nodes from them on demand. The
// instanceGroups names MUST match the Terraform-created groups
// (terraform output hyperpod_gpu_instance_groups), max 10.
#HyperpodNodeClass: {
	apiVersion: "karpenter.sagemaker.amazonaws.com/v1"
	kind:       "HyperpodNodeClass"
	metadata:   #ObjectMeta
	spec: {
		instanceGroups: [...string] & [_, ...]
	}
}


// Seldon Core v2 custom model server. podSpec swaps in our custom MLServer image
// (Dockerfile.seldon) and extraCapabilities advertises what its Models require.
#SeldonServer: {
	apiVersion: "mlops.seldon.io/v1alpha1"
	kind:       "Server"
	metadata:   #ObjectMeta
	spec: {
		serverConfig: string
		replicas?:    int & >=0
		extraCapabilities?: [...string]
		podSpec?: {...}
	}
}

// Seldon Core v2 model version. storageUri (resolved from the MLflow registry)
// points at the artifact dir; requirements pick the server by capability.
#SeldonModel: {
	apiVersion: "mlops.seldon.io/v1alpha1"
	kind:       "Model"
	metadata:   #ObjectMeta
	spec: {
		storageUri: string
		requirements?: [...string]
		memory?: string
	}
}

// Seldon Core v2 A/B experiment: weighted split across candidate models.
#SeldonExperiment: {
	apiVersion: "mlops.seldon.io/v1alpha1"
	kind:       "Experiment"
	metadata:   #ObjectMeta
	spec: {
		default: string
		candidates: [...{name: string, weight: int & >=0}] & [_, ...]
		mirror?: {name: string, percent: int & >=0 & <=100}
	}
}

// ── Core v1 ─────────────────────────────────────────────────────────────────

// ServiceAccount: used by the etl-shards chart (IRSA/Pod-Identity binding).
#ServiceAccount: {
	apiVersion: "v1"
	kind:       "ServiceAccount"
	metadata:   #ObjectMeta
	automountServiceAccountToken?: bool
}




// WorkflowTemplate: a reusable, versioned workflow spec managed by ArgoCD.
// Runs are spawned via `argo submit --from workflowtemplate/<name>` — the
// template itself is never mutated by a run, so ArgoCD can reconcile it safely.
#WorkflowTemplate: {
	apiVersion: "argoproj.io/v1alpha1"
	kind:       "WorkflowTemplate"
	metadata:   #ObjectMeta
	spec:       #WorkflowSpec
}

// Workflow: a single execution instance (created by `argo submit`).
// Not managed by ArgoCD directly, but included so rendered manifests
// can be validated if needed.
#Workflow: {
	apiVersion: "argoproj.io/v1alpha1"
	kind:       "Workflow"
	metadata:   #ObjectMeta
	spec:       #WorkflowSpec
}

#WorkflowSpec: {
	entrypoint:          string
	serviceAccountName?: string
	parallelism?:        int & >=1
	podGC?: {
		strategy: "OnWorkflowCompletion" | "OnWorkflowSuccess" | "OnPodCompletion" | "OnPodSuccess"
	}
	retryStrategy?: #RetryStrategy
	templates: [...#WorkflowTemplate_Template] & [_, ...]
	// Free-form fields (volumes, nodeSelector, tolerations, etc.)
	...
}

#RetryStrategy: {
	limit:        string | int
	retryPolicy?: "Always" | "OnFailure" | "OnError" | "OnTransientError"
	backoff?: {
		duration?:    string
		factor?:      string | int
		maxDuration?: string
	}
}

#WorkflowTemplate_Template: {
	name: string
	// A template is one of: steps, dag, container, script, resource, suspend.
	// Only the shapes used by etl-shards are constrained; others are open ({...}).
	steps?: [...[...#WorkflowStep]]
	dag?: {tasks: [...#DAGTask] & [_, ...]}
	container?: #WorkflowContainer
	inputs?: {
		parameters?: [...{name: string, value?: string}]
		artifacts?: [...{...}]
	}
	outputs?: {
		parameters?: [...{...}]
		artifacts?: [...{...}]
	}
	podSpecPatch?: string
	securityContext?: {...}
	nodeSelector?: {[string]: string}
	tolerations?: [...{...}]
	volumes?: [...{name: string, ...}]
	retryStrategy?: #RetryStrategy
	metadata?: {labels?: {[string]: string}, annotations?: {[string]: string}}
	...
}

#WorkflowStep: {
	name:      string
	template:  string
	arguments?: {
		parameters?: [...{name: string, value: string}]
		artifacts?: [...{...}]
	}
	withSequence?: {
		count?:  string | int
		start?:  string | int
		end?:    string | int
		format?: string
	}
	withItems?: [..._]
	when?: string
	...
}

#DAGTask: {
	name:         string
	template:     string
	dependencies?: [...string]
	arguments?: {
		parameters?: [...{name: string, value: string}]
	}
	...
}

#WorkflowContainer: {
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
	securityContext?: {...}
	...
}


#Resource: #HyperPodPyTorchJob |
	#PersistentVolume |
	#PersistentVolumeClaim |
	#ServiceAccount |
	#Application |
	#ApplicationSet |
	#NodePool |
	#EC2NodeClass |
	#HyperpodNodeClass |
	#SeldonServer |
	#SeldonModel |
	#SeldonExperiment |
	#WorkflowTemplate |
	#Workflow

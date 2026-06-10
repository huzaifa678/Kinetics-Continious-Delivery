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
	helm?: {
		valueFiles?: [...string]
		parameters?: [...{name: string, value: string}]
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


#Resource: #HyperPodPyTorchJob |
	#PersistentVolume |
	#PersistentVolumeClaim |
	#Application |
	#ApplicationSet |
	#NodePool |
	#EC2NodeClass |
	#HyperpodNodeClass

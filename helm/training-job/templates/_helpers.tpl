{{- define "kinetics-training.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kinetics-training.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "kinetics-training.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
=============================================================================
GPU allocation mode — single source of truth (Option A vs Option B).
=============================================================================
Every GPU-dependent decision in this chart derives from "kinetics-training.gpuMode"
below, so the A-xor-B rule and its validation live in exactly ONE place instead
of a scattered `{{ if eq .Values.gpu.mode "dra" }}` in each template. The device
plugin (A) and the DRA driver (B) are mutually exclusive on a node; this helper
is what makes "exactly one, never both, never a typo" a hard, reused invariant.
*/}}
{{- define "kinetics-training.gpuMode" -}}
{{- $mode := .Values.gpu.mode | default "devicePlugin" -}}
{{- if not (has $mode (list "devicePlugin" "dra")) -}}
{{- fail (printf "gpu.mode must be 'devicePlugin' (Option A) or 'dra' (Option B), got %q" $mode) -}}
{{- end -}}
{{- $mode -}}
{{- end -}}

{{/*
Container resources for the chosen mode. Option A: an nvidia.com/gpu limit
derived from the one knob (distributed.gpusPerNode). Option B: a DRA claim (the
GPUs come from the pod's resourceClaims) and NO nvidia.com/gpu limit. Never both.
*/}}
{{- define "kinetics-training.gpuResources" -}}
{{- if eq (include "kinetics-training.gpuMode" .) "dra" }}
claims:
  - name: gpus
requests:
  {{- toYaml .Values.resources.requests | nindent 2 }}
{{- else }}
limits:
  nvidia.com/gpu: {{ .Values.distributed.gpusPerNode }}
requests:
  {{- toYaml .Values.resources.requests | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Pod-level resourceClaims — only Option B declares them (empty under Option A).
*/}}
{{- define "kinetics-training.gpuResourceClaims" -}}
{{- if eq (include "kinetics-training.gpuMode" .) "dra" }}
resourceClaims:
  - name: gpus
    resourceClaimTemplateName: {{ include "kinetics-training.fullname" . }}-gpu
{{- end }}
{{- end -}}

{{/*
GPU node targeting for the chosen mode. Classic (A) and DRA (B) each carry their
own selector under gpu.nodeSelector.<mode> so they CAN diverge (e.g. a future
DRA-only node label or instance family); identical today since both land on the
same HyperPod g5 GPU nodes. Keyed off the validated mode — no raw conditional.
*/}}
{{- define "kinetics-training.gpuNodeSelector" -}}
{{- $mode := include "kinetics-training.gpuMode" . -}}
{{- $sel := index .Values.gpu.nodeSelector $mode -}}
{{- if not $sel -}}
{{- fail (printf "gpu.nodeSelector.%s is required but unset" $mode) -}}
{{- end -}}
{{- toYaml $sel -}}
{{- end -}}

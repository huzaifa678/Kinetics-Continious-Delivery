{{- define "thanos.name" -}}
{{- .Values.fullnameOverride | default "thanos" -}}
{{- end -}}

{{- define "thanos.labels" -}}
app.kubernetes.io/name: {{ include "thanos.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Component fullname, e.g. thanos-receive */}}
{{- define "thanos.component" -}}
{{ include "thanos.name" $.root }}-{{ $.name }}
{{- end -}}

{{- define "thanos.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end -}}

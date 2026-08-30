{{/* Short name (the chart name) */}}
{{- define "webapp.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/* Fully qualified name: <release>-<chart> */}}
{{- define "webapp.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name -}}
{{- end -}}

{{/* Common labels applied to every object */}}
{{- define "webapp.labels" -}}
app: {{ include "webapp.name" . }}
release: {{ .Release.Name }}
env: {{ .Values.env }}
{{- end -}}

{{/* Selector labels (stable subset used by Deployment/Service selectors) */}}
{{- define "webapp.selectorLabels" -}}
app: {{ include "webapp.name" . }}
release: {{ .Release.Name }}
{{- end -}}

{{/*
Expand the name of the chart.
*/}}
{{- define "my-laravel-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "my-laravel-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version label.
*/}}
{{- define "my-laravel-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels (recommandations Kubernetes)
*/}}
{{- define "my-laravel-app.labels" -}}
helm.sh/chart: {{ include "my-laravel-app.chart" . }}
{{ include "my-laravel-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kubequest
{{- end }}

{{/*
Selector labels
*/}}
{{- define "my-laravel-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "my-laravel-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

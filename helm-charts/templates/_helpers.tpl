{{/*
Expand the name of the chart.
*/}}
{{- define "helm-charts.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "helm-charts.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if eq .Release.Name $name }}
{{- $name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "helm-charts.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "helm-charts.labels" -}}
helm.sh/chart: {{ include "helm-charts.chart" . }}
{{ include "helm-charts.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "helm-charts.selectorLabels" -}}
app.kubernetes.io/name: {{ include "helm-charts.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "helm-charts.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "helm-charts.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create docker registry auth secret
*/}}
{{- define "imagePullSecret" }}
{{- with .Values.harbor }}
{{- $auth := printf "%s:%s" .username .password | b64enc }}
{{- $config := dict "auths" (dict .server (dict "username" .username "password" .password "auth" $auth)) }}
{{- $json := $config | toPrettyJson }}
{{- $json | b64enc }}
{{- end }}
{{- end }}

{{/*
Expand the name of the chart.
*/}}
{{- define "jupyterhub-metrics.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "jupyterhub-metrics.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "jupyterhub-metrics.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "jupyterhub-metrics.labels" -}}
helm.sh/chart: {{ include "jupyterhub-metrics.chart" . }}
{{ include "jupyterhub-metrics.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "jupyterhub-metrics.selectorLabels" -}}
app.kubernetes.io/name: {{ include "jupyterhub-metrics.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "jupyterhub-metrics.serviceAccountName" -}}
{{- if .Values.rbac.create }}
{{- default (include "jupyterhub-metrics.fullname" .) .Values.rbac.serviceAccountName }}
{{- else }}
{{- default "default" .Values.rbac.serviceAccountName }}
{{- end }}
{{- end }}

{{/*
Return the appropriate apiVersion for RBAC APIs
*/}}
{{- define "jupyterhub-metrics.rbac.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "rbac.authorization.k8s.io/v1" }}
{{- print "rbac.authorization.k8s.io/v1" }}
{{- else }}
{{- print "rbac.authorization.k8s.io/v1beta1" }}
{{- end }}
{{- end }}

{{/*
Get Grafana password secret name
*/}}
{{- define "jupyterhub-metrics.grafana.passwordSecret" -}}
{{- if .Values.secrets.externalSecretEnabled }}
{{- .Values.secrets.externalSecretName }}
{{- else }}
{{- include "jupyterhub-metrics.fullname" . }}-secrets
{{- end }}
{{- end }}

{{/*
Get Grafana password key name
*/}}
{{- define "jupyterhub-metrics.grafana.passwordKey" -}}
{{- if .Values.secrets.externalSecretEnabled }}
{{- .Values.secrets.externalSecretGrafanaPasswordKey }}
{{- else }}
{{- print "GF_SECURITY_ADMIN_PASSWORD" }}
{{- end }}
{{- end }}

{{/*
Return namespace
*/}}
{{- define "jupyterhub-metrics.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
TimescaleDB host
*/}}
{{- define "jupyterhub-metrics.timescaledb.host" -}}
{{- if .Values.timescaledb.external.enabled }}
{{- .Values.timescaledb.external.host }}
{{- else }}
{{- printf "%s-timescaledb" (include "jupyterhub-metrics.fullname" .) }}
{{- end }}
{{- end }}

{{/*
TimescaleDB password secret name
*/}}
{{- define "jupyterhub-metrics.timescaledb.passwordSecret" -}}
{{- if .Values.secrets.externalSecretEnabled }}
{{- .Values.secrets.externalSecretName }}
{{- else }}
{{- include "jupyterhub-metrics.fullname" . }}-secrets
{{- end }}
{{- end }}

{{/*
TimescaleDB password key name
*/}}
{{- define "jupyterhub-metrics.timescaledb.passwordKey" -}}
{{- if .Values.secrets.externalSecretEnabled }}
{{- .Values.secrets.externalSecretDbPasswordKey }}
{{- else }}
{{- print "POSTGRES_PASSWORD" }}
{{- end }}
{{- end }}

{{/*
TimescaleDB port
*/}}
{{- define "jupyterhub-metrics.timescaledb.port" -}}
{{- .Values.timescaledb.database.port }}
{{- end }}

{{- define "amex-tracker.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-amex-tracker" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "amex-tracker.labels" -}}
app.kubernetes.io/name: amex-tracker
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "amex-tracker.selectorLabels" -}}
app.kubernetes.io/name: amex-tracker
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "amex-tracker.secretName" -}}
{{- if .Values.existingSecret -}}
{{ .Values.existingSecret }}
{{- else -}}
{{ include "amex-tracker.fullname" . }}-secrets
{{- end -}}
{{- end -}}

{{- define "amex-tracker.pgSecret" -}}
{{ include "amex-tracker.fullname" . }}-pg-app
{{- end -}}

{{/*
DB environment. When CloudNativePG is enabled, wire the individual connection
parts from its generated -app secret; the backend assembles AMEX_DATABASE_URL.
When disabled, AMEX_DATABASE_URL is supplied via the app Secret instead.
*/}}
{{- define "amex-tracker.dbEnv" -}}
{{- if .Values.postgres.enabled }}
# Host/port/db are deterministic (CloudNativePG -rw service); only the
# credentials come from the operator-generated -app secret.
- name: AMEX_DB_HOST
  value: {{ include "amex-tracker.fullname" . }}-pg-rw
- name: AMEX_DB_PORT
  value: "5432"
- name: AMEX_DB_NAME
  value: {{ .Values.postgres.database | quote }}
- name: AMEX_DB_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "amex-tracker.pgSecret" . }}
      key: username
- name: AMEX_DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "amex-tracker.pgSecret" . }}
      key: password
{{- end }}
{{- end -}}

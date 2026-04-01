{{- define "panoramax.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "panoramax.dbUrl" -}}
postgres://{{ .Values.db.user }}:{{ .Values.db.password }}@db/{{ .Values.db.name }}
{{- end -}}

{{- define "panoramax.apiImage" -}}
panoramax/api:{{ .Values.imageTag }}
{{- end -}}

{{/* Init container that blocks until the PostgreSQL TCP port is reachable */}}
{{- define "panoramax.waitForDb" -}}
- name: wait-for-db
  image: busybox:1.36
  command:
    - sh
    - -c
    - until nc -z db 5432; do echo "waiting for db..."; sleep 2; done
{{- end -}}

{{/* Init container that blocks until Keycloak's realm endpoint responds */}}
{{- define "panoramax.waitForAuth" -}}
- name: wait-for-auth
  image: busybox:1.36
  command:
    - sh
    - -c
    - until wget -qO /dev/null http://auth:8080/realms/geovisio 2>/dev/null; do echo "waiting for auth..."; sleep 5; done
{{- end -}}

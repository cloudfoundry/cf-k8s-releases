{{/*
Repeated per-container cert volumeMounts. Each metrics server and each log-cache
client connection mounts the same secret into every container that uses it.
*/}}
{{- define "logcache.metricsCertMount" -}}
- name: metrics
  mountPath: /etc/ssl/certs/metrics
  readOnly: true
{{- end -}}

{{- define "logcache.logcacheCertMount" -}}
- name: logcache
  mountPath: /etc/ssl/certs/logcache
  readOnly: true
{{- end -}}

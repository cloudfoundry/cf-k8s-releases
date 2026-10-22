{{/* SQL DSN, reproducing diego-release's connection_string_from_db_params ERB. */}}
{{- define "diego.sqlConnectionString" -}}
{{- $db := .db -}}
{{- $host := tpl $db.address .root -}}
{{- if eq $db.driver "postgres" -}}
postgres://{{ $db.user }}:{{ $db.password }}@{{ $host }}:{{ $db.port }}/{{ $db.name }}
{{- else if eq $db.driver "mysql" -}}
{{ $db.user }}:{{ $db.password }}@tcp({{ $host }}:{{ $db.port }})/{{ $db.name }}
{{- else -}}
{{- fail (printf "unknown db.driver %q (expected postgres or mysql)" $db.driver) -}}
{{- end -}}
{{- end -}}

{{/* Loggregator v2 block; emit as the LAST config key (no trailing comma). */}}
{{- define "diego.loggregatorConfig" -}}
"loggregator": {
  "loggregator_use_v2_api": true,
  "loggregator_api_port": {{ int .cfg.v2ApiPort }},
  "loggregator_api_host": "{{ tpl .cfg.apiHost .root }}",
  "loggregator_ca_path": "/etc/ssl/certs/loggregator/ca.crt",
  "loggregator_cert_path": "/etc/ssl/certs/loggregator/tls.crt",
  "loggregator_key_path": "/etc/ssl/certs/loggregator/tls.key",
  "loggregator_job_deployment": "cf",
  "loggregator_job_name": "{{ .jobName }}",
  "loggregator_job_origin": "{{ .origin }}",
  {{- if hasKey .cfg "appMetricExclusionFilter" }}
  "loggregator_app_metric_exclusion_filter": {{ .cfg.appMetricExclusionFilter | toJson }},
  {{- end }}
  "loggregator_source_id": "{{ .sourceId }}"
}
{{- end -}}

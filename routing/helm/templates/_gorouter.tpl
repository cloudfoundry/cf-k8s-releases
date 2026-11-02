{{- define "routing.gorouter.certMounts" -}}
{{- range $name, $secret := . }}
- name: gorouter-{{ $name }}
  mountPath: /etc/ssl/certs/gorouter/{{ $name }}
  readOnly: true
{{- end -}}
{{- end -}}

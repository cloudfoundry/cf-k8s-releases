{{- define "routing.tcpRouterBackendCertMounts" -}}
{{- if .Values.tcpRouter.backendTLS.enabled }}
- name: tcp-backend-ca
  mountPath: /etc/ssl/certs/tcp-backend-ca
  readOnly: true
{{- end }}
{{- range $index, $certificate := .Values.tcpRouter.certificateSecrets.frontendTLS }}
- name: tcp-frontend-{{ $index }}
  mountPath: /etc/ssl/certs/tcp-frontend/{{ $certificate.name }}
  readOnly: true
{{- end }}
{{- end -}}

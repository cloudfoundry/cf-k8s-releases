{{- define "routing.udpForwarder" -}}
{{- $forwarder := .root.Values.udpForwarder -}}
- name: udp-forwarder
  image: {{ $forwarder.image.repository }}:{{ $forwarder.image.tag }}
  imagePullPolicy: {{ $forwarder.image.imagePullPolicy }}
  {{- if $forwarder.resources }}
  resources:
    {{- toYaml $forwarder.resources | nindent 4 }}
  {{- end }}
  env:
    - name: UDP_PORT
      value: {{ .port | quote }}
    - name: LOGGREGATOR_AGENT_CA_FILE_PATH
      value: /etc/ssl/certs/udp-forwarder/ca.crt
    - name: LOGGREGATOR_AGENT_CERT_FILE_PATH
      value: /etc/ssl/certs/udp-forwarder/tls.crt
    - name: LOGGREGATOR_AGENT_KEY_FILE_PATH
      value: /etc/ssl/certs/udp-forwarder/tls.key
    - name: LOGGREGATOR_AGENT_ADDR
      value: "{{ tpl $forwarder.metronEndpoint.host .root }}:{{ $forwarder.metronEndpoint.port }}"
    - name: METRICS_CA_FILE_PATH
      value: /etc/ssl/certs/udp-forwarder/ca.crt
    - name: METRICS_CERT_FILE_PATH
      value: /etc/ssl/certs/udp-forwarder/tls.crt
    - name: METRICS_KEY_FILE_PATH
      value: /etc/ssl/certs/udp-forwarder/tls.key
  volumeMounts:
    - name: udp-forwarder
      mountPath: /etc/ssl/certs/udp-forwarder
{{- end -}}

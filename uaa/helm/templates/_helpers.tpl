{{- define "uaa.dbUrl" -}}
{{- $db := .Values.uaadb -}}
{{- $scheme := $db.dbScheme -}}
{{- if eq $scheme "postgres" }}{{- $scheme = "postgresql" -}}{{- end -}}
{{- if not (or (eq $scheme "postgresql") (eq $scheme "mysql")) }}{{- fail "uaadb.scheme must be postgresql or mysql" -}}{{- end -}}
{{- $url := printf "jdbc:%s://%s:%v/%s" $scheme (tpl $db.address .) $db.port $db.name -}}
{{- $tls := $db.tls -}}
{{- if eq $scheme "postgresql" -}}
  {{- if eq $tls "enabled" }}{{- $url = printf "%s?sslmode=verify-full&sslrootcert=/etc/ssl/certs/postgres/ca.crt" $url -}}
  {{- else if eq $tls "enabled_skip_hostname_validation" }}{{- $url = printf "%s?sslmode=verify-ca&sslrootcert=/etc/ssl/certs/postgres/ca.crt" $url -}}
  {{- else if eq $tls "enabled_skip_all_validation" }}{{- $url = printf "%s?sslmode=require" $url -}}
  {{- else if eq $tls "disabled" }}{{- $url = printf "%s?sslmode=disable" $url -}}
  {{- else }}{{- fail "uaadb.tls must be enabled, enabled_skip_hostname_validation, enabled_skip_all_validation or disabled" -}}{{- end -}}
{{- else -}}
  {{- if eq $tls "enabled" }}{{- $url = printf "%s?useSSL=true" $url -}}
  {{- else if eq $tls "enabled_skip_hostname_validation" }}{{- $url = printf "%s?useSSL=true&disableSslHostnameVerification=true" $url -}}
  {{- else if eq $tls "enabled_skip_all_validation" }}{{- $url = printf "%s?useSSL=true&trustServerCertificate=true" $url -}}
  {{- else if eq $tls "disabled" }}{{- $url = printf "%s?useSSL=false" $url -}}
  {{- else }}{{- fail "uaadb.tls must be enabled, enabled_skip_hostname_validation, enabled_skip_all_validation or disabled" -}}{{- end -}}
  {{- if and (ne $tls "disabled") $db.tlsProtocols }}{{- $url = printf "%s&enabledSslProtocolSuites=%s" $url $db.tlsProtocols -}}{{- end -}}
{{- end -}}
{{- with $db.additionalParameters }}{{- range $k, $v := . }}{{- if $v }}{{- $url = printf "%s&%s=%s" $url $k $v -}}{{- end }}{{- end }}{{- end -}}
{{- $url -}}
{{- end -}}

{{- define "uaa.springProfiles" -}}
{{- $scheme := .Values.uaadb.dbScheme -}}
{{- if eq $scheme "postgres" }}{{- $scheme = "postgresql" -}}{{- end -}}
{{- $scheme -}}{{- if .Values.uaa.ldap.enabled }},ldap{{- end -}}
{{- end -}}

{{- define "uaa.needsPostgresCa" -}}
{{- $s := .Values.uaadb.dbScheme -}}
{{- if or (eq $s "postgresql") (eq $s "postgres") -}}
{{- if or (eq .Values.uaadb.tls "enabled") (eq .Values.uaadb.tls "enabled_skip_hostname_validation") -}}true{{- end -}}
{{- end -}}
{{- end -}}

{{- define "uaa.compact" -}}
{{- $out := dict -}}
{{- range $k, $v := . -}}
  {{- if kindIs "map" $v -}}
    {{- $sub := include "uaa.compact" $v | fromYaml -}}
    {{- if $sub }}{{- $_ := set $out $k $sub -}}{{- end -}}
  {{- else if not (kindIs "invalid" $v) -}}
    {{- $_ := set $out $k $v -}}
  {{- end -}}
{{- end -}}
{{- toYaml $out -}}
{{- end -}}

{{- define "uaa.corsSection" -}}
{{- $out := dict -}}
{{- $allowed := dict -}}
{{- range $k, $v := .allowed }}{{- if not (kindIs "invalid" $v) }}{{- $_ := set $allowed $k $v -}}{{- end }}{{- end -}}
{{- if $allowed }}{{- $_ := set $out "allowed" $allowed -}}{{- end -}}
{{- if not (kindIs "invalid" .maxAge) }}{{- $_ := set $out "max_age" .maxAge -}}{{- end -}}
{{- if $out }}{{- toYaml $out -}}{{- end -}}
{{- end -}}

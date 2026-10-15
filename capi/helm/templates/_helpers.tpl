{{/*
capi.storageCliConfig — build a storage-cli blobstore config JSON from the BOSH-shaped
connection_config, mirroring capi-release's storage_cli_config_*.json.erb translation.
*/}}
{{- define "capi.storageCliConfig" -}}
{{- $provider := .provider -}}
{{- $conn := .cfg | default dict }}
{{- $out := dict "provider" $provider -}}
{{- $optional := dict -}}
{{- if eq $provider "azurebs" -}}
  {{- $_ := set $out "account_name" (required "capi.storageCliConfig azurebs: connectionConfig.azureStorageAccountName is required" (index $conn "azureStorageAccountName")) -}}
  {{- $_ := set $out "container_name" (required "capi.storageCliConfig azurebs: connection_config.container_name is required" (index $conn "container_name")) -}}
  {{- $_ := set $out "account_key" (required "capi.storageCliConfig azurebs: connectionConfig.azureStorageAccessKey is required" (index $conn "azureStorageAccessKey")) -}}
  {{- $_ := set $out "environment" (default "AzureCloud" (index $conn "environment")) -}}
  {{- $optional = dict "put_timeout_in_seconds" "put_timeout_in_seconds" "http_request_timeout" "http_request_timeout" "http_response_header_timeout" "http_response_header_timeout" -}}
{{- else if eq $provider "gcs" -}}
  {{- $_ := set $out "credentials_source" "static" -}}
  {{- $_ := set $out "json_key" (required "capi.storageCliConfig gcs: connectionConfig.googleJsonKeyString is required" (index $conn "googleJsonKeyString")) -}}
  {{- $_ := set $out "bucket_name" (required "capi.storageCliConfig gcs: connection_config.bucket_name is required" (index $conn "bucket_name")) -}}
  {{- $optional = dict "storage_class" "storage_class" "encryption_key" "encryption_key" "http_request_timeout" "http_request_timeout" "http_response_header_timeout" "http_response_header_timeout" -}}
{{- else if eq $provider "s3" -}}
  {{- $_ := set $out "bucket_name" (required "capi.storageCliConfig s3: connection_config.bucket_name is required" (index $conn "bucket_name")) -}}
  {{- if index $conn "useIamProfile" -}}
    {{- $_ := set $out "credentials_source" "env_or_profile" -}}
  {{- else -}}
    {{- $_ := set $out "credentials_source" "static" -}}
    {{- $_ := set $out "access_key_id" (required "capi.storageCliConfig s3: connectionConfig.awsAccessKeyId is required (or set use_iam_profile)" (index $conn "awsAccessKeyId")) -}}
    {{- $_ := set $out "secret_access_key" (required "capi.storageCliConfig s3: connectionConfig.awsSecretAccessKey is required (or set use_iam_profile)" (index $conn "awsSecretAccessKey")) -}}
  {{- end -}}
  {{- /* two keys are renamed (encryption->server_side_encryption, kms id->sse_kms_key_id); the rest keep their name */ -}}
  {{- $optional = dict
      "folder_name" "folder_name" "host" "host" "port" "port" "region" "region"
      "ssl_verify_peer" "ssl_verify_peer" "use_ssl" "use_ssl" "signature_version" "signature_version"
      "server_side_encryption" "encryption" "sse_kms_key_id" "x-amz-server-side-encryption-aws-kms-key-id"
      "assume_role_arn" "assume_role_arn" "multipart_upload" "multipart_upload" "host_style" "host_style"
      "swift_auth_account" "swift_auth_account" "swift_temp_url_key" "swift_temp_url_key"
      "download_concurrency" "download_concurrency" "download_part_size" "download_part_size"
      "upload_concurrency" "upload_concurrency" "upload_part_size" "upload_part_size"
      "multipart_copy_threshold" "multipart_copy_threshold" "multipart_copy_part_size" "multipart_copy_part_size"
      "single_upload_threshold" "single_upload_threshold"
      "request_checksum_calculation_enabled" "request_checksum_calculation_enabled"
      "response_checksum_calculation_enabled" "response_checksum_calculation_enabled"
      "uploader_request_checksum_calculation_enabled" "uploader_request_checksum_calculation_enabled"
      "http_request_timeout" "http_request_timeout" "http_response_header_timeout" "http_response_header_timeout" -}}
{{- else if eq $provider "alioss" -}}
  {{- $_ := set $out "access_key_id" (required "capi.storageCliConfig alioss: connectionConfig.aliyunAccesskeyId is required" (index $conn "aliyunAccesskeyId")) -}}
  {{- $_ := set $out "access_key_secret" (required "capi.storageCliConfig alioss: connectionConfig.aliyunAccesskeySecret is required" (index $conn "aliyunAccesskeySecret")) -}}
  {{- $_ := set $out "endpoint" (required "capi.storageCliConfig alioss: connectionConfig.aliyunOssEndpoint is required" (index $conn "aliyunOssEndpoint")) -}}
  {{- $_ := set $out "bucket_name" (required "capi.storageCliConfig alioss: connectionConfig.aliyunOssBucket is required" (index $conn "aliyunOssBucket")) -}}
  {{- $optional = dict "http_request_timeout" "http_request_timeout" "http_response_header_timeout" "http_response_header_timeout" -}}
{{- else if eq $provider "dav" -}}
  {{- $_ := set $out "user" (required "capi.storageCliConfig dav: connection_config.username is required" (index $conn "username")) -}}
  {{- $_ := set $out "password" (required "capi.storageCliConfig dav: connection_config.password is required" (index $conn "password")) -}}
  {{- $_ := set $out "endpoint" (printf "%s/admin/%s" (required "capi.storageCliConfig dav: connectionConfig.privateEndpoint is required" (index $conn "privateEndpoint")) .resourceDir) -}}
  {{- $optional = dict "public_endpoint" "public_endpoint" "secret" "secret" "retry_attempts" "retry_attempts" -}}
  {{- $caCert := index $conn "caCert" -}}
  {{- if $caCert -}}{{- $_ := set $out "tls" (dict "cert" (dict "ca" $caCert)) -}}{{- end -}}
{{- else -}}
  {{- fail (printf "capi.storageCliConfig: unsupported blobstore_provider %q (expected azurebs|gcs|s3|alioss|dav)" $provider) -}}
{{- end -}}
{{- range $cliKey, $boshKey := $optional -}}
  {{- $value := index $conn $boshKey -}}
  {{- if not (or (kindIs "invalid" $value) (and (kindIs "string" $value) (eq $value ""))) -}}
    {{- $_ := set $out $cliKey $value -}}
  {{- end -}}
{{- end -}}
{{- if and (eq $provider "azurebs") (not (hasKey $out "put_timeout_in_seconds")) -}}
  {{- $_ := set $out "put_timeout_in_seconds" "41" -}}
{{- end -}}
{{- if hasKey $out "host" -}}{{- $_ := set $out "host" (tpl (index $out "host") .root) -}}{{- end -}}
{{- $out | toJson -}}
{{- end -}}


{{- define "capi.ccCertVolumeMounts" -}}
- name: mutual-tls
  mountPath: /etc/ssl/certs/mutual-tls
  readOnly: true
- name: loggregator
  mountPath: /etc/ssl/certs/loggregator
  readOnly: true
- name: logcache
  mountPath: /etc/ssl/certs/logcache
  readOnly: true
- name: uaa
  mountPath: /etc/ssl/certs/uaa
  readOnly: true
- name: credhub
  mountPath: /etc/ssl/certs/credhub
  readOnly: true
{{- if .Values.ccdb.caCertificateSecret }}
- name: db-ca
  mountPath: /etc/ssl/certs/db-ca
  readOnly: true
{{- end }}
{{- end -}}

{{- define "capi.ccCertVolumes" -}}
- name: mutual-tls
  secret:
    secretName: {{ required "cloudController.certificateSecrets.mutualTLS is required" .Values.cloudController.certificateSecrets.mutualTLS }}
- name: loggregator
  secret:
    secretName: {{ required "cloudController.certificateSecrets.loggregatorTLS is required" .Values.cloudController.certificateSecrets.loggregatorTLS }}
- name: logcache
  secret:
    secretName: {{ required "cloudController.certificateSecrets.logcacheTLS is required" .Values.cloudController.certificateSecrets.logcacheTLS }}
- name: uaa
  secret:
    secretName: {{ required "cloudController.certificateSecrets.uaaCA is required" .Values.cloudController.certificateSecrets.uaaCA }}
- name: credhub
  secret:
    secretName: {{ required "cloudController.certificateSecrets.credhubCA is required" .Values.cloudController.certificateSecrets.credhubCA }}
{{- if .Values.ccdb.caCertificateSecret }}
- name: db-ca
  secret:
    secretName: {{ .Values.ccdb.caCertificateSecret }}
{{- end }}
{{- end -}}


{{- define "capi.validateAppDomains" -}}
{{- range $domain := . -}}
{{- if and (kindIs "map" $domain) (index $domain "internal") (hasKey $domain "router_group_name") -}}
{{- fail "cloudController.config.app_domains: router groups cannot be specified for internal domains" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "capi.clientSecret" -}}
{{- $client := index .root.Values.cloudController.config.uaa.clients .name | default dict -}}
{{- $client.secret | default .root.Values.oauthClientsSecret | required (printf "cloudController.config.uaa.clients.%s.secret or oauthClientsSecret must be provided" .name) | quote -}}
{{- end -}}

{{- define "capi.databaseEncryption" -}}
{{- $enc := .databaseEncryption -}}
{{- $legacyKey := .dbEncryptionKey -}}
{{- $rawKeys := $enc.keys | default dict -}}
{{- $keys := dict -}}
{{- $currentLabel := $enc.currentKeyLabel | default "" -}}
{{- if kindIs "slice" $rawKeys -}}
  {{- $activeLabels := list -}}
  {{- range $key := $rawKeys -}}
    {{- $_ := set $keys $key.label $key.encryption_key -}}
    {{- if $key.active }}{{- $activeLabels = append $activeLabels $key.label -}}{{- end -}}
  {{- end -}}
  {{- if ne (len $activeLabels) 1 }}{{- fail "cloudController.config.database_encryption.keys: exactly one key must be marked active" -}}{{- end -}}
  {{- $currentLabel = first $activeLabels -}}
{{- else -}}
  {{- $keys = $rawKeys -}}
{{- end -}}
{{- if and (not $legacyKey) (empty $keys) }}{{- fail "cloudController.config: set db_encryption_key or database_encryption.keys" -}}{{- end -}}
{{- if not $enc.skipValidation -}}
  {{- if or $currentLabel (not (empty $keys)) -}}
    {{- if not (hasKey $keys $currentLabel) }}{{- fail "cloudController.config.database_encryption.current_key_label is not present in database_encryption.keys" -}}{{- end -}}
  {{- end -}}
{{- end -}}
db_encryption_key: {{ if $legacyKey }}{{ $legacyKey | quote }}{{ else }}~{{ end }}
{{- if $keys }}
database_encryption:
  keys:
{{- toYaml $keys | nindent 4 }}
  current_key_label: {{ $currentLabel | quote }}
  pbkdf2_hmac_iterations: {{ $enc.experimentalPbkdf2HmacIterations }}
{{- end -}}
{{- end -}}

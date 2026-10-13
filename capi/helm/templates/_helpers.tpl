{{/*
capi.storageCliConfig — build a storage-cli blobstore config JSON from the BOSH-shaped
connection_config, mirroring capi-release's storage_cli_config_*.json.erb translation.

Input: dict with
  provider    - cc.<blob>.blobstore_provider (azurebs|gcs|s3|alioss|dav)
  cfg         - cc.<blob>.connection_config (BOSH property names)
  resourceDir - the blob's directory key (used to compose the dav endpoint)
  root        - chart root context ($), used to tpl the host value

Mandatory keys use `required` so a misconfigured blobstore fails at render, like BOSH's
bare p(). Optional keys are copied only when present and non-empty (false/0 are kept).
*/}}
{{- define "capi.storageCliConfig" -}}
{{- $provider := .provider -}}
{{- $conn := .cfg | default dict }}{{- /* default dict: treat an absent connection_config as empty */ -}}
{{- $out := dict "provider" $provider -}}
{{- /* $optional maps a storage-cli output key -> the connection_config key to copy from */ -}}
{{- $optional := dict -}}
{{- if eq $provider "azurebs" -}}
  {{- $_ := set $out "account_name" (required "capi.storageCliConfig azurebs: connection_config.azure_storage_account_name is required" (index $conn "azure_storage_account_name")) -}}
  {{- $_ := set $out "container_name" (required "capi.storageCliConfig azurebs: connection_config.container_name is required" (index $conn "container_name")) -}}
  {{- $_ := set $out "account_key" (required "capi.storageCliConfig azurebs: connection_config.azure_storage_access_key is required" (index $conn "azure_storage_access_key")) -}}
  {{- $_ := set $out "environment" (default "AzureCloud" (index $conn "environment")) -}}
  {{- $optional = dict "put_timeout_in_seconds" "put_timeout_in_seconds" "http_request_timeout" "http_request_timeout" "http_response_header_timeout" "http_response_header_timeout" -}}
{{- else if eq $provider "gcs" -}}
  {{- $_ := set $out "credentials_source" "static" -}}
  {{- $_ := set $out "json_key" (required "capi.storageCliConfig gcs: connection_config.google_json_key_string is required" (index $conn "google_json_key_string")) -}}
  {{- $_ := set $out "bucket_name" (required "capi.storageCliConfig gcs: connection_config.bucket_name is required" (index $conn "bucket_name")) -}}
  {{- $optional = dict "storage_class" "storage_class" "encryption_key" "encryption_key" "http_request_timeout" "http_request_timeout" "http_response_header_timeout" "http_response_header_timeout" -}}
{{- else if eq $provider "s3" -}}
  {{- $_ := set $out "bucket_name" (required "capi.storageCliConfig s3: connection_config.bucket_name is required" (index $conn "bucket_name")) -}}
  {{- if index $conn "use_iam_profile" -}}
    {{- $_ := set $out "credentials_source" "env_or_profile" -}}
  {{- else -}}
    {{- $_ := set $out "credentials_source" "static" -}}
    {{- $_ := set $out "access_key_id" (required "capi.storageCliConfig s3: connection_config.aws_access_key_id is required (or set use_iam_profile)" (index $conn "aws_access_key_id")) -}}
    {{- $_ := set $out "secret_access_key" (required "capi.storageCliConfig s3: connection_config.aws_secret_access_key is required (or set use_iam_profile)" (index $conn "aws_secret_access_key")) -}}
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
  {{- $_ := set $out "access_key_id" (required "capi.storageCliConfig alioss: connection_config.aliyun_accesskey_id is required" (index $conn "aliyun_accesskey_id")) -}}
  {{- $_ := set $out "access_key_secret" (required "capi.storageCliConfig alioss: connection_config.aliyun_accesskey_secret is required" (index $conn "aliyun_accesskey_secret")) -}}
  {{- $_ := set $out "endpoint" (required "capi.storageCliConfig alioss: connection_config.aliyun_oss_endpoint is required" (index $conn "aliyun_oss_endpoint")) -}}
  {{- $_ := set $out "bucket_name" (required "capi.storageCliConfig alioss: connection_config.aliyun_oss_bucket is required" (index $conn "aliyun_oss_bucket")) -}}
  {{- $optional = dict "http_request_timeout" "http_request_timeout" "http_response_header_timeout" "http_response_header_timeout" -}}
{{- else if eq $provider "dav" -}}
  {{- $_ := set $out "user" (required "capi.storageCliConfig dav: connection_config.username is required" (index $conn "username")) -}}
  {{- $_ := set $out "password" (required "capi.storageCliConfig dav: connection_config.password is required" (index $conn "password")) -}}
  {{- $_ := set $out "endpoint" (printf "%s/admin/%s" (required "capi.storageCliConfig dav: connection_config.private_endpoint is required" (index $conn "private_endpoint")) .resourceDir) -}}
  {{- $optional = dict "public_endpoint" "public_endpoint" "secret" "secret" "retry_attempts" "retry_attempts" -}}
  {{- $caCert := index $conn "ca_cert" -}}
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


{{/*
capi.validateAppDomains — fail if an internal app domain also names a router group.
Input: the app_domains list (strings and/or {name, internal, router_group_name} maps).
*/}}
{{- define "capi.validateAppDomains" -}}
{{- range $domain := . -}}
{{- if and (kindIs "map" $domain) (index $domain "internal") (hasKey $domain "router_group_name") -}}
{{- fail "cloudController.config.app_domains: router groups cannot be specified for internal domains" -}}
{{- end -}}
{{- end -}}
{{- end -}}


{{/*
capi.clientSecret — resolve a UAA client secret, falling back to the shared
oauthClientsSecret, and fail if neither is set.
Input: dict with  root (the chart root context $), name (the uaa.clients key)
*/}}
{{- define "capi.clientSecret" -}}
{{- $client := index .root.Values.cloudController.config.uaa.clients .name | default dict -}}
{{- $client.secret | default .root.Values.oauthClientsSecret | required (printf "cloudController.config.uaa.clients.%s.secret or oauthClientsSecret must be provided" .name) | quote -}}
{{- end -}}


{{/*
capi.databaseEncryption — render the db_encryption_key line and the database_encryption
block, mirroring the BOSH ERB. database_encryption.keys may be either:
  - a map {label: key, ...} with an explicit current_key_label, or
  - a list [{label, encryption_key, active}] whose single active entry sets current_key_label.
Input: the cloudController.config map.
*/}}
{{- define "capi.databaseEncryption" -}}
{{- $enc := .database_encryption -}}
{{- $legacyKey := .db_encryption_key -}}
{{- $rawKeys := $enc.keys | default dict -}}{{- /* default dict: treat unset keys as "none" */ -}}
{{- $keys := dict -}}
{{- $currentLabel := $enc.current_key_label | default "" -}}
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
{{- if not $enc.skip_validation -}}
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
  pbkdf2_hmac_iterations: {{ $enc.experimental_pbkdf2_hmac_iterations }}
{{- end -}}
{{- end -}}

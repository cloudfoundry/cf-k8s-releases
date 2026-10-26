{{- define "loggregatorAgent.tags" -}}
{{- $pairs := list -}}
{{- range $k, $v := mergeOverwrite (dict "deployment" (tpl .values.deployment .root) "job" "forwarder-agent" "index" "$(POD_NAME)" "ip" "$(POD_IP)") .values.tags -}}
{{- $pairs = append $pairs (printf "%s:%v" $k $v) -}}
{{- end -}}
{{- join "," $pairs -}}
{{- end -}}

{{- define "loggregatorAgent.podIdentity" -}}
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
{{- end -}}

{{- define "loggregatorAgent.aggregateDrains" -}}
{{- $drains := list -}}
{{- if kindIs "string" . -}}
{{- if . -}}
{{- range splitList "," . -}}
{{- $drains = append $drains (dict "url" .) -}}
{{- end -}}
{{- end -}}
{{- else -}}
{{- range . -}}
{{- if kindIs "slice" . -}}
{{- $drains = concat $drains (include "loggregatorAgent.aggregateDrains" . | fromJsonArray) -}}
{{- else -}}
{{- $drains = append $drains . -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- toJson $drains -}}
{{- end -}}

{{- define "loggregatorAgent.blacklistedRanges" -}}
{{- $ranges := list -}}
{{- range . -}}
{{- $ranges = append $ranges (printf "%s-%s" .start .end) -}}
{{- end -}}
{{- join "," $ranges -}}
{{- end -}}

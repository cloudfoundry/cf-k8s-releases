{{- define "loggregatorAgent.tags" -}}
{{- $pairs := list -}}
{{- range $k, $v := . -}}
{{- $pairs = append $pairs (printf "%s:%s" $k $v) -}}
{{- end -}}
{{- join "," $pairs -}}
{{- end -}}

{{- define "loggregatorAgent.blacklistedRanges" -}}
{{- $ranges := list -}}
{{- range . -}}
{{- $ranges = append $ranges (printf "%s-%s" .start .end) -}}
{{- end -}}
{{- join "," $ranges -}}
{{- end -}}

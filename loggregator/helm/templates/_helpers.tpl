{{/*
Comma-separated list of every doppler pod's stable StatefulSet DNS address.
Consumers (reverse_log_proxy, trafficcontroller) must dial every doppler to
receive the complete log stream, so this tracks doppler.replicas.
*/}}
{{- define "loggregator.dopplerAddrs" -}}
{{- $addrs := list -}}
{{- range $i := until (int .Values.doppler.replicas) -}}
{{- $addrs = append $addrs (printf "doppler-%d.doppler.%s.svc.cluster.local:%v" $i $.Release.Namespace $.Values.doppler.grpcPort) -}}
{{- end -}}
{{- join "," $addrs -}}
{{- end -}}

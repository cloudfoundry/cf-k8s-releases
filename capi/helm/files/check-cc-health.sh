#!/bin/sh

# Adapted from CAPI's cloud_controller_api_health_check.erb. Keep retries
# bounded below route registrar's 6s timeout, including the final attempt.
exec timeout --signal=KILL 5s curl \
  --fail --silent --show-error --insecure \
  --max-time 2 --retry-max-time 4 --retry 100000 --retry-delay 1 \
  "https://localhost:{{ .Values.cloudController.config.publicTLS.port }}/healthz"

#!/bin/sh -e

jq -s --arg podIP "$POD_IP" '
  add | if (.host // "") == "" then .host = $podIP else . end
' /etc/route-registrar-template/route-registrar.json > /tmp/route-registrar.json

exec /usr/local/bin/route-registrar -configPath /tmp/route-registrar.json "$@"

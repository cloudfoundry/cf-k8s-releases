#!/bin/sh

set -e

if [ "${IS_DRAINING:-false}" = true ]; then
    sed -i '/^global$/a\
    setenv IS_DRAINING true' /haproxy/haproxy.conf
fi

reload_response=$(printf 'reload\n' | socat -t 300 - UNIX-CONNECT:/haproxy/master.sock)
printf '%s\n' "$reload_response"
printf '%s\n' "$reload_response" | grep -q '^Success=1$'

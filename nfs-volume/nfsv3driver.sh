#!/bin/bash

set -e

# Start rpcbind manually instead of calling `service rpcbind start`. If the /run
# carries an ACL or SELinux label, `ls -l` shows "drwxr-xr-x+" / "drwxr-xr-x.",
# and the init script's strict ownership check wrongly fails on the suffix.
install -d -o _rpc -g root -m 0755 /run/rpcbind

OPTIONS="-w"
[ -f /etc/default/rpcbind ] && . /etc/default/rpcbind

/usr/sbin/rpcbind $OPTIONS

exec /usr/local/bin/nfsv3driver "$@"

#!/bin/sh
set -Eeuo pipefail

# change UID/GID
export GTS_UID="${GTS_UID:-1000}"
export GTS_GID="${GTS_GID:-1000}"

usermod -u "$GTS_UID" gotosocial
groupmod -g "$GTS_GID" gotosocial

# fix permissions
chown -R gotosocial:gotosocial /gotosocial

exec setpriv --reuid=$GTS_UID --regid=$GTS_GID --init-groups "$@"

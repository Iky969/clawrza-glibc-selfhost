#!/bin/sh
# Build script executed INSIDE the guest by spkg. Uses the guest gcc + make.
set -eu
DESTDIR=$1
[ -n "$DESTDIR" ] || { echo "usage: build.sh <destdir>" >&2; exit 2; }
cd "$(dirname "$0")"
make clean >/dev/null 2>&1 || true
make
install -D -m 0755 hello "$DESTDIR/usr/bin/hello"
install -D -m 0644 README "$DESTDIR/usr/share/doc/hello/README"

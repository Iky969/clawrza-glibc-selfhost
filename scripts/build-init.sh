#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/env.sh"

# kinit only needs libc; compile with the host compiler for the bootstrap,
# then recompile with the in-tree gcc once the toolchain exists.
CC_HOST=gcc
if [ -x "$SYSROOT/usr/bin/gcc" ]; then
    CC_GUEST="$SYSROOT/usr/bin/gcc"
else
    CC_GUEST="$CC_HOST"
fi

log "building kinit with $CC_GUEST"
"$CC_GUEST" -O2 -Wall -Wextra -o "$BUILD/kinit" "$ROOT/src/init/kinit.c"
install -m 0755 "$BUILD/kinit" "$SYSROOT/sbin/init"
install -m 0755 "$BUILD/kinit" "$SYSROOT/sbin/kinit"
log "kinit installed: $(ls -lh "$SYSROOT/sbin/init" | awk '{print $5}')"

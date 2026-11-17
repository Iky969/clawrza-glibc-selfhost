#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/env.sh"

log "assembling rootfs in $SYSROOT"

install -d -m 0755 "$SYSROOT"/{bin,sbin,usr/bin,usr/sbin,usr/lib,usr/src,etc,dev,proc,sys,run,tmp,root,var/log,var/lib}
install -d -m 0755 "$SYSROOT/var/lib/spkg"

install -m 0644 "$ROOT/configs/fstab"     "$SYSROOT/etc/fstab"
install -m 0644 "$ROOT/configs/hostname"  "$SYSROOT/etc/hostname"
install -m 0644 "$ROOT/configs/passwd"    "$SYSROOT/etc/passwd"
install -m 0644 "$ROOT/configs/group"     "$SYSROOT/etc/group"
install -m 0644 "$ROOT/configs/init.conf" "$SYSROOT/etc/init.conf"

cat > "$SYSROOT/etc/profile" <<'EOF'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
PS1='clawrza:\w# '
EOF

install -m 0755 "$ROOT/src/spkg/spkg"      "$SYSROOT/usr/bin/spkg"
install -m 0755 "$ROOT/src/spkg/selftest.sh" "$SYSROOT/usr/bin/selftest"

# sample source package, present inside the guest
install -d -m 0755 "$SYSROOT/usr/src/packages"
cp -a "$ROOT/src/spkg/packages/hello-1.0" "$SYSROOT/usr/src/packages/"

cat > "$SYSROOT/etc/os-release" <<'EOF'
NAME=clawrza-glibc-selfhost
ID=clawrza
PRETTY_NAME="clawrza self-hosted GLIBC distro"
VERSION_ID=0.1
EOF

log "rootfs contents (top level)"
ls "$SYSROOT"
log "rootfs size: $(du -sh "$SYSROOT" | cut -f1)"

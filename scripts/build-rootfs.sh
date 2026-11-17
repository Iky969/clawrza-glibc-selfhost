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

install -d -m 0755 "$SYSROOT/usr/share/udhcpc"
install -m 0755 "$ROOT/configs/udhcpc-default.script" \
    "$SYSROOT/usr/share/udhcpc/default.script"

cat > "$SYSROOT/etc/profile" <<'EOF'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
PS1='clawrza:\w# '
EOF

install -m 0755 "$ROOT/src/spkg/spkg"      "$SYSROOT/usr/bin/spkg"
install -m 0755 "$ROOT/src/spkg/selftest.sh" "$SYSROOT/usr/bin/selftest"
ln -sf gcc "$SYSROOT/usr/bin/cc"
# gcc invokes cc1 by bare name; make it discoverable on PATH inside the guest.
# The symlink MUST be relative: a host absolute path would be broken in QEMU.
CC1=$(find "$SYSROOT/usr/libexec" -name cc1 -type f 2>/dev/null | head -1)
if [ -n "$CC1" ]; then
    GVER=$(basename "$(dirname "$CC1")")
    ln -sfn "../libexec/gcc/$TARGET/$GVER/cc1" "$SYSROOT/usr/bin/cc1"
fi

# The host-built gcc/cc1/as/ld are linked against host shared libraries
# (libisl, libmpc, libmpfr, libgmp, zlib, zstd). Copy those into the guest so
# the toolchain is actually runnable inside QEMU. Never overwrite our libc.
copy_host_deps() {
    local bin="$1" lib b
    [ -f "$bin" ] || return 0
    ldd "$bin" 2>/dev/null | sed -n 's/.*=> \(\/[^ ]*\).*/\1/p' | while read -r lib; do
        b=$(basename "$lib")
        case "$b" in
            libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|ld-linux*) continue ;;
        esac
        if [ ! -e "$SYSROOT/usr/lib/$b" ] && [ ! -e "$SYSROOT/lib64/$b" ]; then
            install -D -m 0644 "$lib" "$SYSROOT/usr/lib/$b"
        fi
    done
}
for b in usr/bin/gcc usr/bin/cc1 usr/bin/as usr/bin/ld usr/bin/make bin/busybox; do
    copy_host_deps "$SYSROOT/$b"
done
CC1=$(find "$SYSROOT/usr/libexec" -name cc1 -type f 2>/dev/null | head -1)
[ -n "$CC1" ] && copy_host_deps "$CC1"

# glibc's loader in this sysroot searches /lib and /lib64 but not /usr/lib
# unless an ld.so.cache exists. Mirror the shared objects into /lib so the
# toolchain (cc1, as, ld) can resolve them without a cache.
install -d -m 0755 "$SYSROOT/lib"
for so in "$SYSROOT"/usr/lib/*.so*; do
    [ -e "$so" ] || continue
    ln -sfn "../usr/lib/$(basename "$so")" "$SYSROOT/lib/$(basename "$so")"
done
cat > "$SYSROOT/etc/ld.so.conf" <<'EOF'
/lib
/lib64
/usr/lib
EOF
# source for in-guest rebuild proof (kinit is C, spkg is a POSIX sh script)
install -d -m 0755 "$SYSROOT/usr/src/clawrza"
install -m 0644 "$ROOT/src/init/kinit.c" "$SYSROOT/usr/src/clawrza/kinit.c"
install -m 0644 "$ROOT/src/spkg/spkg"   "$SYSROOT/usr/src/clawrza/spkg.sh"
install -m 0644 "$ROOT/src/rebuild/Makefile" "$SYSROOT/usr/src/clawrza/Makefile"

# busybox install drops a /sbin/init symlink; our PID 1 must win, always.
if [ -f "$BUILD/kinit" ]; then
    install -m 0755 "$BUILD/kinit" "$SYSROOT/sbin/init"
    install -m 0755 "$BUILD/kinit" "$SYSROOT/sbin/kinit"
fi

log "host shared libraries copied for guest toolchain; /lib symlinks created"

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

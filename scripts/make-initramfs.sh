#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/env.sh"

INITRD="$BUILD/initrd"
rm -rf "$INITRD"; mkdir -p "$INITRD"/{bin,sbin,lib,lib64,proc,sys,dev,run,newroot}

cp -a "$SYSROOT/bin/busybox" "$INITRD/bin/busybox"
for a in sh mount umount switch_root mkdir cat echo sleep ls; do
    ln -sf busybox "$INITRD/bin/$a"
done
# dynamic loader + libc needed by busybox
cp -a "$SYSROOT/lib/." "$INITRD/lib/" 2>/dev/null || true
[ -d "$SYSROOT/lib64" ] && cp -a "$SYSROOT/lib64/." "$INITRD/lib64/" || true

cat > "$INITRD/init" <<'EOF'
#!/bin/sh
# early userspace: mount pseudo filesystems, find root, switch_root
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t tmpfs tmpfs /run

ROOT=/dev/vda2
for arg in $(cat /proc/cmdline); do
    case "$arg" in root=*) ROOT=${arg#root=} ;; esac
done

n=0
while [ ! -b "$ROOT" ] && [ $n -lt 50 ]; do sleep 0.1; n=$((n+1)); done
[ -b "$ROOT" ] || { echo "initramfs: root device $ROOT not found"; exec /bin/sh; }

echo "initramfs: switch_root to $ROOT"
mount -t ext4 -o rw "$ROOT" /newroot || { echo "initramfs: mount failed"; exec /bin/sh; }
mount --move /dev /newroot/dev
mount --move /sys /newroot/sys
mount --move /proc /newroot/proc
mount --move /run /newroot/run
exec switch_root /newroot /sbin/init
EOF
chmod 0755 "$INITRD/init"

log "packing initramfs"
( cd "$INITRD" && find . -mindepth 1 -print0 | LC_ALL=C sort -z |
  cpio --null -ov --format=newc 2>/dev/null | gzip -9 > "$DISTRO/initramfs.cpio.gz" )
log "initramfs: $(ls -lh "$DISTRO/initramfs.cpio.gz" | awk '{print $5}')"

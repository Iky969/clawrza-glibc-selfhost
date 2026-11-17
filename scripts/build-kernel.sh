#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/env.sh"

cd "$SRCDIR/linux-${KERNEL_VER}"
log "configuring kernel $KERNEL_VER"
make defconfig > "$BUILD/kernel.log" 2>&1
for opt in CONFIG_VIRTIO CONFIG_VIRTIO_PCI CONFIG_VIRTIO_BLK CONFIG_VIRTIO_NET \
           CONFIG_VIRTIO_CONSOLE CONFIG_EXT4_FS CONFIG_DEVTMPFS CONFIG_DEVTMPFS_MOUNT \
           CONFIG_TMPFS CONFIG_SERIAL_8250 CONFIG_SERIAL_8250_CONSOLE \
           CONFIG_CGROUPS CONFIG_BLK_DEV_INITRD CONFIG_RD_GZIP CONFIG_RD_XZ; do
    ./scripts/config --enable "$opt" >> "$BUILD/kernel.log" 2>&1
done
# avoid host OpenSSL dependency for certificate extraction
./scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS "" >> "$BUILD/kernel.log" 2>&1
./scripts/config --disable CONFIG_MODULE_SIG >> "$BUILD/kernel.log" 2>&1
for opt in CONFIG_DRM CONFIG_SOUND CONFIG_WIRELESS CONFIG_WLAN CONFIG_BLUETOOTH \
           CONFIG_TABLET_USB_ACECAD CONFIG_TC; do
    ./scripts/config --disable "$opt" >> "$BUILD/kernel.log" 2>&1
done
make olddefconfig >> "$BUILD/kernel.log" 2>&1
log "building bzImage (make -j$JOBS)"
make -j"$JOBS" bzImage >> "$BUILD/kernel.log" 2>&1 || {
    tail -50 "$BUILD/kernel.log" >&2; exit 1; }
install -m 0644 arch/x86/boot/bzImage "$DISTRO/bzImage"
log "kernel ready: $(ls -lh "$DISTRO/bzImage" | awk '{print $5}')"

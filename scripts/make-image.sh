#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/env.sh"

IMG="$DISTRO/clawrza.img"
LIMINE=$(find "$SRCDIR" -maxdepth 1 -type d -name 'limine-*' | head -1)
LIMINE_BIN="$SRCDIR/limine-binary/limine-binary"
[ -x "$LIMINE_BIN/limine-deploy" ] || die "limine prebuilt binaries not fetched"
need qemu-img
need sgdisk
need sudo

log "creating 512 MiB GPT image"
rm -f "$IMG"
truncate -s 512M "$IMG"
sgdisk --zap-all "$IMG" >/dev/null
sgdisk -a 1 -n 3:34:2047 -t 3:ef02 -c 3:bios_boot "$IMG" >/dev/null
sgdisk -a 1 -n 1:2048:133119 -t 1:ef00 -c 1:clawrza_boot "$IMG" >/dev/null
sgdisk -a 1 -n 2:133120:0 -t 2:8300 -c 2:clawrza_root "$IMG" >/dev/null
sgdisk -p "$IMG" | sed -n '1,14p'

LOOP=$(sudo losetup -fP --show "$IMG")
cleanup() {
    sudo umount "$BUILD/mnt/root" 2>/dev/null || true
    sudo umount "$BUILD/mnt/boot" 2>/dev/null || true
    sudo losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

log "formatting partitions on $LOOP"
sudo mkfs.vfat -F32 -n CLAWRZABOOT "${LOOP}p1" >/dev/null
sudo mkfs.ext4 -F -q -L clawrza_root "${LOOP}p2"

rm -rf "$BUILD/mnt"; mkdir -p "$BUILD/mnt/root" "$BUILD/mnt/boot"
sudo mount "${LOOP}p2" "$BUILD/mnt/root"
sudo cp -a "$SYSROOT/." "$BUILD/mnt/root/"
sudo umount "$BUILD/mnt/root"

sudo mount "${LOOP}p1" "$BUILD/mnt/boot"
sudo install -m 0644 "$DISTRO/bzImage"          "$BUILD/mnt/boot/bzImage"
sudo install -m 0644 "$DISTRO/initramfs.cpio.gz" "$BUILD/mnt/boot/initramfs.cpio.gz"
sudo install -m 0644 "$ROOT/configs/limine.cfg"  "$BUILD/mnt/boot/limine.conf"
sudo mkdir -p "$BUILD/mnt/boot/EFI/BOOT"
if [ -f "$LIMINE_BIN/limine-bios.sys" ]; then
    sudo install -m 0644 "$LIMINE_BIN/limine-bios.sys" "$BUILD/mnt/boot/limine-bios.sys"
fi
for f in BOOTX64.EFI BOOTIA32.EFI; do
    p=$(find "$LIMINE_BIN" -name "$f" | head -1)
    [ -n "$p" ] && sudo install -m 0644 "$p" "$BUILD/mnt/boot/EFI/BOOT/$f"
done
sudo cp "$ROOT/configs/limine.cfg" "$BUILD/mnt/boot/EFI/BOOT/limine.conf" 2>/dev/null || true
sudo umount "$BUILD/mnt/boot"

log "installing Limine to BIOS boot partition (GPT index 3)"
sudo "$LIMINE_BIN/limine-deploy" bios-install --force --quiet "$LOOP" 3 || \
echo "WARNING: limine bios-install failed; BIOS boot may not work"
sync
sudo chmod 0666 "$IMG"
log "image ready: $(ls -lh "$IMG" | awk '{print $5}')  $IMG"

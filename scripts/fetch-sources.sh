#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/env.sh"

fetch() {
    local name="$1" url="$2" file="$3" dir="$4"
    if [ ! -f "$SRCDIR/$file" ]; then
        log "downloading $name"
        curl -fL --retry 3 --connect-timeout 20 -o "$SRCDIR/$file" "$url"
    else
        echo "cached: $file"
    fi
    if [ ! -d "$SRCDIR/$dir" ]; then
        log "extracting $name"
        tar -xf "$SRCDIR/$file" -C "$SRCDIR"
    fi
}

fetch linux       "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VER}.tar.xz"   "linux-${KERNEL_VER}.tar.xz"   "linux-${KERNEL_VER}"
fetch binutils    "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz"          "binutils-${BINUTILS_VER}.tar.xz"  "binutils-${BINUTILS_VER}"
fetch gcc         "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"          "gcc-${GCC_VER}.tar.xz"        "gcc-${GCC_VER}"
fetch glibc       "https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VER}.tar.xz"                   "glibc-${GLIBC_VER}.tar.xz"    "glibc-${GLIBC_VER}"
fetch make        "https://ftp.gnu.org/gnu/make/make-${MAKE_VER}.tar.gz"                      "make-${MAKE_VER}.tar.gz"     "make-${MAKE_VER}"
fetch busybox     "https://busybox.net/downloads/busybox-${BUSYBOX_VER}.tar.bz2"               "busybox-${BUSYBOX_VER}.tar.bz2" "busybox-${BUSYBOX_VER}"
fetch limine      "https://github.com/limine-bootloader/limine/releases/download/v${LIMINE_VER}/limine-${LIMINE_VER}.tar.xz" "limine-${LIMINE_VER}.tar.xz" "limine-${LIMINE_VER}"

# Official prebuilt bootloader payloads (BIOS stage2 + UEFI binaries + deploy tool)
if [ ! -f "$SRCDIR/limine-binary-${LIMINE_VER}.tar.xz" ]; then
    log "downloading limine prebuilt binaries"
    curl -fL --retry 3 --connect-timeout 20 \
        -o "$SRCDIR/limine-binary-${LIMINE_VER}.tar.xz" \
        "https://github.com/limine-bootloader/limine/releases/download/v${LIMINE_VER}/limine-binary.tar.xz"
fi
mkdir -p "$SRCDIR/limine-binary"
if [ ! -x "$SRCDIR/limine-binary/limine-binary/limine-deploy" ]; then
    tar -xf "$SRCDIR/limine-binary-${LIMINE_VER}.tar.xz" -C "$SRCDIR/limine-binary"
    ( cd "$SRCDIR/limine-binary/limine-binary" && \
      cc -O2 -std=c99 -D_FILE_OFFSET_BITS=64 limine.c -o limine-deploy )
fi

( cd "$SRCDIR" && sha256sum *.tar.* > SOURCE_SHA256SUMS )
log "all sources ready in $SRCDIR"
ls -lh "$SRCDIR"/*.tar.* | sed 's/^/  /'

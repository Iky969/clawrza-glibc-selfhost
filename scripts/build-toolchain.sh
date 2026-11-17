#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/env.sh"

stage() {
    log "$1"
    shift
    "$@" > "$BUILD/toolchain-$STAGE.log" 2>&1 || {
        echo "FAILED at stage $STAGE; tail of $BUILD/toolchain-$STAGE.log:" >&2
        tail -40 "$BUILD/toolchain-$STAGE.log" >&2
        exit 1
    }
}

# ---------------------------------------------------------------- 1. headers
STAGE=kernel-headers
log "installing kernel headers into $SYSROOT/usr/include"
make -C "$SRCDIR/linux-${KERNEL_VER}" mrproper >/dev/null 2>&1 || true
make -C "$SRCDIR/linux-${KERNEL_VER}" headers_install \
    INSTALL_HDR_PATH="$SYSROOT/usr" > "$BUILD/toolchain-$STAGE.log" 2>&1

# ---------------------------------------------------------------- 2. glibc
STAGE=glibc
rm -rf "$BUILD/glibc-build"; mkdir -p "$BUILD/glibc-build"; cd "$BUILD/glibc-build"
log "configuring glibc $GLIBC_VER"
"$SRCDIR/glibc-${GLIBC_VER}/configure" \
    --prefix=/usr \
    --build="$TARGET" --host="$TARGET" \
    --enable-shared --disable-nls --disable-werror \
    --with-headers="$SYSROOT/usr/include" \
    CC=gcc CFLAGS="-O2 -g0" > "$BUILD/toolchain-$STAGE.log" 2>&1 || {
        tail -40 "$BUILD/toolchain-$STAGE.log" >&2; exit 1; }
log "building glibc (make -j$JOBS)"
make -j"$JOBS" >> "$BUILD/toolchain-$STAGE.log" 2>&1 || {
    tail -40 "$BUILD/toolchain-$STAGE.log" >&2; exit 1; }
log "installing glibc into sysroot"
make install DESTDIR="$SYSROOT" >> "$BUILD/toolchain-$STAGE.log" 2>&1 || {
    tail -40 "$BUILD/toolchain-$STAGE.log" >&2; exit 1; }

# ---------------------------------------------------------------- 3. binutils
STAGE=binutils
rm -rf "$BUILD/binutils-build"; mkdir -p "$BUILD/binutils-build"; cd "$BUILD/binutils-build"
log "configuring binutils $BINUTILS_VER"
"$SRCDIR/binutils-${BINUTILS_VER}/configure" \
    --prefix=/usr --build="$TARGET" --host="$TARGET" --target="$TARGET" \
    --disable-nls --disable-werror --disable-multilib --enable-shared \
    > "$BUILD/toolchain-$STAGE.log" 2>&1 || { tail -40 "$BUILD/toolchain-$STAGE.log" >&2; exit 1; }
log "building binutils (make -j$JOBS)"
make -j"$JOBS" all >> "$BUILD/toolchain-$STAGE.log" 2>&1 || {
    tail -40 "$BUILD/toolchain-$STAGE.log" >&2; exit 1; }
make install DESTDIR="$SYSROOT" >> "$BUILD/toolchain-$STAGE.log" 2>&1 || {
    tail -40 "$BUILD/toolchain-$STAGE.log" >&2; exit 1; }

# ---------------------------------------------------------------- 4. gcc
STAGE=gcc
rm -rf "$BUILD/gcc-build"; mkdir -p "$BUILD/gcc-build"; cd "$BUILD/gcc-build"
log "configuring gcc $GCC_VER (C only, faster bootstrap)"
"$SRCDIR/gcc-${GCC_VER}/configure" \
    --prefix=/usr --build="$TARGET" --host="$TARGET" --target="$TARGET" \
    --enable-languages=c \
    --disable-nls --disable-werror --disable-multilib --disable-bootstrap \
    --disable-libssp --disable-libgomp --disable-libquadmath \
    --with-system-zlib \
    --with-native-system-header-dir=/usr/include \
    --with-build-sysroot="$SYSROOT" \
    --with-local-prefix=/usr \
    CFLAGS="-O2 -g0" CXXFLAGS="-O2 -g0" \
    LDFLAGS="-Wl,-rpath,/usr/lib -Wl,-rpath,/lib" \
    > "$BUILD/toolchain-$STAGE.log" 2>&1 || { tail -40 "$BUILD/toolchain-$STAGE.log" >&2; exit 1; }
log "building gcc (make -j$JOBS, this is the slow step)"
make -j"$JOBS" >> "$BUILD/toolchain-$STAGE.log" 2>&1 || {
    tail -60 "$BUILD/toolchain-$STAGE.log" >&2; exit 1; }
log "installing gcc into sysroot"
make install DESTDIR="$SYSROOT" >> "$BUILD/toolchain-$STAGE.log" 2>&1 || {
    tail -40 "$BUILD/toolchain-$STAGE.log" >&2; exit 1; }

# ---------------------------------------------------------------- 5. make
STAGE=make
rm -rf "$BUILD/make-build"; mkdir -p "$BUILD/make-build"; cd "$BUILD/make-build"
log "building make $MAKE_VER"
"$SRCDIR/make-${MAKE_VER}/configure" --prefix=/usr > "$BUILD/toolchain-$STAGE.log" 2>&1
make -j"$JOBS" >> "$BUILD/toolchain-$STAGE.log" 2>&1 || {
    tail -40 "$BUILD/toolchain-$STAGE.log" >&2; exit 1; }
make install DESTDIR="$SYSROOT" >> "$BUILD/toolchain-$STAGE.log" 2>&1

# ---------------------------------------------------------------- 6. busybox
STAGE=busybox
cd "$SRCDIR/busybox-${BUSYBOX_VER}"
make mrproper >/dev/null 2>&1 || true
make defconfig > "$BUILD/toolchain-$STAGE.log" 2>&1
# enable applets needed by the guest
for opt in CONFIG_CTTYHACK CONFIG_ASH CONFIG_SH_MATH_SUPPORT CONFIG_UNXZ \
           CONFIG_GZIP CONFIG_FEATURE_SEAMLESS_GZ CONFIG_NSLOOKUP \
           CONFIG_PING CONFIG_IFCONFIG CONFIG_UDHCPC CONFIG_SWITCH_ROOT \
           CONFIG_MOUNT CONFIG_FEATURE_MOUNT_FAKE; do
    sed -i "s/^# ${opt} is not set/${opt}=y/" .config
    grep -q "^${opt}=y" .config || echo "${opt}=y" >> .config
done
make oldconfig >> "$BUILD/toolchain-$STAGE.log" 2>&1 || true
log "building busybox (make -j$JOBS)"
make -j"$JOBS" >> "$BUILD/toolchain-$STAGE.log" 2>&1 || {
    tail -60 "$BUILD/toolchain-$STAGE.log" >&2; exit 1; }
make CONFIG_PREFIX="$SYSROOT" install >> "$BUILD/toolchain-$STAGE.log" 2>&1

# ---------------------------------------------------------------- verify
log "toolchain summary"
printf '  gcc    : '; "$SYSROOT/usr/bin/gcc" --version 2>/dev/null | head -1 || echo MISSING
printf '  ld     : '; "$SYSROOT/usr/bin/ld" --version 2>/dev/null | head -1 || echo MISSING
printf '  libc   : '; ls "$SYSROOT"/lib/libc.so.6 2>/dev/null || echo MISSING
printf '  make   : '; "$SYSROOT/usr/bin/make" --version 2>/dev/null | head -1 || echo MISSING
printf '  sh     : '; "$SYSROOT/bin/sh" -c 'echo busybox-ok' 2>/dev/null || echo MISSING
printf '  total  : '; du -sh "$SYSROOT" | cut -f1

#!/bin/sh
# Shared environment for all build scripts. Source this file.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
SRCDIR="$BUILD/src"
SYSROOT="$BUILD/sysroot"
DISTRO="$BUILD/distro"
JOBS="$(nproc)"

KERNEL_VER=6.12.74
BINUTILS_VER=2.44
GCC_VER=14.2.0
GLIBC_VER=2.41
MAKE_VER=4.4.1
BUSYBOX_VER=1.37.0
LIMINE_VER=12.10.0

TARGET=x86_64-linux-gnu

mkdir -p "$BUILD" "$SRCDIR" "$SYSROOT" "$DISTRO"

log()   { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die()   { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
need()  { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }

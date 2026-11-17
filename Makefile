ROOT     := $(shell pwd)
JOBS     := $(shell nproc)
BUILD    := $(ROOT)/build
SYSROOT  := $(BUILD)/sysroot
DISTRO   := $(BUILD)/distro

.PHONY: all fetch toolchain kernel init rootfs initramfs image test clean distclean help

all: fetch toolchain kernel rootfs initramfs
	@echo "Build complete. Run: sudo make image && make test"

help:
	@echo "targets: fetch toolchain kernel rootfs initramfs image test all clean distclean"

fetch:
	bash scripts/fetch-sources.sh

toolchain: fetch
	bash scripts/build-toolchain.sh

kernel: fetch
	bash scripts/build-kernel.sh

init:
	bash scripts/build-init.sh

rootfs: toolchain kernel init
	bash scripts/build-rootfs.sh

initramfs: rootfs
	bash scripts/make-initramfs.sh

image: initramfs
	sudo bash scripts/make-image.sh

test: image
	bash scripts/test-boot.sh

clean:
	rm -rf $(BUILD)/glibc-build $(BUILD)/binutils-build $(BUILD)/gcc-build \
	       $(BUILD)/make-build $(BUILD)/busybox-build

distclean:
	sudo rm -rf $(BUILD)

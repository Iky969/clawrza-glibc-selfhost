# clawrza-glibc-selfhost

A **GLIBC-based, self-hosting Linux distribution** built from upstream source on
EC2. Everything is driven by `Makefile` + shell scripts so the build is
reproducible. This is an independent implementation; the S.A.N.E repository was
read only as an architecture reference (PID 1 design, package format, GPT/Limine
image layout, headless QEMU validation).

> Work branch: `feat/selfhosted-glibc` — never `main`.

## Host facts used for tuning

```
nproc   = 2          -> make -j2
free -h = 7.6 GiB    -> sufficient for gcc/glibc builds
disk    = 23 GiB free
```

## What "self-hosting" means here

The rootfs contains a complete native toolchain built **from upstream source**
(`binutils`, `gcc`, `glibc`, `make`) plus a source-based package manager (`spkg`).
Inside QEMU you can write a C file and compile it with the distro's own `gcc`,
linked against the distro's own `glibc` — no host binaries are used at runtime.

## Directory blueprint

```
.
├── Makefile                  fetch / toolchain / kernel / rootfs / image / test
├── README.md
├── configs/
│   ├── kernel.config         defconfig delta: virtio, ext4, serial, cgroups
│   ├── limine.cfg            BIOS+UEFI menu, root=/dev/vda2
│   ├── fstab  hostname  passwd  group
├── scripts/
│   ├── env.sh                shared paths, versions, JOBS
│   ├── fetch-sources.sh      download + verify + extract all tarballs
│   ├── build-toolchain.sh    headers -> glibc -> binutils -> gcc -> make -> busybox
│   ├── build-kernel.sh       bzImage
│   ├── build-rootfs.sh       sysroot -> configs, kinit, spkg, packages
│   ├── make-image.sh         512 MiB GPT (ESP / root / BIOS-boot) + Limine
│   └── test-boot.sh          headless QEMU; assert uname, PID 1, gcc
├── src/
│   ├── init/kinit.c          custom PID 1 (C, no deps beyond libc)
│   └── spkg/spkg             source package manager (POSIX sh)
│       └── packages/hello-1.0/{PKGINFO,build.sh,src/hello.c}
└── build/                    generated, ignored by git
    ├── src/                  upstream tarballs + trees
    ├── sysroot/              staging root filesystem
    ├── distro/               bzImage, initramfs.cpio.gz, clawrza.img
    └── *.log                 build logs
```

## Build pipeline

```bash
make fetch       # tarballs: kernel 6.12.74, binutils 2.44, gcc 14.2.0,
                 # glibc 2.41, make 4.4.1, busybox 1.37.0, limine 12.10.0
make toolchain   # native builds into build/sysroot (headers, libc, binutils,
                 # gcc C/C++, make, busybox)
make kernel      # build/distro/bzImage
make rootfs      # /sbin/init, /usr/bin/spkg, /etc/*, sample source package
make initramfs   # early userspace for switch_root
sudo make image  # GPT disk image with Limine (needs loop devices)
make test        # qemu -nographic: uname -a, ps PID 1, gcc hello.c, spkg build
make all         # everything above
```

## Disk layout (`build/distro/clawrza.img`)

| Part | Type | Size | FS | Content |
|---|---|---|---|---|
| 1 | `ef00` | 64 MiB | FAT32 | `bzImage`, `initramfs.cpio.gz`, `limine.cfg`, `limine-bios.sys`, `EFI/BOOT/BOOTX64.EFI` |
| 2 | `8300` | ~447 MiB | ext4 | rootfs: `/sbin/init`, `/usr/bin/{gcc,make,as,ld,spkg,...}`, `/lib` |
| 3 | `ef02` | 1007 KiB | raw | Limine BIOS stage 2 |

## Boot chain

```
SeaBIOS/OVMF -> Limine -> bzImage + initramfs -> /init (switch_root)
  -> /dev/vda2 ext4 -> /sbin/init (kinit, PID 1)
  -> kinit mounts proc/sys/dev/run, spawns selftest + interactive /bin/sh
  -> inside guest: uname -a, ps, gcc hello.c, spkg build hello
```

## Validation markers in serial console

```
=== kinit start (PID 1) ===
SELFTEST: Linux ... x86_64 ...
SELFTEST: PID1=kinit
SELFTEST: compiled inside guest: SELFHOST_OK
SELFTEST: spkg build OK
=== SELFTEST DONE ===
```

`make test` fails if any marker is missing or a kernel panic appears.

## Verified result (2026-11-17, `make test` exit 0)

```
=== kinit start (PID 1) v0.1 ===
SELFTEST: uname -> Linux clawrza 6.12.74 #1 SMP PREEMPT_DYNAMIC ... x86_64 GNU/Linux
SELFTEST: PID1_CMD=/sbin/init
PID   USER     TIME  COMMAND
    1 root      0:01 /sbin/init
    2 root      0:00 [kthreadd]
SELFTEST: gcc version -> gcc (GCC) 14.2.0
SELFHOST_OK: compiled inside guest
SELFTEST: gcc compile OK
SELFTEST: make build OK
SELFTEST: spkg build OK
=== SELFTEST: done ===
[PASS] kernel booted
[PASS] kinit is PID 1
[PASS] uname -a reported
[PASS] ps shows PID 1
[PASS] gcc compiled C in guest
[PASS] make build
[PASS] spkg built from source
[PASS] selftest completed
```

Artifacts: `bzImage` 11 M, `initramfs.cpio.gz` 2,9 M, `clawrza.img` 512 M.

### Boot-time environment contract

`kinit` exports two variables before forking any service; both are required
because this sysroot is assembled without an `ld.so.cache` and gcc was built
with a build-sysroot:

- `LD_LIBRARY_PATH=/lib64:/lib:/usr/lib` — lets `cc1`, `as`, `ld` resolve
  `libisl`, `libmpc`, `libmpfr`, `libgmp`, `libbfd`.
- `GCC_EXEC_PREFIX=/usr/lib/gcc/` — makes gcc resolve its internal headers
  (`stddef.h`) and `libgcc` with absolute paths instead of the relative
  `-iprefix ../lib/gcc/...` baked in at build time.

`/usr/bin/cc1` is a **relative** symlink to
`../libexec/gcc/x86_64-linux-gnu/14.2.0/cc1` (a host-absolute link breaks
inside the guest).

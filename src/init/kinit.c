/*
 * kinit - tiny PID 1 for clawrza-glibc-selfhost.
 *
 * Design (independent implementation, inspired by the S.A.N.E ninit pattern):
 *   - refuses to run unless getpid() == 1
 *   - mounts proc/sysfs/devtmpfs/tmpfs idempotently
 *   - spawns a boot selftest once, and an interactive shell with respawn
 *   - reaps children non-blockingly with waitpid(WNOHANG) + pause()
 *   - SIGTERM/SIGINT trigger a clean reboot(RB_AUTOBOOT)
 *
 * Build: gcc -O2 -Wall -o kinit kinit.c
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile sig_atomic_t want_shutdown;
static pid_t shell_pid;

static void on_signal(int sig) {
    if (sig == SIGTERM || sig == SIGINT) want_shutdown = sig;
}

static void on_sigchld(int sig) { (void)sig; }

static void ensure_dir(const char *p) { mkdir(p, 0755); }

static void try_mount(const char *src, const char *tgt, const char *type,
                      unsigned long flags) {
    ensure_dir(tgt);
    if (mount(src, tgt, type, flags, NULL) < 0 && errno != EBUSY)
        fprintf(stderr, "kinit: mount %s -> %s: %s\n", src, tgt, strerror(errno));
}

static void setup_fs(void) {
    umask(022);
    try_mount("proc", "/proc", "proc", 0);
    try_mount("sysfs", "/sys", "sysfs", 0);
    try_mount("devtmpfs", "/dev", "devtmpfs", 0);
    try_mount("tmpfs", "/run", "tmpfs", 0);
    ensure_dir("/tmp");
    chmod("/tmp", 01777);
}

static pid_t spawn(const char *path, char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        setsid();
        int fd = open("/dev/console", O_RDWR);
        if (fd < 0) fd = open("/dev/null", O_RDWR);
        if (fd >= 0) {
            dup2(fd, 0); dup2(fd, 1); dup2(fd, 2);
            if (fd > 2) close(fd);
        }
        signal(SIGCHLD, SIG_DFL);
        signal(SIGTERM, SIG_DFL);
        signal(SIGINT, SIG_DFL);
        execv(path, argv);
        fprintf(stderr, "kinit: exec %s failed: %s\n", path, strerror(errno));
        _exit(127);
    }
    return pid;
}

static pid_t spawn_shell(void) {
    char *argv[] = { "sh", "-i", NULL };
    return spawn("/bin/sh", argv);
}

static void spawn_selftest(void) {
    char *argv[] = { "selftest", NULL };
    pid_t p = spawn("/usr/bin/selftest", argv);
    fprintf(stderr, "kinit: selftest spawned (pid %d)\n", p);
}

int main(void) {
    if (getpid() != 1) {
        fprintf(stderr, "kinit: refusing to run as PID %d (need 1)\n", getpid());
        return 1;
    }

    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    signal(SIGCHLD, on_sigchld);
    signal(SIGHUP, SIG_IGN);

    setup_fs();
    sethostname("clawrza", 7);

    /* this sysroot has no ld.so.cache: point the loader at all lib dirs */
    setenv("LD_LIBRARY_PATH", "/lib64:/lib:/usr/lib", 1);
    setenv("GCC_EXEC_PREFIX", "/usr/lib/gcc/", 1);

    printf("\n=== kinit start (PID 1) v0.1 ===\n");
    printf("kinit: hostname=clawrza\n");
    printf("kinit: mounting filesystems done\n");
    fflush(stdout);

    spawn_selftest();
    shell_pid = spawn_shell();
    printf("kinit: main loop ready (shell pid %d)\n", shell_pid);
    fflush(stdout);

    for (;;) {
        int st;
        pid_t p = waitpid(-1, &st, WNOHANG);
        if (p > 0) {
            if (p == shell_pid) {
                fprintf(stderr, "kinit: shell exited, respawning\n");
                shell_pid = spawn_shell();
            }
            continue;
        }
        if (want_shutdown) {
            fprintf(stderr, "kinit: shutdown requested, rebooting\n");
            sync();
            reboot(RB_AUTOBOOT);
            for (;;) pause();
        }
        if (p < 0 && errno == ECHILD) {
            /* no children left (should not happen) */
            shell_pid = spawn_shell();
        }
        pause();
    }
    return 0;
}

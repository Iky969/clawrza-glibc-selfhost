/*
 * kinit - tiny PID 1 for clawrza-glibc-selfhost.
 *
 *   - refuses to run unless getpid() == 1
 *   - mounts proc/sysfs/devtmpfs/tmpfs
 *   - exports guest loader/toolchain environment before forking
 *   - reads /etc/init.conf:  name:(once|respawn):command
 *   - reaps with waitpid(WNOHANG) and respawns with a 2s guard
 *   - SIGTERM/SIGINT -> sync() + reboot(RB_AUTOBOOT)
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MAX_SVC 16
#define CMD_LEN 256
#define RESPAWN_GUARD 2

struct service {
    char name[32];
    char cmd[CMD_LEN];
    int respawn;
    pid_t pid;
    time_t last_start;
    time_t retry_at;
};

static struct service svcs[MAX_SVC];
static int nsvcs;
static volatile sig_atomic_t want_shutdown;

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

static char *trim(char *s) {
    while (*s == ' ' || *s == '\t') s++;
    char *e = s + strlen(s);
    while (e > s && (e[-1] == ' ' || e[-1] == '\t' ||
                     e[-1] == '\n' || e[-1] == '\r')) *--e = 0;
    return s;
}

static int add_service(const char *name, const char *mode, const char *cmd) {
    if (nsvcs >= MAX_SVC || !*name || !*cmd) return -1;
    snprintf(svcs[nsvcs].name, sizeof(svcs[nsvcs].name), "%s", name);
    snprintf(svcs[nsvcs].cmd, sizeof(svcs[nsvcs].cmd), "%s", cmd);
    svcs[nsvcs].respawn = (strcmp(mode, "respawn") == 0);
    svcs[nsvcs].pid = 0;
    svcs[nsvcs].last_start = 0;
    svcs[nsvcs].retry_at = 0;
    nsvcs++;
    return 0;
}

/* Format:  name:(once|respawn):command   -- '#' starts a comment */
static int parse_init_conf(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    char line[512];
    while (fgets(line, sizeof(line), f)) {
        char *comment = strchr(line, '#');
        if (comment) *comment = 0;
        char *a = strchr(line, ':');
        if (!a) continue;
        *a++ = 0;
        char *b = strchr(a, ':');
        if (!b) continue;
        *b++ = 0;
        add_service(trim(line), trim(a), trim(b));
    }
    fclose(f);
    return nsvcs > 0 ? 0 : -1;
}

static pid_t spawn_service(const char *cmd) {
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
        execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
        _exit(127);
    }
    return pid;
}

static void start_service(struct service *s) {
    s->pid = spawn_service(s->cmd);
    s->last_start = time(NULL);
    s->retry_at = 0;
    fprintf(stderr, "kinit: started %s (pid %d)\n", s->name, s->pid);
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

    /* no ld.so.cache and gcc's build-time -iprefix is relative to CWD */
    setenv("LD_LIBRARY_PATH", "/lib64:/lib:/usr/lib", 1);
    setenv("GCC_EXEC_PREFIX", "/usr/lib/gcc/", 1);

    printf("\n=== kinit start (PID 1) v0.2 ===\n");
    printf("kinit: hostname=clawrza\n");

    if (parse_init_conf("/etc/init.conf") < 0) {
        fprintf(stderr, "kinit: /etc/init.conf missing, using defaults\n");
        add_service("selftest", "once", "/usr/bin/selftest");
        add_service("console", "respawn", "/bin/sh -i");
    }
    for (int i = 0; i < nsvcs; i++) start_service(&svcs[i]);
    printf("kinit: %d services started, entering main loop\n", nsvcs);
    fflush(stdout);

    for (;;) {
        int st;
        time_t now = time(NULL);
        pid_t p = waitpid(-1, &st, WNOHANG);

        if (p > 0) {
            for (int i = 0; i < nsvcs; i++) {
                if (svcs[i].pid != p) continue;
                svcs[i].pid = 0;
                if (svcs[i].respawn) {
                    now = time(NULL);
                    if (now - svcs[i].last_start >= RESPAWN_GUARD) {
                        svcs[i].retry_at = 0;
                        start_service(&svcs[i]);
                    } else {
                        svcs[i].retry_at = now;
                        fprintf(stderr, "kinit: %s crashed too fast, delaying respawn\n",
                                svcs[i].name);
                    }
                }
            }
            continue;
        }

        if (want_shutdown) {
            fprintf(stderr, "kinit: shutdown requested, rebooting\n");
            sync();
            reboot(RB_AUTOBOOT);
            for (;;) pause();
        }

        /* delayed respawn after a crash-loop guard */
        now = time(NULL);
        for (int i = 0; i < nsvcs; i++) {
            if (svcs[i].pid == 0 && svcs[i].respawn && svcs[i].retry_at &&
                now >= svcs[i].retry_at + RESPAWN_GUARD) {
                start_service(&svcs[i]);
            }
        }

        /* bounded wait so delayed respawns still fire */
        int timeout = -1;
        now = time(NULL);
        for (int i = 0; i < nsvcs; i++) {
            if (svcs[i].pid == 0 && svcs[i].respawn && svcs[i].retry_at) {
                long left = svcs[i].retry_at + RESPAWN_GUARD - now;
                int ms = left > 0 ? (int)(left * 1000) : 0;
                if (timeout < 0 || ms < timeout) timeout = ms;
            }
        }
        poll(NULL, 0, timeout);
    }
    return 0;
}

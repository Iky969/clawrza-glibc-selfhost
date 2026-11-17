#!/bin/sh
# Boot-time selftest, executed by kinit (PID 1) on the serial console.
echo
echo "=== SELFTEST: start ==="
echo "SELFTEST: uname -> $(uname -a)"
echo "SELFTEST: PID1_CMD=$(tr '\0' ' ' < /proc/1/cmdline)"
echo "SELFTEST: ps output:"
ps | head -8

# wait for the udhcpc service started from /etc/init.conf
n=0
while ! ip addr show eth0 2>/dev/null | grep -q 'inet ' && [ "$n" -lt 20 ]; do
    sleep 0.5
    n=$((n + 1))
done
echo "SELFTEST: network -> $(ip addr show eth0 2>/dev/null | grep 'inet ' | head -1)"
if ping -c 2 -W 2 10.0.2.2 >/dev/null 2>&1; then
    echo "SELFTEST: outbound ping OK"
else
    echo "SELFTEST: outbound ping FAILED"
fi

echo "SELFTEST: gcc version -> $(gcc --version | head -1)"
mkdir -p /tmp/selfhost-test
cat > /tmp/selfhost-test/hello.c <<'EOF'
#include <stdio.h>
#include <string.h>
int main(void) {
    char buf[64];
    strcpy(buf, "SELFHOST_OK");
    printf("%s: compiled inside guest\n", buf);
    return 0;
}
EOF
cd /tmp/selfhost-test
if gcc -O2 -Wall -o hello hello.c && ./hello; then
    echo "SELFTEST: gcc compile OK"
else
    echo "SELFTEST: gcc compile FAILED"
fi

cat > Makefile <<'EOF'
all: hello
hello: hello.c
	gcc -O2 -Wall -o hello hello.c
clean:
	rm -f hello
EOF
make clean >/dev/null 2>&1 || true
if make; then
    echo "SELFTEST: make build OK"
else
    echo "SELFTEST: make build FAILED"
fi

if spkg init >/dev/null 2>&1; then :; fi
if spkg build hello; then
    echo "SELFTEST: spkg build OK"
else
    echo "SELFTEST: spkg build FAILED"
fi

# --- prove self-hosting of the distro's own init and package manager -------
echo "SELFTEST: rebuilding kinit + spkg from source INSIDE guest"
cd /usr/src/clawrza
make clean >/dev/null 2>&1 || true
if make; then
    echo "SELFTEST: in-guest make rebuild OK"
else
    echo "SELFTEST: in-guest make rebuild FAILED"
fi
echo "SELFTEST: rebuilt kinit sha256 -> $(sha256sum kinit | cut -d' ' -f1)"
echo "SELFTEST: installed kinit sha256 -> $(sha256sum /sbin/init | cut -d' ' -f1)"
echo "SELFTEST: rebuilt kinit refuses non-PID1 -> $(./kinit 2>&1 | head -1)"
if ./spkg list >/dev/null 2>&1; then
    echo "SELFTEST: rebuilt spkg source runs OK"
else
    echo "SELFTEST: rebuilt spkg source FAILED"
fi

echo "SELFTEST: installed packages:"
spkg list || true

echo "=== SELFTEST: done ==="

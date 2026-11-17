#!/bin/sh
# Boot-time selftest, executed by kinit (PID 1) on the serial console.
echo
echo "=== SELFTEST: start ==="
echo "SELFTEST: uname -> $(uname -a)"
echo "SELFTEST: PID1_CMD=$(tr '\0' ' ' < /proc/1/cmdline)"
echo "SELFTEST: ps output:"
ps | head -8

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
echo "SELFTEST: installed packages:"
spkg list || true

echo "=== SELFTEST: done ==="

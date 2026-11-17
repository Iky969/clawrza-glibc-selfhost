#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/env.sh"

IMG="$DISTRO/clawrza.img"
LOG="$DISTRO/qemu-console.log"
[ -f "$IMG" ] || die "image missing; run 'sudo make image' first"

rm -f "$LOG"
log "booting headless QEMU (timeout 40s)"
timeout 40s qemu-system-x86_64 \
    -drive "file=$IMG,format=raw,if=virtio" \
    -m 512M -smp "$JOBS" \
    -nographic -serial "file:$LOG" \
    -display none -no-reboot -no-shutdown \
    -monitor none 2>"$DISTRO/qemu-stderr.log" &
QPID=$!

for i in $(seq 1 180); do
    grep -q 'SELFTEST: done' "$LOG" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.2
done
sleep 1
kill "$QPID" 2>/dev/null || true
wait "$QPID" 2>/dev/null || true

echo
echo "================ console ================"
cat "$LOG" 2>/dev/null | tail -60
echo "========================================="

fail=0
check() {
    if grep -q "$2" "$LOG" 2>/dev/null; then
        echo "[PASS] $1"
    else
        echo "[FAIL] $1 (missing: $2)"
        fail=1
    fi
}

check "kernel booted"            "Linux version"
check "kinit is PID 1"           "kinit start (PID 1)"
check "uname -a reported"        "SELFTEST: uname"
check "ps shows PID 1"           "SELFTEST: PID1_CMD"
check "gcc compiled C in guest"  "SELFHOST_OK"
check "make build"               "SELFTEST: make build OK"
check "spkg built from source"   "SELFTEST: spkg build OK"
check "selftest completed"       "SELFTEST: done"
check "kinit rebuilt in guest"   "SELFTEST: in-guest make rebuild OK"
check "spkg source runnable"     "SELFTEST: rebuilt spkg source runs OK"
check "DHCP address on eth0"     "SELFTEST: network ->"
check "outbound connectivity"    "SELFTEST: outbound ping OK"

if grep -qi 'Kernel panic\|Attempted to kill init' "$LOG" 2>/dev/null; then
    echo "[FAIL] kernel panic detected"
    fail=1
fi

[ "$fail" -eq 0 ] || { echo "BOOT TEST FAILED" >&2; exit 1; }
log "BOOT TEST PASSED"

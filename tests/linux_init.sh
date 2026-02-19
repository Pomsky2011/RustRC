#!/usr/bin/env bash
# Test: RustRC boots as PID 1 under a Linux kernel via initramfs.
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "=== linux: PID 1 boot ==="

need_cmd qemu-system-x86_64              || { summary; exit; }
need_cmd bsdtar "install libarchive"     || { summary; exit; }
need_file /boot/vmlinuz-linux "install linux" || { summary; exit; }

build_static

INITRD=$(mktemp /tmp/rustrc-linux-XXXXXX.img)
trap 'rm -f "$INITRD"' EXIT
make_initramfs "$BINARY" "$INITRD"

info "Booting in QEMU…"
if linux_qemu_boot /boot/vmlinuz-linux "$INITRD" "Hello, world!"; then
    pass "RustRC ran as Linux PID 1 and printed expected output"
else
    fail "expected 'Hello, world!' not found in QEMU output"
fi

summary

#!/usr/bin/env bash
# Test: RustRC boots from a GRUB-built hybrid ISO (BIOS + UEFI).
# QEMU boots the ISO from CD with no -kernel shortcut, mirroring real hardware.
# The resulting ISO at tests/.cache/rustrc-bare-metal.iso can be flashed to USB.
set -euo pipefail
source "$(dirname "$0")/common.sh"

ISO="$CACHE_DIR/rustrc-bare-metal.iso"

echo "=== bare metal: GRUB ISO boot ==="

need_cmd qemu-system-x86_64              || { summary; exit; }
need_cmd bsdtar    "install libarchive"  || { summary; exit; }
need_cmd grub-mkrescue "install grub"    || { summary; exit; }
need_cmd xorriso   "install xorriso"     || { summary; exit; }
need_file /boot/vmlinuz-linux "install linux" || { summary; exit; }

build_static

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Build initramfs
INITRD="$WORK/initramfs.img"
make_initramfs "$BINARY" "$INITRD"

# Assemble the ISO tree
mkdir -p "$WORK/iso/boot/grub"
cp /boot/vmlinuz-linux "$WORK/iso/boot/vmlinuz"
cp "$INITRD"           "$WORK/iso/boot/initramfs.img"

cat > "$WORK/iso/boot/grub/grub.cfg" << 'GRUBCFG'
set timeout=0
set default=0

# Route console to serial so QEMU -nographic can capture output.
serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
terminal_input  serial
terminal_output serial

menuentry "RustRC" {
    linux  /boot/vmlinuz console=ttyS0 quiet
    initrd /boot/initramfs.img
}
GRUBCFG

info "Building GRUB hybrid ISO (BIOS + UEFI)…"
grub-mkrescue -o "$ISO" "$WORK/iso" 2>/dev/null
info "ISO: $ISO  ($(du -sh "$ISO" | cut -f1))"
info "  Flash to USB: sudo dd if=$ISO of=/dev/sdX bs=4M status=progress"

info "Booting ISO in QEMU via BIOS CD (no -kernel flag)…"
if iso_qemu_boot "$ISO" "Hello, world!"; then
    pass "RustRC booted via GRUB from ISO and printed expected output"
else
    fail "expected 'Hello, world!' not found when booting from ISO"
fi

summary

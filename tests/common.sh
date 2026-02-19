#!/usr/bin/env bash
# Shared utilities for RustRC integration tests.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$REPO_ROOT/tests/.cache"
TIMEOUT=30

# Non-interactive bash doesn't source ~/.bashrc, so ~/.cargo/bin is absent.
export PATH="$HOME/.cargo/bin:$PATH"

mkdir -p "$CACHE_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
_PASS=0; _FAIL=0; _SKIP=0

pass() { echo -e "${GREEN}[PASS]${NC} $*"; _PASS=$((_PASS + 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $*"; _FAIL=$((_FAIL + 1)); }
skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; _SKIP=$((_SKIP + 1)); }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }

# Skip and return 1 if a command is missing.
need_cmd() {
    command -v "$1" &>/dev/null && return 0
    skip "command not found: $1${2:+ — $2}"; return 1
}

# Skip and return 1 if a file is missing.
need_file() {
    [[ -f "$1" ]] && return 0
    skip "file not found: $1${2:+ — $2}"; return 1
}

# Skip and return 1 if a rustup target is not installed.
need_target() {
    rustup target list --installed 2>/dev/null | grep -q "^$1$" && return 0
    skip "rustup target not installed: $1 — run: rustup target add $1"; return 1
}

# Build RustRC for the host with a statically linked CRT.
# Sets BINARY to the resulting path.
build_static() {
    info "Building (host, static CRT)…"
    RUSTFLAGS="-C target-feature=+crt-static" \
        cargo build --release --manifest-path "$REPO_ROOT/Cargo.toml" 2>&1
    BINARY="$REPO_ROOT/target/release/RustRC"
}

# Cross-compile RustRC for target $1.
# Tries cargo-zigbuild first, then ld.lld.
# Sets BINARY on success; calls skip and returns 1 on failure.
#
# NOTE: bash suppresses set -e for every command inside a function body when
# the function is called as an `if` condition. We therefore capture cargo's
# exit status explicitly with `|| st=$?` instead of relying on set -e.
build_cross() {
    local target="$1"
    local env_var="CARGO_TARGET_$(echo "$target" | tr '[:lower:]-' '[:upper:]_')_LINKER"
    local st=0
    info "Cross-compiling for $target…"
    if command -v cargo-zigbuild &>/dev/null; then
        # BSD libc requires dynamic linking through zig's sysroot; +crt-static
        # is incompatible here and causes a hard error from the linker.
        cargo zigbuild --release --target "$target" \
            --manifest-path "$REPO_ROOT/Cargo.toml" 2>&1 || st=$?
    elif command -v ld.lld &>/dev/null; then
        RUSTFLAGS="-C target-feature=+crt-static" \
            env "$env_var=ld.lld" \
            cargo build --release --target "$target" \
            --manifest-path "$REPO_ROOT/Cargo.toml" 2>&1 || st=$?
    else
        skip "no cross-linker available (install cargo-zigbuild+zig, or lld)"; return 1
    fi
    if [[ $st -ne 0 ]]; then
        skip "cross-compilation failed — no BSD sysroot available; install cargo-zigbuild+zig"
        return 1
    fi
    BINARY="$REPO_ROOT/target/$target/release/RustRC"
}

# Pack binary $1 into a Linux cpio initramfs at path $2.
make_initramfs() {
    local bin="$1" out="$2"
    local tmp; tmp=$(mktemp -d)
    cp "$bin" "$tmp/init" && chmod +x "$tmp/init"
    (cd "$tmp" && bsdtar -c -f "$out" --format newc .) 2>/dev/null
    rm -rf "$tmp"
}

# Boot kernel + initramfs in QEMU; return 0 iff $3 appears in output.
# Output is captured to a variable first — piping grep directly would cause
# QEMU to receive SIGPIPE when grep exits early, making pipefail report failure
# even when the expected string was found.
linux_qemu_boot() {
    local kernel="$1" initrd="$2" want="$3" out
    out=$(timeout "$TIMEOUT" qemu-system-x86_64 \
        -kernel "$kernel" -initrd "$initrd" \
        -append "console=ttyS0 quiet" \
        -nographic -m 256M -no-reboot 2>&1) || true
    grep -qF "$want" <<< "$out"
}

# Boot a GRUB ISO via BIOS CD; return 0 iff $2 appears in output.
iso_qemu_boot() {
    local iso="$1" want="$2" out
    out=$(timeout 60 qemu-system-x86_64 \
        -cdrom "$iso" -boot d \
        -nographic -m 256M -no-reboot 2>&1) || true
    grep -qF "$want" <<< "$out"
}

# Boot a qcow2 BSD disk image; return 0 iff $2 appears in output.
bsd_qemu_boot() {
    local image="$1" want="$2" out
    out=$(timeout 120 qemu-system-x86_64 \
        -drive "file=$image,format=qcow2,if=virtio" \
        -machine q35 -nographic -m 512M -no-reboot 2>&1) || true
    grep -qF "$want" <<< "$out"
}

# Inject local file $2 into qcow2 image $1 at guest path $3.
# Uses guestfish to auto-detect the root partition.
inject_init() {
    local image="$1" local_file="$2" guest_path="$3"
    local root_dev
    root_dev=$(guestfish -a "$image" --ro run : inspect-os 2>/dev/null | head -1)
    if [[ -z "$root_dev" ]]; then
        echo "guestfish: could not detect root filesystem in $image"; return 1
    fi
    guestfish -a "$image" \
        run : \
        mount "$root_dev" / : \
        upload "$local_file" "$guest_path" : \
        chmod 0555 "$guest_path" : \
        umount / 2>&1
}

# Print a per-script summary and exit 1 if any test failed.
summary() {
    echo
    echo -e "  ${GREEN}passed${NC} $_PASS  ${RED}failed${NC} $_FAIL  ${YELLOW}skipped${NC} $_SKIP"
    [[ $_FAIL -eq 0 ]]
}

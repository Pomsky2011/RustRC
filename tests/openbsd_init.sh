#!/usr/bin/env bash
# Test: RustRC cross-compiles for OpenBSD and runs as PID 1.
# x86_64-unknown-openbsd is a Rust Tier 3 target — no prebuilt std.
# Requires cargo-zigbuild+zig OR a nightly toolchain with -Zbuild-std.
set -euo pipefail
source "$(dirname "$0")/common.sh"

TARGET="x86_64-unknown-openbsd"
IMAGE="$CACHE_DIR/openbsd.qcow2"

echo "=== openbsd: cross-compile + PID 1 boot ==="

need_cmd cargo || { summary; exit; }

# --- Phase 1 + 2: compile and build (combined — Tier 3 needs special tooling) ---
# cargo check alone cannot run for Tier 3 without build-std or zigbuild,
# so we go straight to a full build attempt.

if command -v cargo-zigbuild &>/dev/null; then
    info "Building $TARGET via cargo-zigbuild…"
    # BSD libc requires dynamic linking through zig's sysroot; no +crt-static.
    # Capture exit status explicitly — "unsupported target" should be a skip.
    st=0
    cargo zigbuild --release --target "$TARGET" \
        --manifest-path "$REPO_ROOT/Cargo.toml" 2>&1 || st=$?
    if [[ $st -eq 0 ]]; then
        pass "Cross-compilation for OpenBSD (x86_64) succeeded (zigbuild)"
        BINARY="$REPO_ROOT/target/$TARGET/release/RustRC"
    else
        skip "cargo-zigbuild does not support $TARGET with this zig version"
        summary; exit 0
    fi
elif rustup toolchain list 2>/dev/null | grep -q nightly; then
    info "Building $TARGET via nightly -Zbuild-std…"
    st=0
    cargo +nightly build -Zbuild-std \
        --release --target "$TARGET" \
        --manifest-path "$REPO_ROOT/Cargo.toml" 2>&1 || st=$?
    if [[ $st -eq 0 ]]; then
        pass "Cross-compilation for OpenBSD (x86_64) succeeded (nightly)"
        BINARY="$REPO_ROOT/target/$TARGET/release/RustRC"
    else
        fail "nightly -Zbuild-std build for $TARGET failed"
        summary; exit 1
    fi
else
    skip "$TARGET is Tier 3 — install cargo-zigbuild+zig or a nightly toolchain"
    skip "  see tests/DEPENDENCIES.txt"
    summary; exit 0
fi

# --- Phase 3: boot test ---
need_cmd qemu-system-x86_64 || { summary; exit; }

if [[ ! -f "$IMAGE" ]]; then
    skip "OpenBSD disk image not found at $IMAGE — see tests/DEPENDENCIES.txt"
    summary; exit 0
fi

need_cmd guestfish "install libguestfs" || { summary; exit; }

info "Injecting binary into OpenBSD image (working copy)…"
MODIFIED=$(mktemp /tmp/openbsd-XXXXXX.qcow2)
trap 'rm -f "$MODIFIED"' EXIT
cp "$IMAGE" "$MODIFIED"

if ! inject_init "$MODIFIED" "$BINARY" /sbin/init; then
    fail "Failed to inject binary into OpenBSD disk image"
    summary; exit 1
fi

info "Booting OpenBSD in QEMU…"
if bsd_qemu_boot "$MODIFIED" "Hello, world!"; then
    pass "RustRC ran as OpenBSD PID 1 and printed expected output"
else
    fail "expected 'Hello, world!' not found in OpenBSD boot output"
fi

summary

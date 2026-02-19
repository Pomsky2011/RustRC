#!/usr/bin/env bash
# Test: RustRC cross-compiles for FreeBSD and runs as PID 1.
# x86_64-unknown-freebsd is a Rust Tier 2 target.
set -euo pipefail
source "$(dirname "$0")/common.sh"

TARGET="x86_64-unknown-freebsd"
IMAGE="$CACHE_DIR/freebsd.qcow2"

echo "=== freebsd: cross-compile + PID 1 boot ==="

need_cmd cargo || { summary; exit; }

# --- Phase 1: compile check (no linker required) ---
need_target "$TARGET" || { summary; exit; }

info "Checking $TARGET compilation…"
if cargo check --target "$TARGET" \
        --manifest-path "$REPO_ROOT/Cargo.toml" 2>&1; then
    pass "cargo check for $TARGET succeeded"
else
    fail "cargo check for $TARGET failed"
    summary; exit 1
fi

# --- Phase 2: full cross-compile ---
if build_cross "$TARGET"; then
    pass "Cross-compilation for FreeBSD (x86_64) succeeded"
else
    # build_cross already called skip()
    summary; exit 0
fi

# --- Phase 3: boot test ---
need_cmd qemu-system-x86_64 || { summary; exit; }

if [[ ! -f "$IMAGE" ]]; then
    skip "FreeBSD disk image not found at $IMAGE — see tests/DEPENDENCIES.txt"
    summary; exit 0
fi

need_cmd guestfish "install libguestfs" || { summary; exit; }

info "Injecting binary into FreeBSD image (working copy)…"
MODIFIED=$(mktemp /tmp/freebsd-XXXXXX.qcow2)
trap 'rm -f "$MODIFIED"' EXIT
cp "$IMAGE" "$MODIFIED"

if ! inject_init "$MODIFIED" "$BINARY" /sbin/init; then
    fail "Failed to inject binary into FreeBSD disk image"
    summary; exit 1
fi

info "Booting FreeBSD in QEMU…"
if bsd_qemu_boot "$MODIFIED" "Hello, world!"; then
    pass "RustRC ran as FreeBSD PID 1 and printed expected output"
else
    fail "expected 'Hello, world!' not found in FreeBSD boot output"
fi

summary

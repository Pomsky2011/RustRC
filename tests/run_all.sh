#!/usr/bin/env bash
# Run all RustRC integration tests and report overall results.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

SCRIPTS=(
    linux_init.sh
    freebsd_init.sh
    openbsd_init.sh
    netbsd_init.sh
    bare_metal.sh
)

overall_pass=0
overall_fail=0

for script in "${SCRIPTS[@]}"; do
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if bash "$TESTS_DIR/$script"; then
        overall_pass=$((overall_pass + 1))
    else
        overall_fail=$((overall_fail + 1))
    fi
done

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Overall: ${GREEN}${overall_pass} passed${NC}  ${RED}${overall_fail} failed${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[[ $overall_fail -eq 0 ]]

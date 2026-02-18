# Rust Check

Run a full suite of Rust checks: format, clippy, build, and test.

## Steps
1. Run `cargo fmt --check` to verify formatting
2. Run `cargo clippy -- -D warnings` to catch lint issues
3. Run `cargo build` to verify compilation
4. Run `cargo test` to run the test suite
5. Report results for each step, continuing even if earlier steps fail

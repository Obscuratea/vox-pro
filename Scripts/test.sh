#!/usr/bin/env bash
# Every automated test, in the same order CI runs them (.github/workflows/tests.yml).
# Usage: Scripts/test.sh        Exits non-zero if anything fails. See TESTING.md.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=$(grep -m1 '^name' Cargo.toml | cut -d'"' -f2)

# Build for any x86-64 CPU (no AVX-512), the same as the released package.
export CFLAGS="-O2 -march=x86-64 -mtune=generic" CXXFLAGS="-O2 -march=x86-64 -mtune=generic"
export RUSTFLAGS="-C target-cpu=x86-64"

echo "== 1/3 Unit tests (engine, DSP, EQ, settings, updater)"
cargo test --release --locked

echo "== 2/3 UI tests (QML, no screen needed)"
QT_QPA_PLATFORM=offscreen "${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}" -input tests/qml

echo "== 3/3 Runs on any x86-64 CPU (no AVX-512 instructions in the binary)"
cargo build --release --locked
N=$(objdump -d "target/release/$APP" | grep -cE '%zmm[0-9]+|%k[1-7]\b' || true)
if [ "$N" -ne 0 ]; then echo "FAIL: $N AVX-512 instructions found; the app would crash on CPUs without AVX-512"; exit 1; fi
echo "ok: no AVX-512 instructions"

echo
echo "All tests passed."

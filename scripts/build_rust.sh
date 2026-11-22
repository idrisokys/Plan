#!/bin/bash
# Rust çekirdeğini (rust/plan_core) Apple Silicon için derler: libplan_core.a
# Swift derlemesinden (swift build / swift test / build.sh) ÖNCE çalışmalıdır. Rust: https://rustup.rs
set -euo pipefail
cd "$(dirname "$0")/../rust/plan_core"

if ! command -v cargo >/dev/null 2>&1; then
  echo "HATA: cargo bulunamadı. Rust'ı kur: https://rustup.rs" >&2
  exit 1
fi
rustup target add aarch64-apple-darwin >/dev/null 2>&1 || true

export MACOSX_DEPLOYMENT_TARGET=14.6
cargo build --release --target aarch64-apple-darwin
echo "Rust çekirdeği hazır: $(pwd)/target/aarch64-apple-darwin/release/libplan_core.a"

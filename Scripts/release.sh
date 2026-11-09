#!/usr/bin/env bash
# Build the package for a release and write its checksum into release/. It does NOT publish anything:
# at the end it prints the gh command to run when you are ready.
# Usage: Scripts/release.sh   (after bumping version in Cargo.toml and pkgver in packaging/PKGBUILD)
set -euo pipefail
cd "$(dirname "$0")/.."
VER=$(grep -m1 '^version' Cargo.toml | cut -d'"' -f2)
PKGVER=$(grep -m1 '^pkgver=' packaging/PKGBUILD | cut -d= -f2)
[ "$VER" = "$PKGVER" ] || { echo "Cargo.toml says $VER but PKGBUILD says $PKGVER"; exit 1; }
python3 Scripts/gen_third_party.py . "Vox Pro" --pro
cargo test --release
(cd packaging && makepkg -f --noconfirm)
mkdir -p release && rm -f release/*
PKG=$(ls -t packaging/*.pkg.tar.zst | head -1)
cp "$PKG" release/
(cd release && sha256sum "$(basename "$PKG")" > "$(basename "$PKG").sha256")
echo
echo "Ready in release/. When you want to publish (this posts to GitHub):"
echo "  gh release create v$VER release/* --repo Obscuratea/vox-pro --title \"Vox Pro $VER\" --notes-file NOTES.md"

#!/usr/bin/env bash
# Build the AppImage: one file that runs on most current Linux systems (see README, Requirements).
#
# It must be built on an older system than Arch, or it would need a newer glibc than Ubuntu, Mint or
# Fedora have, so it runs inside Ubuntu 24.04:
#   on this computer:  Scripts/appimage.sh --container     (needs podman; output in release/)
#   on GitHub:         .github/workflows/appimage.yml runs it in an ubuntu:24.04 container
#
# Inside: Qt (the official 6.12 build), SoundTouch and the other libraries come along in the file.
# PipeWire does not: it has to be the system's own, so it can talk to the system's sound server.
# KWindowSystem is left out (Ubuntu 24.04 has no KF6), so the Glass themes have no KWin blur here.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=$PWD
APP=$(grep -m1 '^name' Cargo.toml | cut -d'"' -f2)
VER=$(grep -m1 '^version' Cargo.toml | cut -d'"' -f2)
QT_VERSION=6.12.1

if [ "${1:-}" = "--container" ]; then
    mkdir -p "$HOME/.cache/vox-appimage" release
    exec podman run --rm --network host \
        -v "$SRC:/src:Z" -v "$HOME/.cache/vox-appimage:/cache:Z" -w /src \
        docker.io/library/ubuntu:24.04 Scripts/appimage.sh
fi

CACHE=${CACHE:-/cache}
mkdir -p "$CACHE"
export DEBIAN_FRONTEND=noninteractive

echo "== Build tools and libraries"
EXTRA=""
grep -q "lilv" packaging/PKGBUILD && EXTRA="liblilv-dev"
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    build-essential clang libclang-dev cmake pkg-config git curl ca-certificates file patchelf \
    python3-venv desktop-file-utils squashfs-tools librsvg2-bin \
    libpipewire-0.3-dev libsoundtouch-dev $EXTRA \
    libgl-dev libegl-dev libxkbcommon-dev libxkbcommon-x11-0 libfontconfig1-dev libfreetype-dev \
    libdbus-1-3 libwayland-client0 libwayland-cursor0 libwayland-egl1 \
    libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 \
    libxcb-shape0 libxcb-xinerama0 libxcb-xkb1 libx11-xcb1 >/dev/null

echo "== Rust"
export RUSTUP_HOME=$CACHE/rustup CARGO_HOME=$CACHE/cargo
[ -x "$CARGO_HOME/bin/cargo" ] || curl -sSf https://sh.rustup.rs | sh -s -- -y -q --profile minimal
export PATH=$CARGO_HOME/bin:$PATH
rustup -q update stable >/dev/null 2>&1 || true

echo "== Qt $QT_VERSION"
QT=$CACHE/qt/$QT_VERSION/gcc_64
if [ ! -x "$QT/bin/qmake" ]; then
    [ -d "$CACHE/venv" ] || python3 -m venv "$CACHE/venv"
    "$CACHE/venv/bin/pip" -q install aqtinstall
    "$CACHE/venv/bin/aqt" install-qt linux desktop "$QT_VERSION" linux_gcc_64 -O "$CACHE/qt" >/dev/null
fi
export QMAKE=$QT/bin/qmake PKG_CONFIG_PATH=$QT/lib/pkgconfig LD_LIBRARY_PATH=$QT/lib CMAKE_PREFIX_PATH=$QT

echo "== Build $APP $VER"
export CARGO_TARGET_DIR=$CACHE/target-$APP VOX_NO_KWINDOWSYSTEM=1
export CFLAGS="-O2 -march=x86-64 -mtune=generic" CXXFLAGS="-O2 -march=x86-64 -mtune=generic"
export RUSTFLAGS="-C target-cpu=x86-64"
cargo build --release --locked

echo "== AppDir"
APPDIR=$CACHE/AppDir-$APP
rm -rf "$APPDIR"
install -Dm755 "$CARGO_TARGET_DIR/release/$APP" "$APPDIR/usr/bin/$APP"
install -Dm644 "packaging/$APP.desktop" "$APPDIR/usr/share/applications/$APP.desktop"
install -Dm644 "packaging/$APP.svg" "$APPDIR/usr/share/icons/hicolor/scalable/apps/$APP.svg"
# The AppImage's own icon (.DirIcon) has to be a PNG.
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
rsvg-convert -w 256 -h 256 "packaging/$APP.svg" -o "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APP.png"
install -Dm644 LICENSE "$APPDIR/usr/share/licenses/$APP/LICENSE"
install -Dm644 THIRD_PARTY.txt "$APPDIR/usr/share/licenses/$APP/THIRD_PARTY.txt"

TOOLS=$CACHE/tools
mkdir -p "$TOOLS"
get() { [ -x "$TOOLS/$1" ] || { curl -sSfL -o "$TOOLS/$1" "$2"; chmod +x "$TOOLS/$1"; }; }
get linuxdeploy https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
get linuxdeploy-plugin-qt https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage
get appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
export PATH=$TOOLS:$PATH APPIMAGE_EXTRACT_AND_RUN=1

echo "== Bundle libraries (everything but PipeWire and the base system)"
export QML_SOURCES_PATHS=$SRC/qml EXTRA_PLATFORM_PLUGINS="libqwayland.so;libqoffscreen.so"   # offscreen: for Scripts/test_appimage.sh
linuxdeploy --appdir "$APPDIR" --plugin qt \
    --exclude-library 'libpipewire-0.3.so*' \
    --desktop-file "$APPDIR/usr/share/applications/$APP.desktop" \
    --icon-file "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APP.png" \
    --icon-file "$APPDIR/usr/share/icons/hicolor/scalable/apps/$APP.svg" >/dev/null
# Two Qt plugins the Qt plugin above does not pick up: drawing with the GPU on Wayland, and SVG icons
# (the tray icon).
for plugin in wayland-graphics-integration-client/libqt-plugin-wayland-egl.so iconengines/libqsvgicon.so; do
    install -Dm755 "$QT/plugins/$plugin" "$APPDIR/usr/plugins/$plugin"
    linuxdeploy --appdir "$APPDIR" --deploy-deps-only "$APPDIR/usr/plugins/$plugin" >/dev/null
done

# Libraries linuxdeploy counts as part of every system, but that some leave out (seen missing on Debian 13 and
# Fedora 42) while libraries in the AppImage need them: libgcrypt needs libgpg-error, Kerberos libcom_err.
for lib in libgpg-error.so.0 libcom_err.so.2; do
    cp -L "/usr/lib/x86_64-linux-gnu/$lib" "$APPDIR/usr/lib/"
done

echo "== Pack"
ln -sf "usr/share/icons/hicolor/256x256/apps/$APP.png" "$APPDIR/.DirIcon"
mkdir -p "$SRC/release"
OUT=$SRC/release/$APP-$VER-x86_64.AppImage
ARCH=x86_64 appimagetool --no-appstream "$APPDIR" "$OUT" >/dev/null
(cd "$SRC/release" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
ls -la "$OUT"

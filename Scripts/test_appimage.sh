#!/usr/bin/env bash
# Try the AppImage on other distributions: each runs in a fresh container with that distribution's own
# PipeWire and WirePlumber (separate from this computer's sound), starts the AppImage without a screen and
# checks that Vox's devices appear in PipeWire. Needs podman.
#
#   Scripts/test_appimage.sh                    every distribution below
#   Scripts/test_appimage.sh fedora:43          just one
set -uo pipefail
cd "$(dirname "$0")/.."
APP=$(grep -m1 '^name' Cargo.toml | cut -d'"' -f2)
VER=$(grep -m1 '^version' Cargo.toml | cut -d'"' -f2)
IMAGE=$PWD/release/$APP-$VER-x86_64.AppImage
[ -f "$IMAGE" ] || { echo "No $IMAGE: run Scripts/appimage.sh --container first"; exit 1; }

DISTROS=("$@")
[ ${#DISTROS[@]} -gt 0 ] || DISTROS=(ubuntu:24.04 ubuntu:25.10 debian:13 fedora:42 fedora:43 archlinux:latest opensuse/tumbleweed:latest)

# What a desktop system has anyway: PipeWire, WirePlumber, D-Bus, OpenGL and fonts. The rest is in the AppImage.
read -r -d '' INSIDE <<'EOF'
set -e
if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq pipewire pipewire-bin wireplumber dbus libgl1 libegl1 libfontconfig1 >/dev/null
elif command -v dnf >/dev/null; then
    dnf install -y -q pipewire pipewire-utils wireplumber dbus-daemon mesa-libGL mesa-libEGL fontconfig >/dev/null
elif command -v pacman >/dev/null; then
    pacman -Sy --noconfirm --needed pipewire wireplumber dbus libglvnd mesa fontconfig >/dev/null
elif command -v zypper >/dev/null; then
    zypper -q -n install pipewire pipewire-tools wireplumber dbus-1 dbus-1-daemon Mesa-libGL1 Mesa-libEGL1 fontconfig >/dev/null
fi
. /etc/os-release
echo "system: $PRETTY_NAME, glibc $(ldd --version | head -1 | grep -oE '[0-9]+\.[0-9]+$'), PipeWire $(pipewire --version | grep -oE 'libpipewire [0-9.]+' | cut -d' ' -f2)"
export XDG_RUNTIME_DIR=/tmp/runtime XDG_CONFIG_HOME=/tmp/config HOME=/tmp/home LANG=C.UTF-8
mkdir -p -m 700 $XDG_RUNTIME_DIR $XDG_CONFIG_HOME $HOME
dbus-run-session -- bash -c '
    pipewire >/tmp/pipewire.log 2>&1 & sleep 1
    wireplumber >/tmp/wireplumber.log 2>&1 & sleep 2
    QT_QPA_PLATFORM=offscreen APPIMAGE_EXTRACT_AND_RUN=1 /test/Vox.AppImage >/tmp/vox.log 2>&1 & VOX=$!
    sleep 8
    if ! kill -0 $VOX 2>/dev/null; then echo "FAIL: Vox quit"; cat /tmp/vox.log; exit 1; fi
    NODES=$(pw-cli ls Node | grep -oE "node.description = \"Vox[^\"]*\"" | cut -d\" -f2 | sort | paste -sd, -)
    kill $VOX
    if [ -z "$NODES" ]; then echo "FAIL: no Vox devices in PipeWire"; cat /tmp/vox.log; exit 1; fi
    echo "Vox devices: $NODES"
    grep -iE "error|cannot|fail" /tmp/vox.log | grep -v "^$" | head -5 | sed "s/^/  log: /" || true
'
EOF

pass=0; fail=0
for d in "${DISTROS[@]}"; do
    echo "== $d"
    case $d in */*) ref=docker.io/$d ;; *) ref=docker.io/library/$d ;; esac
    podman run --rm --network host -v "$IMAGE:/test/Vox.AppImage:ro,Z" "$ref" bash -c "$INSIDE" 2>&1 \
        | grep -vE '^(debconf|WARNING: apt)'
    if [ "${PIPESTATUS[0]}" -eq 0 ]; then pass=$((pass + 1)); echo "   PASS"; else fail=$((fail + 1)); echo "   FAIL"; fi
done
echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]

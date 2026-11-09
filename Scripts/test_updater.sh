#!/usr/bin/env bash
# Exercise the updater against a local fake release: serves the newest built package as "v9.0.0" and runs the
# ignored test in a debug build. A dry run: it stops before the pkexec password prompt.
set -euo pipefail
cd "$(dirname "$0")/.."
PKG=$(ls -t packaging/*.pkg.tar.zst | head -1)
D=$(mktemp -d); trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$D"' EXIT
NAME=$(basename "$PKG"); cp "$PKG" "$D/$NAME"
(cd "$D" && sha256sum "$NAME" > "$NAME.sha256")
# BAD_SUM=1 corrupts the checksum: the updater must refuse (the test then fails with "checksum" in the message).
[ -n "${BAD_SUM:-}" ] && echo "0000000000000000000000000000000000000000000000000000000000000000  $NAME" > "$D/$NAME.sha256"
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
cat > "$D/release.json" <<J
{"tag_name":"v9.0.0","body":"Test release","assets":[
 {"name":"$NAME","browser_download_url":"http://127.0.0.1:$PORT/$NAME","size":$(stat -c %s "$PKG")},
 {"name":"$NAME.sha256","browser_download_url":"http://127.0.0.1:$PORT/$NAME.sha256"}]}
J
timeout 60 python3 -m http.server $PORT --bind 127.0.0.1 --directory "$D" >/dev/null 2>&1 &
sleep 1
VOX_UPDATE_DRY_RUN=1 VOX_UPDATE_API=http://127.0.0.1:$PORT/release.json XDG_CACHE_HOME="$D/cache" \
  cargo test updater::tests::the_whole -- --ignored --nocapture 2>&1 | grep -E "final state|test |panicked|stopped|check said|left|right"

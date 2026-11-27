#!/usr/bin/env bash
# Watch the running program's CPU and memory over time, to check that CPU stays low and memory doesn't keep
# growing (a leak). Uses only /proc, so it works on any Linux system. Leave it running as you normally
# would (playing audio, moving faders) while it watches.
#
#   Scripts/watch_usage.sh              60 minutes, a sample every 10 seconds
#   Scripts/watch_usage.sh 240 30       240 minutes, a sample every 30 seconds
#
# Every sample is also saved to a CSV file (time, CPU %, memory in MB) for a closer look or a chart.
set -euo pipefail
HERE=$PWD
APP=$(grep -m1 '^name' "$(dirname "$0")/../Cargo.toml" | cut -d'"' -f2)
MINUTES=${1:-60}
EVERY=${2:-10}

PID=$(pgrep -xo "$APP" || pgrep -fo "$APP-.*AppImage" || true)
[ -n "$PID" ] || { echo "$APP isn't running. Start it first."; exit 1; }
TICKS=$(getconf CLK_TCK)
CSV="$HERE/$APP-usage-$(date +%Y%m%d-%H%M).csv"
echo "seconds,cpu_percent,memory_mb" > "$CSV"

cpu_ticks() { awk '{print $14 + $15}' "/proc/$PID/stat"; }   # time spent on the CPU so far (user + system)
memory_kb() { awk '/^VmRSS:/ {print $2}' "/proc/$PID/status"; } # memory in use right now (resident)

echo "Watching $APP (pid $PID) for $MINUTES minutes, every $EVERY seconds. Saving to $CSV. Ctrl+C stops early."
printf '%8s  %6s  %9s\n' "time" "CPU %" "memory"
start=$(date +%s)
first_kb=$(memory_kb); max_kb=$first_kb; last_kb=$first_kb
cpu_sum=0; samples=0
prev_ticks=$(cpu_ticks); prev_time=$start

summary() {
    elapsed=$(( $(date +%s) - start ))
    echo
    echo "== $APP over $((elapsed / 60)) min $((elapsed % 60)) s ($samples samples)"
    [ "$samples" -gt 0 ] && awk -v s="$cpu_sum" -v n="$samples" 'BEGIN {printf "CPU:    %.2f %% on average (of one core)\n", s / n}'
    awk -v a="$first_kb" -v b="$last_kb" -v m="$max_kb" -v t="$elapsed" 'BEGIN {
        printf "Memory: %.1f MB at the start, %.1f MB at the end, %.1f MB at most\n", a/1024, b/1024, m/1024
        if (t >= 600) printf "Growth: %+.2f MB per hour\n", (b - a) / 1024 / (t / 3600)
    }'
    echo "Saved: $CSV"
}
trap 'summary; exit 0' INT

end=$(( start + MINUTES * 60 ))
while [ "$(date +%s)" -lt "$end" ]; do
    sleep "$EVERY"
    [ -d "/proc/$PID" ] || { echo "$APP quit."; break; }
    now=$(date +%s); ticks=$(cpu_ticks); kb=$(memory_kb)
    cpu=$(awk -v d="$((ticks - prev_ticks))" -v t="$((now - prev_time))" -v hz="$TICKS" 'BEGIN {printf "%.2f", (t > 0 ? 100 * d / hz / t : 0)}')
    prev_ticks=$ticks; prev_time=$now; last_kb=$kb
    [ "$kb" -gt "$max_kb" ] && max_kb=$kb
    cpu_sum=$(awk -v a="$cpu_sum" -v b="$cpu" 'BEGIN {print a + b}'); samples=$((samples + 1))
    t=$((now - start))
    printf '%02d:%02d:%02d  %6s  %6.1f MB\n' $((t / 3600)) $((t / 60 % 60)) $((t % 60)) "$cpu" "$(awk -v k="$kb" 'BEGIN {print k/1024}')"
    echo "$t,$cpu,$(awk -v k="$kb" 'BEGIN {printf "%.1f", k/1024}')" >> "$CSV"
done
summary

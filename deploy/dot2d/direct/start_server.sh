#!/system/bin/sh
echo "retired: deploy/dot2d/direct/start_server.sh dials 192.168.1.20 and is not the shipping supervisor" >&2
echo "use deploy/dot2d/emos/start_server.sh with core 127.0.0.1:8932" >&2
exit 1
# Historical body below is not executed.
# Home Mate direct-occupation supervisor (G5-2) — replaces EchoMuse's
# start_server.sh IN PLACE; the original is preserved next to this file as
# start_server.echomuse.sh (the rollback channel, kept on device until the
# direct form is stable — user direction 2026-11-08). Design doc:
# docs/g5/direct-firmware-design-20261108.md §2.4.
#
# A/B slot supervision with fast-exit swap. A failed slot rolls back to the
# other firmware slot; a second failure stays there and logs. This script
# EchoMuse is not a fallback target. The init service name is historical.

DIR=/data/local/tmp/hm-direct
LOG=/tmp/hm-direct.log
MAX_LOG=5242880
KEEP_LOG=524288
SUP_LOG=$DIR/supervisor.log
SUP_MAX=65536
SUP_KEEP=32768
MIN_RUNTIME=15
MAX_ATTEMPTS=3
CORE=192.168.1.20:8932
POLICY=$(cd "$(dirname "$0")" && pwd)/../emos/slot_decision.sh
if [ ! -r "$POLICY" ]; then
    POLICY=/data/local/bin/slot_decision.sh
fi
if [ ! -r "$POLICY" ]; then
    echo "slot_decision.sh missing; refusing to start (will not fall back to EchoMuse)" >&2
    exit 1
fi
# shellcheck disable=SC1090
. "$POLICY"

# ── Wait for the codec (EchoMuse waited for echoaudioservice; the direct
#    component needs the ALSA card up — same readiness, no Android service).
i=0
while [ $i -lt 120 ]; do
    [ -e /dev/snd/controlC0 ] && break
    sleep 2
    i=$((i + 2))
done

# ── Hardware init: EchoMuse's exact mixer sequence (names, never numbers —
#    the FireOS 6 kernel shifts control ids).
tinymix -D 0 "Audio_I2S1_Setting" On
tinymix -D 0 "HP DAC Playback Switch" 1 1
tinymix -D 0 "MFP Gpio Mute" On
tinymix -D 0 "PCM Playback Volume" 100 100
for adc in A B C D; do
    tinymix -D 0 "ADC_$adc Digital Volume Control" 88 88
    tinymix -D 0 "ADC_$adc MICPGA Volume Ctrl" 40 40
done

echo hm-direct > /sys/power/wake_lock
# P2 fix: ledcontroller is an INIT service — killing it just makes init
# respawn it (kill-war, "untracked pid killed by signal 1"). The clean
# takeover is `stop ledcontroller` (init marks it stopped, no respawn);
# the firmware owns /sys/.../0-003f/frame exclusively afterwards.
stop ledcontroller 2>/dev/null
mkdir -p $DIR

# ── Supervisor log: the ONLY chatty-on-boot artifact on /data (eMMC-light);
#    trimmed before every append so a crash loop can never grow past the cap.
sup_log() {
    if [ -f "$SUP_LOG" ]; then
        SIZE=$(wc -c < "$SUP_LOG" 2>/dev/null)
    else
        SIZE=0
    fi
    if [ "$SIZE" -gt "$SUP_MAX" ]; then
        tail -c $SUP_KEEP "$SUP_LOG" > "${SUP_LOG}.tmp" 2>/dev/null
        mv "${SUP_LOG}.tmp" "$SUP_LOG" 2>/dev/null
    fi
    UP=""
    if [ -r /proc/uptime ]; then
        read UP _REST < /proc/uptime 2>/dev/null
        UP=${UP%.*}
    fi
    echo "up=${UP}s wall=$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$SUP_LOG"
}

amp_off() {
    tinymix -D 0 "PCM Playback Volume" 0 0 2>/dev/null
    tinymix -D 0 "Ext_Speaker_Amp_Switch" Off 2>/dev/null
}

# ── RAM log cap (chatty firmware output stays in /tmp, wiped at boot).
(
    while true; do
        sleep 300
        SIZE=$(wc -c < "$LOG" 2>/dev/null)
        if [ -n "$SIZE" ] && [ "$SIZE" -gt "$MAX_LOG" ]; then
            tail -c $KEEP_LOG "$LOG" > "${LOG}.1" 2>/dev/null
            : > "$LOG"
            echo "[supervisor] log trimmed: ${SIZE} bytes" >> "$LOG"
        fi
    done
) &
TRIM_PID=$!

CHILD=0
trap 'sup_log "term signalled — supervisor exiting"; kill $CHILD $TRIM_PID 2>/dev/null; wait $CHILD 2>/dev/null; amp_off; exit 0' TERM INT

# ── A/B slots + fast-exit swap. No EchoMuse fallback.
[ -e $DIR/current ] || ln -sf $DIR/audio_a $DIR/current
attempt=0
round=0
sup_log "boot slot=$(readlink $DIR/current 2>/dev/null) core=$CORE"

while true; do
    START_TIME=$(date +%s)
    $DIR/current firmware --core $CORE --state-dir $DIR >> $LOG 2>&1 &
    CHILD=$!
    wait $CHILD
    EXIT_CODE=$?
    amp_off
    END_TIME=$(date +%s)
    RUNTIME=$(( END_TIME - START_TIME ))
    # P3 forensics: each exit carries its code + the LAST 12 lines of the
    # RAM log into the persistent supervisor log — a reboot no longer
    # destroys the evidence of why the previous round died.
    LOG_TAIL=$(tail -12 $LOG 2>/dev/null)
    sup_log "exit code=$EXIT_CODE ran=${RUNTIME}s; log tail: $LOG_TAIL"

    if [ $RUNTIME -ge $MIN_RUNTIME ]; then
        attempt=0
        sup_log "exit code=$EXIT_CODE ran=${RUNTIME}s — restarting"
        sleep 2
        continue
    fi

    attempt=$(( attempt + 1 ))
    sup_log "fast-exit ${attempt}/${MAX_ATTEMPTS} code=$EXIT_CODE ran=${RUNTIME}s"
    if [ $attempt -lt $MAX_ATTEMPTS ]; then
        sleep 3
        continue
    fi

    attempt=0
    round=$(( round + 1 ))
    CURRENT=$(readlink $DIR/current 2>/dev/null)
    CURRENT=${CURRENT:-audio_a}
    DECISION=$(slot_decision "$CURRENT" "$round")
    set -- $DECISION
    action=$1
    target=$2
    if [ "$action" = "stay-error" ]; then
        sup_log "ERROR firmware slots exhausted fast exits; staying on $target; not starting EchoMuse"
        paint_supervisor_error_ring
        sleep 30
        continue
    fi
    if [ ! -x "$DIR/$target" ]; then
        sup_log "ERROR rollback slot $target is not executable; staying on $CURRENT; not starting EchoMuse"
        paint_supervisor_error_ring
        sleep 30
        continue
    fi
    ln -sf "$target" $DIR/current
    sup_log "slot rollback $CURRENT -> $target after $MAX_ATTEMPTS fast exits (not EchoMuse)"
done

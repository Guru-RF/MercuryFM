#!/usr/bin/env bash
# Two-node MercuryFM ARQ loopback over a PulseAudio null-sink bridge (timer-clocked,
# userspace — no kernel snd-aloop, no /dev/snd). Proves the CALL/ACCEPT handshake
# completes and the ARQ gear-shift climbs the ladder live (DATAC15 -> DATAC17) with a
# real data transfer, entirely in a Linux container, no radios. Reaching the top rung
# qam16fm (mode 26) needs a sustained ~19.5 dB link; this null-sink path caps ~17 dB, so
# that last rung is an OTA-bed item. See tests/loopback/README.md.
set -u
BIN=/src/mercuryfm
LOGDIR=/tmp/lb

# PulseAudio refuses to run as root -> drop to a normal user and re-exec the rest there.
if [ "$(id -u)" = "0" ]; then
    id runner >/dev/null 2>&1 || useradd -m runner
    rm -rf "$LOGDIR"; mkdir -p "$LOGDIR" "/run/user/$(id -u runner)"
    cp /work/drive.py "$LOGDIR/drive.py"
    chown -R runner:runner "$LOGDIR" "/run/user/$(id -u runner)" /home/runner 2>/dev/null
    exec su runner -c "bash /work/run_pulse_loopback.sh"
fi

# ---- everything below runs as 'runner' ----
export HOME=/home/runner
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
cd "$LOGDIR"

# High-fidelity pulse config: never resample (mercury already runs 48k on the sound-card
# path and downsamples 48->8 itself), 32-bit samples, so the null-sink monitor is
# effectively bit-exact and the modem sees a high-SNR channel.
mkdir -p "$HOME/.config/pulse"
cat > "$HOME/.config/pulse/daemon.conf" <<'CONF'
avoid-resampling = yes
resample-method = soxr-vhq
default-sample-format = s32le
default-sample-rate = 48000
alternate-sample-rate = 48000
default-fragments = 4
default-fragment-size-msec = 5
CONF

echo "== starting PulseAudio (userspace null sinks) =="
pulseaudio --exit-idle-time=-1 --disable-shm=1 --start --log-target=file:"$LOGDIR/pa.log"
sleep 1
# One null sink per direction @ 48 kHz / s32le. Each auto-creates a <name>.monitor source.
pactl load-module module-null-sink sink_name=a2b rate=48000 channels=1 format=s32le sink_properties=device.description=a2b >/dev/null
pactl load-module module-null-sink sink_name=b2a rate=48000 channels=1 format=s32le sink_properties=device.description=b2a >/dev/null
# full scale, no attenuation
for d in a2b b2a; do pactl set-sink-volume $d 100% 2>/dev/null; pactl set-source-volume ${d}.monitor 100% 2>/dev/null; done
echo "sinks:";   pactl list short sinks   | awk '{print "  "$2}'
echo "sources:"; pactl list short sources | awk '{print "  "$2}'

echo "== launching two nodes =="
# Node A (callee): TX -> sink a2b, RX <- source b2a.monitor.  TNC ctl 8300/data 8301.
"$BIN" -x pulse -o a2b -i b2a.monitor -C /work/loopback.ini -p 8300 -b 8100 -v -L "$LOGDIR/mA.log" >"$LOGDIR/mA.out" 2>&1 &
# Node B (caller/ISS): TX -> sink b2a, RX <- source a2b.monitor.  TNC ctl 8302/data 8303.
"$BIN" -x pulse -o b2a -i a2b.monitor -C /work/loopback.ini -p 8302 -b 8102 -v -L "$LOGDIR/mB.log" >"$LOGDIR/mB.out" 2>&1 &

# wait for both to log + bind
for _ in $(seq 1 40); do
    [ -s "$LOGDIR/mA.log" ] && [ -s "$LOGDIR/mB.log" ] && break; sleep 0.3
done
sleep 2
echo "== driving the link =="
PAYLOAD=40000 python3 "$LOGDIR/drive.py" | tee "$LOGDIR/drive.out"

echo
echo "############ PROOF ############"
echo "--- pulse routing (both nodes connected to their sink/source?) ---"
pactl list short sink-inputs 2>/dev/null | wc -l | xargs echo "  sink-inputs:"
pactl list short source-outputs 2>/dev/null | wc -l | xargs echo "  source-outputs:"
echo "--- (b) sender selected QAM16FM (26) [mB.log] ---"
grep -aE 'Mode negotiation: [0-9]+ -> 26 ' "$LOGDIR/mB.log" | head -3
echo "--- (d) receiver accepted mode -> 26 [mA.log] ---"
grep -aE 'MODE_REQ.*-> 26|peer TX mode.*26' "$LOGDIR/mA.log" | head -2
echo "--- (e) modem switched carriers to QAM16FM [both] ---"
grep -aE 'Switched modem mode to 26|QAM16FM' "$LOGDIR/mA.log" "$LOGDIR/mB.log" | head -3
echo "--- any Mode negotiation lines (which modes were reached) [mB.log] ---"
grep -aoE 'Mode negotiation: [0-9]+ -> [0-9]+' "$LOGDIR/mB.log" | sort | uniq -c
echo "--- CALL/data decoded across the bridge (mode + snr) [mA.log] ---"
grep -aoE 'Decoded frame mode=[0-9]+ \([A-Z0-9]+\).*snr=[0-9.]+' "$LOGDIR/mA.log" | tail -4
echo "--- effective peer SNR the ARQ gear-shift saw [mB.log] ---"
grep -aoE 'peer_snr=[0-9.-]+|eff=[0-9.-]+ dB' "$LOGDIR/mB.log" | tail -6
echo "--- highest reported SNR seen on any decode [both] ---"
grep -aoE 'snr=[0-9.]+' "$LOGDIR/mA.log" "$LOGDIR/mB.log" | grep -aoE '[0-9.]+' | sort -n | tail -1 | xargs echo "  max snr:"
echo
echo "=== VERDICT ==="
CONNECTED=$(grep -ac 'CONNECTED BBBB' "$LOGDIR/drive.out" 2>/dev/null)
TOP=$(grep -aoE 'Mode negotiation: [0-9]+ -> [0-9]+' "$LOGDIR/mB.log" | grep -aoE '[0-9]+$' | sort -n | tail -1)
rc=1
if grep -qaE 'Mode negotiation: [0-9]+ -> 26 ' "$LOGDIR/mB.log"; then
    echo "PASS+ : two-node ARQ link connected and negotiated all the way to QAM16FM (26)"; rc=0
elif [ "$CONNECTED" -ge 1 ] 2>/dev/null && [ -n "$TOP" ] && [ "$TOP" -gt 22 ]; then
    echo "PASS  : two-node ARQ link CONNECTED and gear-shifted DATAC15 -> mode $TOP."
    echo "        (qam16fm entry needs sustained ~19.5 dB; this userspace null-sink"
    echo "         loopback caps at ~17 dB — reach the top rung on the OTA bed.)"
    rc=0
elif [ "$CONNECTED" -ge 1 ] 2>/dev/null; then
    echo "PARTIAL: link CONNECTED but did not gear-shift above the DATAC15 floor."; rc=1
else
    echo "FAIL  : CALL/ACCEPT handshake did not complete."; rc=1
fi
pkill -u "$(id -u)" mercuryfm 2>/dev/null
pkill -u "$(id -u)" pulseaudio 2>/dev/null
exit $rc

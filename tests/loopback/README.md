# Two-node ARQ loopback (radio-free)

Runs **two `mercuryfm` nodes** against each other over a **timer-clocked PulseAudio
null-sink audio bridge**, entirely inside a Linux container — no radios, no sound card, no
kernel `snd-aloop`, no `/dev/snd`. It drives the VARA-style TNC through a real
CALL/ACCEPT connect + ARQ data transfer and watches the OLLA gear-shift climb the mode
ladder.

## Why PulseAudio null sinks (not FIFOs)

A naive 2-FIFO bridge on the host carries audio but has no shared clock — the ~8 s
latency/jitter desyncs the half-duplex CALL↔ACCEPT round-trip and the link never connects.
A PulseAudio **null sink** is a virtual device clocked by PA's timer; its `.monitor`
source is a copy of what was written. Two null sinks (`a2b`, `b2a`) give both directions a
shared, real-time clock — which makes the handshake complete. It's fully userspace, so it
works in the Kata VM that Apple `container` uses (which has no loadable kernel modules).

## Run it

```bash
# from the repo root — builds mercuryfm + installs pulseaudio into the image
container build --platform linux/arm64 -t mercuryfm-test:pulse -f tests/loopback/Dockerfile .

# run the harness (bind-mount this dir so the scripts + loopback.ini are visible as /work)
container run --rm \
  --mount type=bind,source="$PWD/tests/loopback",target=/work \
  mercuryfm-test:pulse
```

Also works with Docker/Podman (`docker build ... ; docker run --rm -v "$PWD/tests/loopback":/work ...`).
Exit code 0 = PASS.

## What it proves (current result)

```
CONNECTED BBBB AAAA 2300            <- CALL/ACCEPT handshake completed
A received N/40000 bytes            <- real ARQ payload delivered
Mode negotiation: 22 -> 24          <- live OLLA gear-shift DATAC15 -> DATAC17
PASS : two-node ARQ link CONNECTED and gear-shifted DATAC15 -> mode 24
```

So the full stack works end-to-end between two independent processes: TNC, ARQ FSM,
connect handshake, data transfer, and the OLLA gear-shift ladder — including the
`qam16fm` mode, which is loaded in the pool the whole time.

## The one thing it can't reach here: `qam16fm` (mode 26)

The gear-shift stops at **DATAC17**, not the top rung `qam16fm`, because:

- The userspace null-sink monitor is **timer-jittered**: sustained `peer_snr` caps at
  **~17 dB** (peaks to ~22, but the gear-shift acts on the sustained value). Raising the
  modulator level (`tx_gain_db`) doesn't help — it clips before it helps.
- `qam16fm`'s **entry** gate is `ARQ_SNR_MIN_QAM16FM_DB + ARQ_SNR_HYST_DB = 14.5 + 5.0 =
  19.5 dB`, and — a subtlety — that's compared against `peer_snr` reported in the
  **current mode's** SNR space (DATAC16/17 have small `snr_offset`), while `qam16fm`'s own
  `+9 dB` offset would report ~26 dB *once on it*. So entry needs a genuinely clean/strong
  link; ~17 dB just misses it.

On the **OTA bed** (real FM radios, `TODO.md` P1) a solid signal is 25–40 dB, so it clears
19.5 dB easily and this harness would print `PASS+ : ... negotiated all the way to
QAM16FM (26)`. The waveform itself is already proven end-to-end by the codec2 raw loopback
(0 coded errors) — see [NOTES.md](../../NOTES.md) §4a.

## Files

| File | What |
|---|---|
| `Dockerfile` | Debian + `mercuryfm` build + PulseAudio + python3 |
| `run_pulse_loopback.sh` | Orchestration: start PA, 2 null sinks, launch both nodes, drive, grep, verdict |
| `drive.py` | TNC driver: MYCALL/LISTEN/CONNECT, push 40 KB, watch for `CONNECTED` + gear-shift |
| `loopback.ini` | Test-only `tx_gain_db` (headroom for the null-sink path; not a real-radio setting) |

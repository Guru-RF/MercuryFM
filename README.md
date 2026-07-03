# MercuryFM

An open, GPL data modem for **VHF/UHF FM voice channels** — in the spirit of VARA FM —
built by reusing the channel-agnostic modem framework of
**[Rhizomatica Mercury](https://github.com/Rhizomatica/mercury)** (the HERMES HF modem)
and giving it an FM-optimized physical layer.

> **Status: forked & building.** This repo is a fork of Mercury v2 (upstream commit
> `5aa5b7b`, v1.9.9). It **builds and runs today** on macOS (Apple Silicon) and Linux
> (verified on linux/arm64). The FM-specific waveform work has not started yet — see the
> roadmap in **[NOTES.md](NOTES.md)**.

## Why

Mercury already provides the hard 80% of a soundcard modem — an ARQ data link, a
VARA-compatible TCP TNC, audio I/O, PTT/radio control, and KISS/broadcast framing — all of
which are **channel-agnostic** and reusable on an FM link. What Mercury lacks for FM is a
suitable waveform: its PHY is the FreeDV OFDM DATAC modes, purpose-built for the fading,
low-SNR **HF** channel. On a flat, high-SNR **FM** voice channel those modes work but waste
~15–20× of the available capacity. MercuryFM's job is to add an FM-tuned waveform
(higher-order QAM, high code rate, minimal cyclic prefix, sparse pilots) to that proven
framework. See the full engineering analysis, data-rate projections vs VARA FM, and roadmap
in **[NOTES.md](NOTES.md)**.

## Building

### macOS (Apple Silicon)

Mercury's build system already has a Darwin/CoreAudio path, so it builds out of the box
with the Xcode command-line tools. HAMLIB is optional (auto-detected via `pkg-config`).

```bash
# prerequisites (HAMLIB optional, for direct rig control):
xcode-select --install        # clang + make, if not already present
brew install pkg-config        # + optionally: brew install hamlib

make CC=clang -j
./mercuryfm -l                   # list modulation modes (proves the modem inits)
./mercuryfm -h
```

Produces a native `arm64` Mach-O binary using the **CoreAudio** backend
(`-x coreaudio`). No ALSA/PulseAudio on macOS.

### Linux — via Apple `container` (verified: linux/arm64)

A [`Dockerfile`](Dockerfile) mirrors the upstream Debian build (ALSA + PulseAudio +
HAMLIB). On Apple Silicon, [Apple's `container`](https://github.com/apple/container) runs
it natively as `linux/arm64` and smoke-tests the binary (`mercuryfm -l`) at build time:

```bash
container system start                                   # once per boot, if needed
container build --platform linux/arm64 -t mercuryfm:trixie-arm64 .
container run --rm mercuryfm:trixie-arm64                # prints -h
container run --rm mercuryfm:trixie-arm64 ./mercuryfm -l   # list modes
```

The same `Dockerfile` works with Docker/Podman (`docker build --platform linux/arm64 .`).

### Linux — native (Debian/Ubuntu/RPi)

```bash
sudo apt-get update && sudo apt-get install -y \
    build-essential pkg-config libasound2-dev libpulse-dev libhamlib-dev make git
make -j
sudo make install       # optional, installs to /usr/bin
```

The FreeDV codec is vendored in-tree — no external FreeDV/codec2 packages needed. For
Raspberry Pi tuning: `make PLATFORM=rpi4` or `make PLATFORM=rpi5`. See
[README.upstream.md](README.upstream.md) for the complete upstream build/run/config
reference (TNC ports, radio control, INI file, Windows).

## Note on the `-G` web UI (Mongoose / GPL)

The optional `-G` WebSocket UI links **Mongoose**, which is `GPL-2.0-only`. That does not
combine cleanly with this GPL-3.0 project **in a distributed binary**, so **MercuryFM ships
source only — it does not publish pre-built binaries** (you build it yourself, as above,
which never "conveys" the combined binary). See [NOTES.md §6](NOTES.md) and
[NOTICE.md](NOTICE.md). A binary built **without** the `-G` UI is pure GPLv3 and freely
distributable.

## License

MercuryFM is **free software under the GNU General Public License, version 3 or (at your
option) any later version (GPL-3.0-or-later)**, inherited from upstream Mercury. See
[LICENSE](LICENSE).

It is a derivative of Rhizomatica Mercury (forked @ `5aa5b7b`), an independent project
**not** endorsed by or affiliated with Rhizomatica, HERMES, or FreeDV. Attribution and
third-party component licenses are in **[NOTICE.md](NOTICE.md)**.

## Repository layout

| Path | What |
|---|---|
| [NOTES.md](NOTES.md) | Feasibility audit, FM data-rate projections vs VARA, license analysis, roadmap |
| [NOTICE.md](NOTICE.md) | Attribution + third-party license inventory |
| [README.upstream.md](README.upstream.md) | Upstream Mercury README (full build/run/config/TNC reference) |
| [Dockerfile](Dockerfile) | Linux/arm64 build via Apple `container` (or Docker/Podman) |
| `modem/`, `datalink_arq/`, `data_interfaces/`, … | Vendored Mercury source (the fork) |

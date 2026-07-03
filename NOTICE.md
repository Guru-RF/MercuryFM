# MercuryFM — Attribution & Third-Party Licenses

MercuryFM is a derivative work of **Mercury**, the HERMES HF modem by
**[Rhizomatica](https://www.rhizomatica.org/)**.

- Upstream: <https://github.com/Rhizomatica/mercury>
- Forked from commit `5aa5b7b` (Mercury v2, version 1.9.9)
- MercuryFM is **GPL-3.0-or-later**, inherited from upstream. See [LICENSE](LICENSE).
- MercuryFM is an independent fork and is **not** endorsed by or affiliated with
  Rhizomatica, the HERMES project, or the FreeDV project.

## Upstream authors (Mercury / HERMES team)

- **Rafael Diniz** — ARQ, broadcast, TCP interface (primary copyright holder,
  "Copyright (C) 2024–2026 Rhizomatica")
- **Pedro Messetti** — testing framework, general improvements
- **Matheus Thibau** — graphical user interface

Mercury is part of the HERMES project and is sponsored by ARDC.

## Vendored third-party components

When these components are used **separately** from the combined MercuryFM binary, they
carry their own licenses. The combined binary is distributed under GPL-3.0-or-later.

| Component | Path (upstream) | License |
|---|---|---|
| FreeDV / codec2 subset (David Rowe) | `modem/freedv/` | LGPL-2.1 — see `LICENSE-freedv` |
| kiss_fft (embedded in FreeDV) | `modem/freedv/` | BSD-3-Clause |
| iniparser | `common/iniparser/` | MIT — see `common/iniparser/LICENSE` |
| ffaudio + ffbase | `audioio/ffaudio/` | Unlicense — see `audioio/ffaudio/UNLICENSE` |
| Hamlib (Windows prebuilt DLLs) | `radio_io/hamlib-w64/` | LGPL-2.1 — see `COPYING.LIB.txt` |
| Unity (test framework) | `tests/` | MIT |
| **Mongoose** (WebSocket UI, `-G`) | `gui_interface/websocket/` | **GPL-2.0-only or commercial** |

> **⚠️ Mongoose license conflict → MercuryFM ships SOURCE ONLY.**
> `gui_interface/websocket/mongoose.{c,h}` is `SPDX: GPL-2.0-only or commercial` (Cesanta
> Software). **GPL-2.0-only is not forward-compatible with GPL-3.0**, so statically linking
> it into a GPL-3.0-or-later binary is a conflict *at distribution of the binary*.
> **Project decision (2026-07-04): MercuryFM does not publish pre-built binaries** — no
> release ZIPs, no CI/release artifacts, no `.deb` packages. Operators compile locally;
> a privately-compiled binary is not "conveyed" so the conflict is never triggered. The
> `-G` WebSocket UI (hence Mongoose) is kept **build-time optional**, so a Mongoose-free,
> pure-GPLv3 binary can be built and distributed if ever needed. A builder who then
> *redistributes* their own Mongoose-linked binary inherits the conflict. Long-term fix:
> replace Mongoose with a GPLv3-compatible library or run the UI as a separate process.
> See [NOTES.md §6](NOTES.md).

## Changes from upstream

Per GPLv3 §5(a), files modified in MercuryFM must carry a prominent notice of the change
and the date. New/modified files should add a copyright line **alongside** (never
replacing) the upstream Rhizomatica copyright, e.g.:

```
/* Copyright (C) 2026 <MercuryFM authors>
 * Modified from Rhizomatica Mercury (5aa5b7b) on 2026-xx-xx: <what changed>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
```

*This NOTICE is a starting inventory taken from an audit of Mercury @ `5aa5b7b`; keep it
in sync as components are actually vendored into this repo.*

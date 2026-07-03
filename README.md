# MercuryFM

An open, GPL data modem for **VHF/UHF FM voice channels** — in the spirit of VARA FM —
built by reusing the channel-agnostic modem framework of
**[Rhizomatica Mercury](https://github.com/Rhizomatica/mercury)** (the HERMES HF modem)
and giving it an FM-optimized physical layer.

> **Status: greenfield / planning.** No code is vendored yet. This repo currently holds
> the feasibility assessment and the project license. See **[NOTES.md](NOTES.md)** for
> the full engineering analysis and roadmap.

## Why

Mercury already provides the hard 80% of a soundcard modem — an ARQ data link, a
VARA-compatible TCP TNC, audio I/O, PTT/radio control, and KISS/broadcast framing — all
of which are **channel-agnostic** and reusable on an FM link. What Mercury lacks for FM
is a suitable waveform: its PHY is the FreeDV OFDM DATAC modes, purpose-built for the
fading, low-SNR **HF** channel. On a flat, high-SNR **FM** voice channel those modes work
but waste ~15–20× of the available capacity. MercuryFM's job is to add an FM-tuned
waveform (higher-order QAM, high code rate, minimal cyclic prefix, sparse pilots) to that
proven framework. See [NOTES.md §1–4](NOTES.md).

## License

MercuryFM is **free software, licensed under the GNU General Public License, version 3 or
(at your option) any later version (GPL-3.0-or-later)**, inherited from upstream Mercury.
See [LICENSE](LICENSE).

MercuryFM is a derivative of Rhizomatica Mercury (forked from commit `5aa5b7b`). It is an
independent project and is **not** endorsed by or affiliated with Rhizomatica, HERMES, or
FreeDV. Attribution and third-party component licenses are in **[NOTICE.md](NOTICE.md)** —
which also flags a Mongoose GPL-2.0-only vs GPL-3.0 conflict that must be resolved before
distributing binaries.

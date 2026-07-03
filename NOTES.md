# MercuryFM — Engineering Feasibility Notes

*Can we reuse [Rhizomatica Mercury](https://github.com/Rhizomatica/mercury) (HF data
modem, GPL-3.0-or-later) to build an FM-mode data modem in the spirit of VARA FM?*

- **Date:** 2026-07-04
- **Status:** greenfield (this repo is empty; nothing forked yet)
- **Upstream analysed:** `github.com/Rhizomatica/mercury` @ `5aa5b7b` (Mercury v2, `VERSION__ "1.9.9"`)
- **Method:** full clone + file-level source audit (PHY, ARQ, TNC, audio, radio I/O,
  licensing) — all figures/paths below were read out of the actual tree.

---

## 1. Bottom line up front

**Yes — qualified. Reuse Mercury.** Roughly 60–80% of Mercury by volume is a clean,
channel-agnostic modem *framework* (ARQ reactor, VARA-style TCP TNC, audio I/O, PTT
control, KISS/broadcast framing) that ports to a VHF/UHF-FM link with **retuning, not
rewriting**. Forking is fully permitted by GPL-3.0-or-later.

**The single most important caveat:** Mercury has *no waveform of its own*. Its entire
PHY is David Rowe's FreeDV/codec2 OFDM **DATAC** modes, which are **QPSK-only,
rate-1/2-class LDPC, dense-pilot, cyclic-prefix waveforms purpose-built for the
frequency-selective, fading, low-SNR HF channel** — the exact opposite of what a flat,
high-SNR FM voice channel wants. They will *function* over FM unchanged (it's just
300–2700 Hz audio) but deliver on the order of 1/10th of VARA FM's throughput.
**Matching VARA FM requires authoring a new flat-channel waveform family (higher-order
QAM, high code rate, sparse pilots, minimal cyclic prefix), which is real new DSP — not
a config flip.** Everything above the PHY is the reusable prize; the PHY is the work.

A secondary but real caveat: the ARQ layer is only ~80% channel-agnostic. Its
gear-shift ladder and per-mode SNR thresholds are **hard-coded FreeDV mode constants in
C**, not a pure table, so "swapping modes" means editing code in a few files.

---

## 2. What Mercury actually is

Mercury v2 (Rhizomatica's HERMES modem, C, GPL-3.0-or-later, ~208k lines) is cleanly
layered on top of a single PHY boundary:

- **PHY**: `modem/modem.c` (~63 KB) is a thin wrapper around a **vendored,
  Rhizomatica-modified FreeDV/codec2 fork** in `modem/freedv/`. All data transport uses
  FreeDV **OFDM data-raw** waveforms (QPSK; one 16-QAM mode `qam16c2`), never the voice
  codecs. Internal rate 8 kHz, 1500 Hz centre; sound card 48 kHz; a polyphase resampler
  (`audioio/resampler.c`, ratio 6) bridges them.
- **ARQ**: `datalink_arq/` — an event-driven reactor: `arq_fsm.{c,h}` (connection +
  data-flow state machines), `arq_events.h`, `arq_modem.c` (thread-safe action queue),
  with an `arq_fsm_callbacks_t` function-pointer interface (`send_tx_frame`,
  `notify_connected`, `deliver_rx_data`…). Real SNR + OLLA (outer-loop link adaptation)
  gear-shifting over a 6-level ladder.
- **TNC**: `data_interfaces/tcp_interfaces.c` — a **VARA-compatible** TCP command/data
  TNC (it literally replies `VARA version 4.9.0 registered`). Control port on
  `tcp_base_port`, data port on `+1`. MYCALL/LISTEN/CONNECT/BW*/DISCONNECT/ABORT/CQFRAME
  plus VARA-compat no-ops. Zero FreeDV/HF references.
- **Audio**: `audioio/audioio.c` on the vendored `ffaudio` lib —
  ALSA/Pulse/WASAPI/DSOUND/CoreAudio/OSS/AAUDIO + SHM/NULL/FIFO backends, 48 kHz.
- **Radio control**: `radio_io/radio_io.c` — **PTT-only** via hamlib `rig_set_ptt()` or
  HERMES SysV-SHM (sbitx). **No frequency or mode setting anywhere** — keys TX only, so a
  VHF/FM rig works identically.
- **Broadcast/KISS**: `datalink_broadcast/` — standard KISS framing (FEND/FESC, VARA
  KISS command bytes), broadcast-vs-ARQ classified from the decoded Mercury packet's
  first byte, not the bearer.

Layers are wired in `main.c`:
`audioio_init → radio_io_init → init_modem → arq_init(payload_bytes, mode) →
broadcast_run → interfaces_init(...)`. The PHY exposes
`generic_modem_t { struct freedv *freedv; int mode; size_t
payload_bytes_per_modem_frame; }` (`modem/modem.h:33-38`) — the `mode` int is an opaque
tag to the TNC and most of ARQ, which is what makes the upper layers swappable.

---

## 3. Reuse map

**Thesis (confirmed):** the tedious, hard-won 80% — ARQ, VARA-style TNC, audio, PTT,
framing — is channel-agnostic and directly reusable. HF-specificity *should* live in the
PHY, but a small amount **leaks** into the ARQ mode tables and the resampler config.

| Subsystem | Files | Verdict | Notes |
|---|---|---|---|
| TCP TNC | `data_interfaces/tcp_interfaces.c`, `net.h` | **KEEP AS-IS** | Already a VARA clone, fully decoupled via command queue + callbacks. A Winlink/VARA-FM client talks to it unchanged. |
| Radio control / PTT | `radio_io/radio_io.{c,h}` | **KEEP AS-IS** | Pure hamlib PTT or SHM keying; no freq/mode logic. Works on any FM rig. |
| KISS framing | `datalink_broadcast/kiss.{c,h}` | **KEEP AS-IS** | Standard KISS + VARA command bytes. Generic bearer a Reticulum/RNode layer would ride on (no Reticulum in-repo — framing primitive only). |
| Broadcast validation | `datalink_broadcast/broadcast.c` | **LIGHT ADAPT** | Only PHY-specific bit: hard-coded `freedv_to_hermes_mode_map[]` / `hermes_broadcast_frame_size[]` (`broadcast.c:42-55`). Update the table for FM modes (it only *warns* on mismatch — silent misalignment risk). |
| Audio backends | `audioio/audioio.c`, `ffaudio` | **KEEP AS-IS** | 48 kHz sound-in/out abstraction is channel-neutral. |
| Resampler | `audioio/resampler.c` | **LIGHT ADAPT** | Hard-codes 8 kHz modem rate + `fc=3400 Hz` LPF (HF-SSB passband). Reconfigure only if the FM waveform wants a wider passband / different internal rate. |
| ARQ reactor (framework) | `datalink_arq/arq_fsm.c`, `arq_modem.c`, `arq_events.h` | **KEEP structure** | FSM, event/action queues, callback interface, header codec, retry machinery all transfer. |
| ARQ mode ladder + thresholds | `arq_fsm.c` `select_best_mode()`, `mode_snr_floor_db()`; `arq_protocol.{c,h}` | **MODERATE ADAPT** | See §4/§8. Hard-coded `FREEDV_MODE_DATAC*` if-cascade + per-mode SNR `#define`s + timing table. Re-tabulate and re-measure. |
| **PHY waveform** | `modem/modem.c`, `modem/freedv/` | **ADD MODE (short term) / NEW WAVEFORM (to beat VARA)** | The core work. See §4. |
| Voice codecs, analog FM, COHPSK, FDMDV | `modem/freedv/codec2.c`, `fm.c`, `cohpsk.c`, … | **IGNORE** | Compiled but off the Mercury data path. |

> **⚠️ "VARA-compatible" = API only, NOT over-the-air.** The VARA compatibility is at the
> **host↔modem TCP layer** — an existing Winlink/Pat client can *drive* MercuryFM as if it
> were a VARA TNC. It does **not** mean MercuryFM interoperates with VARA on the radio.
> The RF waveform (OFDM constellation, FEC, ARQ framing) is FreeDV/your-FM-mode, which a
> real VARA station cannot demodulate (VARA's waveform is proprietary and unpublished).
> Consequence: a session against a genuine VARA station **fails at the RF layer** even
> though the local TNC handshake succeeds; data transfer only completes **MercuryFM ↔
> MercuryFM** (Winlink on both ends, common waveform in the middle). The API reuse buys the
> existing host-software ecosystem for free — not on-air VARA interop. (Also: Mercury
> mimics **VARA HF** 4.9.0; Winlink's **VARA FM** session type differs slightly, so a few
> TNC-command details may need covering to drive MercuryFM in FM mode.)

---

## 4. The core technical gap (and where a new mode plugs in)

### Why DATAC is wrong for FM

FreeDV DATAC modes optimize for HF: cyclic prefix (Tcp 4–6 ms) to guard multipath delay
spread, dense pilots (ns=5 between pilots) to track Doppler, QPSK + rate-1/2..1/3 LDPC to
survive deep fades at −4…+5 dB SNR. An FM voice channel is the opposite: above the
capture-effect threshold it is **flat, AWGN-like, non-fading, near-constant high SNR**,
then a hard cliff at ~10–12 dB C/N. On that channel:

- **Cyclic prefix = pure waste** (no ISI to guard) — ~10–20% of symbol time thrown away.
- **Dense pilots = wasted symbols** (phase is stable, no Doppler).
- **QPSK + rate-1/2 LDPC massively under-drives the SNR** — flat AWGN at ~25 dB supports
  16-/64-QAM and code rate 0.8+.

**Quantified gap:** DATAC1 = 980 bps in 1700 Hz ≈ 0.58 bps/Hz. VARA FM exceeds
**~12,000 bps** in the same mic audio (~4.5–5 bps/Hz) and **~25,000 bps** over the 9600
flat-audio data port. Shannon for ~2.4 kHz at ~25 dB ≈ 20 kbps. So DATAC runs **~15–20×
below the flat-channel ceiling**. Recoverable gains: QPSK→64-QAM ≈3×, rate 0.5→0.83
≈1.7× (≈5× before touching pilots/CP), plus bandwidth widening (2.7 kHz mic → ~6 kHz
data port) ≈2.2× → 10×+.

### Parameter change or new modem? — It depends how far you go

Two distinct paths, do not conflate them:

**(a) Add an FM-tuned OFDM mode — a parameter exercise (no new DSP).**
Mercury's fork **already proves 16-QAM works**: `qam16c2` (bps=4, rate 0.60, tcp=4 ms,
nc=33, ~2.1 kHz, ~3100 bps @ +15 dB). The OFDM engine (`ofdm.c`/`ofdm_mode.c`) already
supports configurable CP, pilot density (np/ns), any LDPC codename, and bps=4. An FM mode
can start from the `qam16c2` template and push **tcp→~0, np down, rate up**. This is
boilerplate spread across ~5 files (below), **none of which touches ARQ**. This gets you
into the *few-kbps, better-than-DATAC* range quickly and de-risks the whole stack.

**(b) Beat VARA FM (10–25 kbps) — a new mode family, but less new DSP than it looks.**
The shipped codec2 OFDM engine hard-asserts `bps ∈ {2,4}` (`ofdm.c:1193`,
`mpdecode_core.c:652`) — only **QPSK and 16-QAM** exist; 64-QAM (bps=6) and 256-QAM
(bps=8) are not implemented. **But the expensive part is already generic:** the
soft-decision demapper (`symbols_to_llrs`→`Demod2D`→`Somap`, `mpdecode_core.c:577-664`)
computes soft LLRs for *any* M=2^bps via max-star, and pilot-derived gain normalization
(`mean_amp`/`rx_amps`/`amp_est_mode`) is already threaded and already used by 16-QAM.
So reaching 64/256-QAM does **not** need a new demodulator or new LLR math — it needs: a
new **Gray-coded constellation table** (like `qam16[]` at `ofdm.c:79-87`) + its
normalization; extending the two `(bps==2)||(bps==4)` asserts + mod branches
(`ofdm.c:487-488,1198-1199`); a **new higher-rate LDPC H-matrix** (see below — none
above r≈0.8 exists); and **high-SNR amplitude/clip/EsNo calibration + OTA validation**
(the dominant real cost, because high-order QAM is fragile at the +19–28 dB it needs).
For the flat 9600 data port a **single-carrier QAM** mode is also worth considering
(OFDM's multipath benefit is unneeded on FM).

### Where a new mode plugs in — "the mode registry"

There is **no clean vtable/registry**. Modes are a fixed struct + duplicated C switch/if
lists. Adding one means a consistent edit across:

1. `modem/freedv/freedv_api.h` — new `FREEDV_MODE_*` enum + `_EN` macro (existing
   Rhizomatica-added enums: QAM16C2=25, DATAC16=23, DATAC17=24).
2. `modem/freedv/freedv_api.c` — add the `FDV_MODE_ACTIVE(...)`
   `freedv_ofdm_data_open()` line, plus ~6 other `FDV_MODE_ACTIVE` lists (lines
   ~129-137, 162-179, 259-267, 296-318, 506-514, 1111-1119).
3. `modem/freedv/freedv_700.c:195-204` — enum→string `strcpy`.
4. `modem/freedv/ofdm_mode.c` — new `else if (strcmp(mode,"..."))` block setting
   ns/np/tcp/ts/nc/bps/codename.
5. `modem/modem.c` — the `modem_mode_pool_t` struct (`:138-156`, 8 named
   `struct freedv *` slots), `init_mode_pool_locked()`, and **every** parallel switch/if
   list: `pooled_freedv_for_mode_locked()` (`:282-314`), `is_supported_split_mode`
   (`:178`), `is_payload_split_mode` (`:190`), `mode_name_from_enum` (`:200`),
   `bitrate_level_from_payload_mode` (`:341`).

**Trap:** the compiler will *not* catch a missing branch → silent mis-dispatch. And
**ARQ identifies the peer's mode partly by payload frame SIZE** ("mode-inference-by-size",
`ofdm_mode.c:139-141`) — a new mode's payload byte count must be **distinct from every
existing mode** or it will be mis-identified. The codebase already works around this:
datac17 chose np=61 specifically to differ from qam16c2. Pick your payload size
deliberately.

**Bandwidth ceiling:** everything is pinned to 8 kHz internal / 1500 Hz centre. A wide
FM mode wanting >~2.7 kHz audio bandwidth exceeds the 8 kHz Nyquist budget and forces
raising `config->fs` and reworking the resampler ratio (`audioio.c` `resample_ratio=6`;
`resampler.c` `FILT_FS 48000.0`) — a bigger change than adding a narrow OFDM mode.

**A truly non-FreeDV waveform** (e.g. single-carrier QAM) can't plug into
`generic_modem_t` — it hardcodes `struct freedv *` (`modem.h:34`). That path requires
introducing a real waveform abstraction and reworking `tx_thread`/`rx_thread` and
`send/receive_modulated_data`.

---

## 4a. Achievable data rates over FM — the numbers

*This section answers "expand DATAC to 12.5/25 kHz — what data rate vs VARA?" The model
below was derived from `ofdm.c:307-312` and cross-checked by independent recomputation; it
reproduces Mercury's own published figures exactly, so the projections rest on the real
code, not hand-waving.*

### The model (exact, not a heuristic)

For any codec2 OFDM data mode:

```
spectral efficiency  SE = η · bps · r · [ ts / (ts + tcp) ]      bits/s/Hz
net bitrate          = SE · W          (W = occupied audio bandwidth, Hz)
occupied bandwidth   = Nc / ts         (subcarrier spacing = 1/ts = 62.5 Hz for ts=0.016)
```

- `η = (Ns−1)/Ns` is **exactly** the pilot-symbol cadence, **not** a fudge factor. Every
  mode uses Ns=5 → **η = 0.80** (measured 0.792–0.798 on the real modes).
- `ts/(ts+tcp)` is the cyclic-prefix tax. HF uses tcp=6 ms; a flat FM channel can drop it
  to ~1 ms → factor 0.94.
- **Validation:** datac1 → 0.581 bps/Hz (× 1687 Hz = **980 bps**, matches published);
  qam16c2 → 1.520 bps/Hz (× 2062 Hz = **~3135 bps**, matches published ~3100). ✅

### Usable audio bandwidth is set by the FM channel, NOT the sample rate

The most important correction to the "8 → 12.5/25 kHz" framing: **`8` is the modem sample
rate (Fs=8000); `12.5`/`25` are the FM RF channel spacings — different domains.** FM
*expands* bandwidth (Carson's rule: `B_RF ≈ 2·(deviation + f_audio)`), so a voice channel
passes far less *audio* than its RF width:

| FM channel | Deviation | Usable **audio** BW (W) | What carries it | Fs needed |
|---|---|---|---|---|
| 12.5 kHz (narrow) | ~2.5 kHz | **~3.0 kHz** | mic path *or* data port | **8 kHz already suffices** |
| 25 kHz (wide) | ~5 kHz | **~4.5–4.8 kHz** (data-port roll-off, −6 dB @ 4.8 kHz — *not* the ~5.5 kHz Carson alone would allow) | **flat 9600 data port only** | **≥16 kHz** |

So you never inject 12.5 kHz of audio into a 12.5 kHz channel. And Fs=8000 already covers
a 12.5 kHz-channel mode — *except* that the resampler's hard-wired **3400 Hz LPF**
(`resampler.c:23`) caps audio at ~3.4 kHz regardless of Fs, so even narrow mode needs that
one filter widened.

### Projected net data rates (η=0.80, flat-channel CP factor 0.94)

| Waveform | SE (bps/Hz) | **12.5 kHz** (W≈3.0) | **25 kHz** (W≈4.8) | In codec2 **today**? | ~RF C/N to decode |
|---|---|---|---|---|---|
| QPSK, r½ (DATAC-class) | 0.75 | 2.3 kbps | 3.6 kbps | ✅ yes | ~2–4 dB |
| 16-QAM, r0.6 (qam16c2-class) | 1.81 | 5.4 kbps | 8.7 kbps | ✅ yes | ~10–12 dB |
| 16-QAM, r0.8 | 2.41 | **7.2 kbps** | **11.6 kbps** | ⚠️ 16-QAM ✅ + r≈0.8 LDPC exists (bind block sizes) | ~13–15 dB |
| 64-QAM, r0.75 | 3.39 | 10.2 kbps | 16.3 kbps | ❌ needs 64-QAM table + r0.75 H-matrix | ~18–21 dB |
| 64-QAM, r0.83 | 3.75 | **11.3 kbps** | **18.0 kbps** | ❌ 64-QAM + new LDPC | ~19–21 dB |
| 256-QAM, r0.83 | 5.0 | 15.0 kbps | 24.0 kbps | ❌ + per-carrier bit-loading (see below) | ~26–29 dB |
| **VARA FM (reference)** | — | **~12 kbps** (narrow) | **~25 kbps** (wide) | closed/commercial | — |

**Read this table as two tiers:**

- **With code that already exists** (QPSK / 16-QAM, r0.5–0.8): **~5–7 kbps narrow, ~9–12
  kbps wide.** That's already **5–12× DATAC-over-FM** and, on the wide channel, brushes
  VARA-FM-narrow territory — for the price of adding a mode, not new DSP.
- **To reach VARA-FM parity** (~12 narrow / ~25 wide) you need **64-QAM** (→ ~11 kbps in
  12.5 kHz ≈ VARA narrow) and **64/256-QAM on the wide channel** (→ ~18–24 kbps ≈ VARA
  wide). That is the genuinely new work.

### Five caveats that keep these numbers honest

1. **No FM SNR-improvement bonus.** Modulation index β = dev/W ≈ 0.83 (12.5) / 0.9 (25),
   both < 1 → *narrowband* FM → recovered audio SNR ≈ RF C/N. The 64/256-QAM rows need
   their full ~18–29 dB as **real RF carrier-to-noise**, not a gift from FM gain.
2. **Triangular FM noise → bit-loading required for wide mode.** FM post-detection noise
   rises +6 dB/octave; the flat 9600 port has no de-emphasis to cancel it, so SNR is
   ~15 dB *worse* at the top of a wide band than the bottom. Uniform 256-QAM across the
   band is unrealistic — a wideband flat-FM OFDM modem must do **per-subcarrier
   bit-loading** (heavy QAM low, light QAM high). Treat the 256-QAM row as best-case
   low-subcarrier, not a flat-band average.
3. **Capture cliff, not a graceful slope.** Below ~10–12 dB C/N, FM produces impulsive
   click/capture noise — non-Gaussian, not the AWGN the LDPC thresholds assume. The link
   is near-binary (works / falls off a cliff), which also limits how useful SNR-gradient
   gear-shifting is (§7 Phase 2).
4. **Hard `Nc ≤ 62` ceiling.** `pilotvalues[]` is a fixed 64-entry table
   (`assert` at `ofdm.c:372`) → max ~3875 Hz at 62.5 Hz spacing. A 25 kHz/wide mode needs
   ~77–88 carriers → **exceeds the cap**, forcing a longer pilot-sequence design (plus
   `MAX_UW_BITS=192`). Narrow (12.5 kHz, ~48 carriers) fits under the cap.
5. **LDPC block-length binding.** Coded bits/packet must exactly equal an available
   codeword length (datac1 → 8192, qam16c2 → 16200, both exact). Largest in-tree is
   n=16200, so faster/wider modes must **tile multiple codewords** → more latency + coarser
   packet-loss granularity, and tiling short codes forfeits coding gain the SNR column
   assumes.

### So is it "very easily expandable"? — half true

Widening bandwidth *is* mostly parametric: `Nc` is runtime-allocated (up to the 62 cap) and
Fs is derived at runtime inside `ofdm.c` (no fixed FFT — it's a per-carrier DFT). Your
instinct is right that the OFDM *widening* is not hard. But two things temper "very easy":
the **throughput that matches VARA comes from the constellation order (64-QAM), which
codec2 does not have**, and **wide mode** hits the Nc cap, the Fs=8000 plumbing
(`resampler.c` 6:1 ratio + 3400 Hz LPF, ~5 `FREEDV_FS_8000` sites in `modem.c`, the
`modem.c:507` guard), *and* the flat-9600-data-port hardware requirement. Concrete effort:

| Target | Effort | Why |
|---|---|---|
| **12.5 kHz 16-QAM mode** (~5–7 kbps) | **days** | 16-QAM fully built; fits 8 kHz Fs; widen the 3400 Hz LPF, pick Nc/Np to bind an LDPC codeword, thread the enum/pool/ARQ-size table with a *distinct* payload size, retune amplitude. Mechanical (~25 files), low DSP risk. |
| **64-QAM constellation** (~11–18 kbps) | **days coding + weeks calibration** | Add Gray table + extend 2 asserts/branches + import a higher-rate LDPC; the real cost is amplitude/phase robustness + OTA calibration at +19–28 dB. Soft-LLR & gain-normalization are already generic (reused from 16-QAM). |
| **25 kHz wide mode** (~18–24 kbps) | **weeks — months if the rig has no flat 9600 data port** | Fs≥16 kHz forces the resampler rewrite + LPF + all the 8000 hardcodes + audio retiming; Nc>62 forces a new pilot sequence; and it depends on external flat-data-port hardware the codec can't provide. |

### Quick-reference build ladder (narrow / 12.5 kHz, strong-signal max)

The pragmatic path to VARA-FM-narrow parity, cheapest first — each step is a superset of
the one above:

| Step | Net rate | Effort | vs VARA narrow (~12 kbps) |
|---|---|---|---|
| Stock `qam16c2` over FM (existing mode, no code change) | ~3.1 kbps | **zero** | 26% |
| Widen to ~3 kHz + trim CP (16-QAM r0.6) | 5.4 kbps | days | 45% |
| 16-QAM r0.8 (16-QAM built; ~r0.8 LDPC exists) | 7.2 kbps | + days | 60% |
| **64-QAM r0.83** | **11.3 kbps** | days coding + weeks calibration | **94%** |

Matching VARA-FM **wide** (~25 kbps) is a *separate, larger* effort — 25 kHz channel + the
flat 9600 data port + Fs≥16 kHz + a new pilot sequence (past the Nc≤62 cap) + 256-QAM with
per-subcarrier bit-loading → ~18–24 kbps, weeks-to-months. Both sides quoted here are
strong-signal maxima, so the comparison is apples-to-apples.

**Bottom line:** beating DATAC-over-FM by 5–12× is days of work on code that exists;
reaching genuine VARA-FM parity is a few weeks of DSP (64-QAM + new LDPC + calibration) for
the narrow channel, and weeks-to-months for the wide channel — but it is *achievable*, and
the numbers say a well-built MercuryFM lands right in VARA FM's ballpark.

---

## 5. VARA FM context

VARA FM (José Alberto Nieto Ros, EA5HVK / Rosmodem) is a **closed-source, commercial**
soundcard modem that carries data through an ordinary FM voice transceiver. Like VARA HF
it is adaptive multi-carrier **OFDM**, but it exploits the flat, high-SNR FM channel to
run **higher-order constellations and much wider bandwidth**:

- **Narrow mode**: audio via the radio's normal mic-in/speaker-out filtered voice path
  (works with a PC sound card). Can exceed **~12,000 bps**.
- **Wide mode**: requires the rear-panel flat **9600-baud "data port"**
  (discriminator-tap RX, direct-modulator TX). Can exceed **~25,000 bps** on a strong
  VHF path. Not all rigs (esp. HTs) have this.
- Wide/narrow stations negotiate and a wide station slows to match a narrow peer.
- By comparison VARA HF is ~180 bps free / ~8490 bps paid max in 2400 Hz SSB. So VARA FM
  is ~3–30× faster.
- **Licensing**: closed/commercial; free eval throttled (~566 bps "Level 1"); one-time
  purchase unlocks lifetime full speed.

Waveform-level parameters (constellations, subcarriers, FEC) are **not published**, so
any open modem is **clean-room and non-interoperable** with VARA. **An open, GPL,
FM-voice-channel data modem is a legitimate and currently unfilled niche.** Open building
blocks worth studying: Direwolf (AX.25 1200 AFSK / 9600 G3RUH), FX.25 / IL2P (FEC framing
for 9600, NinoTNC), and FreeDV/FreeDATA's OFDM data engine (which Mercury already
vendors). None matches VARA FM's adaptive-OFDM throughput today.

*(Cited throughput numbers are strong-signal maxima from community sources — wa8lmf.net,
masterscommunications VARA primer — not vendor spec sheets. Re-measure on your target
radios.)*

---

## 6. License — "taking over the GPL"

Mercury v2 is **GPL-3.0-or-later** (verbatim GPLv3 `LICENSE`; README §LICENSE; per-file
SPDX headers — **65** source files `GPL-3.0-or-later`, "Copyright (C) 2025/2026
Rhizomatica, Author: Rafael Diniz"; 73 of 392 `.c/.h` carry SPDX, the rest rely on the
umbrella `LICENSE`). A GPLv3-or-later fork is **fully permitted**. Obligations you
inherit:

1. **Stay GPL-3.0-or-later.** MercuryFM cannot be relicensed, closed, or dual-licensed
   under incompatible terms.
2. **Keep `LICENSE` verbatim** and keep the README license statement intact — the ~319
   files with no SPDX tag rely on that umbrella notice, so don't separate code from it.
3. **Preserve every existing copyright and per-file header** (GPL/LGPL/MIT/Unlicense) and
   every component license file: `LICENSE-freedv`, `common/iniparser/LICENSE`,
   `audioio/ffaudio/UNLICENSE`, `radio_io/hamlib-w64/COPYING.LIB.txt`.
4. **Add your own copyright ALONGSIDE (never replacing) Rhizomatica's**:
   `Copyright (C) 2026 <MercuryFM authors>`, keep the SPDX tag.
5. **Mark changed files** with a change note + date (GPLv3 §5a).
6. **Provide complete corresponding source** for any binary you distribute.
7. **Vendored LGPL FreeDV is fine**: LGPL-2.1 is GPL-compatible; LGPL §3 permits treating
   it under the GPL, so the combined binary is GPLv3 while `modem/freedv/` stays LGPL
   taken separately. (It also embeds BSD kiss_fft — attribute it.)
8. **Rename / don't imply endorsement.** "Mercury", "HERMES", "Rhizomatica", "FreeDV" are
   marks. MercuryFM is a correct rename; also update About/README/`mercury.ini`/binary
   name/docs URLs so the fork doesn't present as official upstream (GPLv3 §7 permits
   upstream to require removing their branding).

### ⚠️ Highest-priority license flag (found during audit — NOT in the brief)

**Vendored Mongoose is GPL-2.0-only.** `gui_interface/websocket/mongoose.c/.h` is
`SPDX: GPL-2.0-only or commercial` (Cesanta / Sergey Lyubka), compiled into the `-G`
WebSocket UI. **GPL-2.0-only does not cleanly combine with GPLv3** (no common license
version). Since Mercury's own code is GPL-3.0-*or-later*, a GPLv3 combined binary
statically linking GPLv2-only Mongoose is a **latent license conflict**. Resolve one of:
use Mongoose under its paid commercial license, make the `-G` UI **optional/separable**,
or **swap Mongoose for a GPLv3-compatible library**. (Verified in-tree at
`gui_interface/websocket/mongoose.h:18`. It may be an upstream oversight — worth raising
with them.)

> **✅ Decision (2026-07-04): MercuryFM distributes SOURCE ONLY — no official pre-built
> binaries.** Operators compile locally. Rationale: the GPLv2-only-vs-GPLv3 incompatibility
> is triggered by **conveying the linked binary**, not by shipping source. If MercuryFM
> never publishes a combined binary, and each user compiles their own copy for their own
> use (which is *not* "conveying" under the GPL), the conflict is never triggered. This is
> the standard, defensible mitigation. Conditions that come with this decision:
> - **No binary that links Mongoose may be published by the project** — that includes
>   release ZIPs, GitHub CI/release artifacts, **and Debian/`.deb` packages** (the upstream
>   `debian/` packaging must be disabled or built Mongoose-free).
> - **Keep the `-G` WebSocket UI (and Mongoose) build-time optional** so a Mongoose-free
>   binary *can* still be distributed if that's ever wanted (e.g. `make WITHOUT_UI=1`). A
>   binary without Mongoose is pure GPLv3-or-later and freely distributable.
> - **Warn downstream builders**: an operator who compiles and then *redistributes* their
>   own Mongoose-linked binary inherits the conflict. Say so in the build instructions.
> - This is an **interim** stance. The clean long-term fix is to drop Mongoose for a
>   GPLv3-compatible WebSocket library, or run the UI as a **separate process** over a
>   socket (so it's an independent program, not a linked combined work). *(Not legal
>   advice — if the project ever needs to ship binaries, resolve the licensing properly
>   first.)*

### Windows binary obligations

Hamlib ships as prebuilt DLLs (`radio_io/hamlib-w64/bin/*.dll`, LGPL-2.1). Windows
releases must reproduce `COPYING.LIB.txt` and keep dynamic linking (already the case) so
users can substitute Hamlib. Bundled `libgcc_s_seh-1.dll`/`libwinpthread-1.dll` (GCC
runtime exception) and `libusb` (LGPL) carry their own notice duties.

### Concrete checklist — files to add to the MercuryFM repo

- [x] `LICENSE` — verbatim GPLv3 (done; copied from upstream `5aa5b7b`).
- [x] `NOTICE.md` — attribution + third-party license inventory + Mongoose flag (done).
- [ ] Once code is actually vendored: keep `LICENSE-freedv`, `common/iniparser/LICENSE`,
      `audioio/ffaudio/UNLICENSE`, `radio_io/hamlib-w64/COPYING.LIB.txt` unmoved.
- [ ] Your `Copyright (C) 2026 …` line added to every file you modify, with a `Changes:`
      note + date (GPLv3 §5a).
- [ ] Updated `README.md` — new name, provenance ("forked from Rhizomatica Mercury @
      5aa5b7b"), non-endorsement statement, license section preserved.
- [ ] `debian/copyright` updated to add Mongoose and Hamlib entries (upstream currently
      lists only `*` = GPL-3+ and `modem/freedv/*` = LGPL-2.1).
- [x] A recorded decision on the Mongoose GPLv2 conflict → **source-only distribution;
      no project-published binaries; keep `-G` UI build-optional** (see §6 callout above).
- [ ] Rename binary, `mercury.ini`, and docs URLs.

---

## 7. Recommended incremental roadmap

**Phase 0 — Fork, build, validate the stack over FM as-is.** *(Low risk, high value.)*
Fork under GPLv3, rename, do the §6 license hygiene, get it building. Run **existing
DATAC/qam16c2 modes over a real FM rig** (mic path). Goal: prove the reusable 80%
end-to-end on FM — TNC connects, ARQ completes transfers, PTT keys, audio in/out works.
This validates the thesis and gives a working baseline before any DSP. Expect it to
*work but be spectrally wasteful* (~1 kbps class). Resolve the Mongoose question here.

**Phase 1 — Add an FM-tuned OFDM mode (parameter exercise).** *(Medium.)*
Clone the `qam16c2` template into a new `FREEDV_MODE_*` across the ~5 files in §4. Push
**tcp→~0, np down, rate up (0.6→0.8)**, keep bps=4 (16-QAM) initially. Choose a payload
byte size **distinct from all existing modes** (avoid the size-inference collision). Add
it to `broadcast.c`'s framesize map. Target: several kbps in the mic passband — clearly
beats DATAC, well short of VARA. Low DSP risk (engine already does 16-QAM); the risk is
boilerplate consistency + the payload-size collision.

**Phase 2 — Retune ARQ for FM.** *(Medium.)*
Re-tabulate `arq_mode_table[]` (`arq_protocol.c:75-87`) and rewrite the hard-coded
`FREEDV_MODE_DATAC*` cascade + per-mode SNR `#define`s in `select_best_mode()` /
`mode_snr_floor_db()`. **Re-measure timing** (frame_dur, ack_timeout, retry_interval) on
the FM channel — HF values assume ~3.9 s ACK-return and long preambles that FM doesn't
have; unmeasured, ARQ will be badly mistuned. Note the FM **capture-effect cliff** makes
SNR-gradient gear-shifting far less useful (channel is near-binary works/cliff) — the
ladder may collapse to 1–2 modes + a robust fallback; if the FM waveform is effectively
single-rate, **strip** the gear-shift subsystem rather than adapt it.

**Phase 3 — New high-order waveform + wide/9600 mode (to actually rival VARA FM).**
*(High — real R&D.)* Author 64-QAM + high-rate LDPC: Gray constellation map/demap,
amplitude-aware soft-LLR demapper, pilot-based gain normalization, new H-matrices. For
**wide mode**, raise `config->fs`, rework the resampler ratio (`resampler.c`,
`audioio.c`), and add support for the flat 9600 data-port audio path — consider a
**single-carrier QAM** mode here since OFDM's multipath benefit is moot on FM. This is
where a non-FreeDV waveform may need a real abstraction to replace `generic_modem_t`'s
hardcoded `struct freedv *`. Characterize/compensate FM pre-/de-emphasis and limiting
(they distort QAM amplitude references). This phase is where you approach 12–25 kbps and
where the schedule risk lives.

---

## 8. Open questions & risks

**DSP / waveform**
- Higher-order QAM is **new DSP, not a parameter tweak** — the biggest scope risk if
  underestimated. codec2 `ofdm.c` is QPSK-plus-one-16QAM-mode; 64-QAM needs new
  map/demap, amplitude-aware LLRs, gain normalization, new LDPC codes.
- **No drop-in reference exists**: DATAC is HF-tuned, FSK_LDPC is low-rate (~44 bps
  payload), Wenet/Horus are direct-RF not audio-subcarrier, BBFM is voice/RADE research.
  Real new-waveform work is on the critical path.
- **FM pre-emphasis/de-emphasis, limiting, and audio levels** distort QAM amplitude
  references — must be characterized/compensated on real radios.
- **Wide mode (25 kbps) needs the flat 9600 data port** (~6 kHz), which exceeds any
  codec2 audio mode's bandwidth and isn't on every radio. Mic-only design caps near
  ~12 kbps.
- **8 kHz / 1500 Hz internal pinning** limits audio bandwidth; wider modes force
  `config->fs` + resampler rework.

**Architecture / integration**
- **No waveform registry** — modes are duplicated C switch/if lists across `modem.c` +
  FreeDV; a missing branch mis-dispatches silently (compiler won't catch it).
- **Payload-size mode inference** (`ofdm_mode.c:139-141`): every new mode needs a unique
  payload byte count.
- **ARQ is only ~80% mode-agnostic**: `ARQ_CONTROL_MODE` is `#define`d to
  `FREEDV_MODE_DATAC16` and control frames assume its 14-byte compact layout
  (`arq_protocol.h:58-76`) — a different control-frame capacity forces revisiting the
  compact encoders/parsers.
- **`generic_modem_t` hardcodes `struct freedv *`** — a non-FreeDV waveform needs a new
  abstraction + `tx/rx_thread` rework.
- **This is a vendored FreeDV fork with non-upstream enums** (QAM16C2/DATAC15/16/17 =
  22–25); every mode you add is a local fork divergence — rebasing onto upstream FreeDV
  will conflict.

**Tuning / measurement**
- ARQ gear-shift **timing constants are HF-measured** and will mistune FM
  airtime/turnaround until re-measured.
- FM **capture cliff** may make the whole SNR gear-shift subsystem dead code to strip
  rather than adapt.
- Quoted VARA FM speeds and DATAC CP/pilot params are from docs/community pages —
  **re-measure on the actual target radios** before committing to a link budget.

**License**
- **Mongoose GPL-2.0-only vs GPLv3** is a latent conflict — must be resolved
  (replace / optional / commercial) before distributing binaries. See §6.
- Windows DLL (Hamlib/libgcc/libusb) notice obligations are currently undocumented
  in-repo.
- No Reticulum code exists — "Reticulum over the modem" needs an external RNode/interface
  layer; only the KISS/TCP framing primitive is present.

**Adoption**
- A clean-room FM waveform interoperates with **neither** VARA FM **nor** existing
  FreeDV/Mercury HF stations — adoption requires MercuryFM on both ends.

---

*These notes were produced from a file-level audit of Mercury @ `5aa5b7b`. Every path,
line number, and mode constant above was read out of that tree; RF/throughput figures for
VARA FM are community-sourced and should be re-measured on target hardware.*

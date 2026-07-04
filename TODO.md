# MercuryFM — TODO

Actionable task list. Companion to **[NOTES.md](NOTES.md)** (the engineering analysis
and data-rate roadmap) — this file is the checklist of concrete work.

Status legend: `[ ]` open · `[~]` in progress · `[x]` done.

---

## 🔴 P1 — Validation the offline loopback can't give (real hardware + ecosystem)

### OTA lab test bed — 2× RF.Guru hotspot (FM)

Everything so far (qam16fm decode, threshold, ARQ floor) is from a pure-AWGN
*software* loopback. It does **not** model the real FM audio path — so on-air testing on
actual FM hardware is the gating validation before qam16fm can be called production-ready.

- [ ] **Build the bench test bed: two stations, each a RF.Guru hotspot with its FM
      transceiver chip** (bench-coupled via attenuators / dummy loads / low power).
      **Two hotspots are required** (one per station).
- [ ] **12.5 kHz (narrow) channel** — run `qam16fm` station ↔ station: confirm ARQ
      connect + bidirectional transfer; log the modem's *real* reported SNR and compare to
      the loopback-derived numbers (FER=0 to ~13.6 dB, `ARQ_SNR_MIN_QAM16FM_DB=14.5`).
- [ ] **25 kHz (wide) channel** — requires the wide mode (see P2 "Wide / 25 kHz"), driven
      through the hotspot's flat / 9600-baud data path.
- [ ] **Characterize what the loopback omits** and re-tune from measurements:
      pre-/de-emphasis, audio limiting/compression, deviation, mic-path vs flat-data-port.
      Re-derive `amp_scale`, `EsNodB`, `ARQ_SNR_MIN_QAM16FM_DB`, and the `freedv_700.c`
      `snr_offset` (+9.0) against real hardware.
- [ ] **Capture metrics**: connect success rate, goodput (bytes/s), mode actually
      negotiated, packet loss vs. path attenuation. Record in `docs/OTA-*.md`.

### Winlink + Pat integration

- [ ] Drive the VARA-style TNC with **Pat** (cross-platform Winlink client) — MYCALL /
      LISTEN / CONNECT / BUFFER / data flow end-to-end over an ARQ link.
- [ ] Drive it with **Winlink Express** (Windows) too.
- [ ] ⚠️ mercuryfm currently reports itself as **VARA HF 4.9.0**; Winlink treats **VARA FM**
      as a *distinct* session type — cover any TNC commands / handshake details the FM
      session expects (verify in `data_interfaces/tcp_interfaces.c`).
- [ ] Round-trip test: send **and** receive a Winlink message + a file, both directions,
      through the ARQ link (over the OTA bed, or the fifo loopback).

### Windows compile test (Windows test station)

- [ ] Verify mercuryfm builds on the Windows test station. Two paths:
  - Native: **MSYS2 / mingw-w64** `make` in the repo.
  - Cross (from Linux/mac): `make windows` → `mercuryfm.exe` (uses
    `x86_64-w64-mingw32-gcc`).
- [ ] ⚠️ **Gotcha:** `radio_io/hamlib-w64/lib/*.a` and `bin/*.dll` are **gitignored** (to
      keep the repo lean), so a fresh clone can't link Hamlib on Windows. Restore them from
      upstream Mercury for a Hamlib-enabled build, **or** do a `WITHOUT_UI=1` + no-Hamlib
      compile check first to confirm the C compiles.
- [ ] ⚠️ The default Windows build links **Mongoose (GPL-2.0-only)** — fine for a local
      *compile test* (we distribute source only), but any *distributable* Windows binary
      must use `WITHOUT_UI=1`.
- [ ] Once green, add it to CI (a Windows GitHub Actions runner or a documented manual
      checklist on the test station).

---

## 🟠 P2 — DSP / waveform (from NOTES §4a, §7)

- [~] **Two-node ARQ negotiation loopback** (fifo backend, no radio) — prove the gear-shift
      actually selects `qam16fm`. *(In progress.)*
- [ ] Add `qam16fm` to the **`broadcast.c` framesize map** (`freedv_to_hermes_mode_map[]` /
      `hermes_broadcast_frame_size[]`) so broadcast mode can use it.
- [ ] **Wide / 25 kHz mode** (~18–24 kbps): raise `config->fs` to ≥16 kHz (rework the 6:1
      resampler + the 3400 Hz LPF + the ~5 `FREEDV_FS_8000` sites in `modem.c`), extend the
      `pilotvalues[]` table past the **Nc ≤ 62** cap, and support the flat 9600 data port.
- [ ] **64-QAM constellation** (NOTES §4b, ~11–18 kbps): add a Gray-coded table, extend the
      two `(bps==2)||(bps==4)` asserts + mod branches, add a higher-rate LDPC matrix,
      calibrate at +19–28 dB. (Soft-LLR + gain-normalization are already generic.)
- [ ] **Per-subcarrier bit-loading** for the wide flat-FM channel (FM's +6 dB/oct
      triangular noise means uniform high-order QAM across the band is unrealistic).
- [ ] **Retune the ARQ ladder for FM** (NOTES §7 Phase 2): FM is a capture cliff, not a
      gradient — the SNR-gradient gear-shift may collapse to 1–2 rungs + a robust fallback;
      re-measure ARQ timing (`ack_timeout` / `retry_interval`) for FM airtime.

---

## 🟡 P3 — Housekeeping / licensing / CI

- [ ] Resolve **Mongoose GPL-2.0-only** long-term (NOTES §6): replace with a
      GPLv3-compatible WebSocket lib, or run the `-G` UI as a separate process. *(Interim
      done: source-only distribution + `make WITHOUT_UI=1`.)*
- [ ] Update `debian/copyright` to add the Mongoose and Hamlib entries.
- [ ] CI (GitHub Actions): **macOS (clang)** + **linux/arm64 (container)** build checks —
      both pass locally today; wire them up. Add Windows once P1 is green.

---

## ✅ Done (this fork so far)

- [x] Fork Mercury v2 (`5aa5b7b`) under GPL-3.0-or-later; license/attribution hygiene.
- [x] Builds + runs on **macOS (clang/CoreAudio)** and **linux/arm64 (Apple `container`)**.
- [x] Rename binary → `mercuryfm`; `make WITHOUT_UI=1` (Mongoose-free, pure-GPLv3 binary).
- [x] First FM waveform **`qam16fm`** (16-QAM, rate-0.80, ~4.6 kbps) through the FreeDV +
      modem registry; enumerates and initializes.
- [x] `qam16fm` wired into the **ARQ gear-shift ladder** (top rung).
- [x] **Offline AWGN loopback**: clean decode = 0 coded errors; measured decode threshold
      ~13.6 dB; `amp_scale`/`EsNodB` derived, `ARQ_SNR_MIN_QAM16FM_DB=14.5` measured.

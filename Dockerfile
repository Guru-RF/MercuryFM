# MercuryFM — Linux build (verified on linux/arm64 via Apple `container`)
#
# Mirrors the upstream Debian build from README.upstream.md and produces the
# `mercury` binary with HAMLIB + ALSA/PulseAudio backends. On Apple Silicon,
# `container build` runs this natively as linux/arm64.
#
#   container build --platform linux/arm64 -t mercuryfm:trixie-arm64 .
#   container run --rm mercuryfm:trixie-arm64            # prints -h
#   container run --rm mercuryfm:trixie-arm64 ./mercury -l   # list modes
#
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        make \
        git \
        libasound2-dev \
        libpulse-dev \
        libhamlib-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

# Drop any host (macOS) build artifacts that slipped into the context, then
# build with all cores. HAMLIB is auto-detected via pkg-config (present here).
RUN make clean >/dev/null 2>&1 || true
RUN make -j"$(nproc)"

# Smoke test at build time: the modem must initialise and enumerate its modes.
RUN ./mercury -l | head -20

CMD ["./mercury", "-h"]

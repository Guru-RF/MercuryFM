# Two-node ARQ loopback test image: mercuryfm + PulseAudio (userspace, timer-clocked
# null-sink loopback — no kernel module, no /dev/snd). Build context = repo root.
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential pkg-config make git \
        libasound2-dev libpulse-dev libhamlib-dev \
        pulseaudio pulseaudio-utils python3 procps \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
RUN make clean >/dev/null 2>&1 || true
RUN make -j"$(nproc)"
CMD ["bash", "/work/run_pulse_loopback.sh"]

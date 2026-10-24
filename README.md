# echomuse-dot2-ref

A small, self-contained firmware patch for **EchoMuse on the Amazon Echo Dot 2** that adds a
**two-channel capture uplink**: `[beam mono | de-aliased ch8 playback reference]`. A controller
(such as a voice-assistant backend) can then run its own AEC with a clean reference instead of
relying on the device's seven-mic cancellation.

- Upstream: [wilbowes/EchoMuse](https://github.com/wilbowes/EchoMuse) (MIT)
- Base tag: **`v2.19.0-ea.1`** — the first release that contains the de-aliasing reference
  (`internal/aec/dealias.go`, commit `63c0fe9`). `v2.18.1` does not have it; back-porting is
  more risk than upgrading.
- Patch: [`patches/0001-ref-uplink-v2.19.0-ea.1.patch`](patches/0001-ref-uplink-v2.19.0-ea.1.patch)
  (3 files, +68 lines)
- Status: **installed on a device (2026-10-24)**. The controller sees the `ref_uplink` capability and
  receives 5120-byte 2ch blocks; live AEC quality validation is still in progress in the consuming
  controller (early runs show the reference arriving but cancellation is weak, so do not expect the
  offline 38 dB ERLE on day one).

## Why

EchoMuse already captures the playback loopback on ch8, but it is decimated from 48 kHz with no
anti-alias filter; feeding it straight to an external canceller gives poor echo return loss
(measured offline: 6.9 dB ERLE). With `dealias.clean()` the same reference reaches **38.3 dB
ERLE** offline. This patch ships that cleaned reference over the existing 80 ms uplink frames,
gated by a controller capability so old controllers keep receiving mono.

| | stock | patched |
|---|---|---|
| uplink | mono beam, ~31 KB/s | 2ch interleaved, ~64 KB/s |
| device AEC | 7-mic speex, ~19 % of a core | off when the controller asks; ref extraction ~1–2 % |
| controller | cannot AEC without a reference | gets clean, frame-aligned reference |

Feature gate: the controller announces `dot2_hw_ref` in `ack.features`; the device enables the
2ch uplink only then (`data.SetRefUplink`). **The same firmware is compatible in both
directions** — an old controller still gets mono, a new controller gets 2ch.

## Build

```bash
./scripts/build.sh                 # clones EchoMuse at EM_TAG, applies the patch, cross-compiles
# artifact: artifacts/server  (ARM 32-bit, sha256 printed)
```

Requirements: `git`, `docker` (OrbStack/colima/Docker Desktop), network access for the compiler
image (NDK + Go 1.24). The compiler image is defined by upstream (`device/compiler`) and is
built once.

## Install (A/B slots, auto-rollback)

The device keeps two firmware slots (`server_a` / `server_b`) and `start_server.sh` rolls back
automatically after 3 quick exits. Installation is a deliberate step:

```bash
adb devices                                     # confirm the Dot is attached
./scripts/install.sh artifacts/server --yes     # writes the INACTIVE slot, switches the symlink, restarts
./scripts/rollback.sh                           # switch back to the previous slot and restart
```

Read [`docs/INSTALL.md`](docs/INSTALL.md) first. It covers verification, the A/B mechanics and
what a failure looks like.

## Verify

On the device:

```
[aec] reference resync / att=... lines keep appearing
[data] Mic streaming started
```

On the controller: `ack.features` includes `dot2_hw_ref`; the adapter should present a 2-channel
`AudioFrame` (mic + reference) and enable AEC. Bandwidth roughly doubles to ~64 KB/s.

## License

MIT. The patch targets MIT-licensed EchoMuse; see [`NOTICE`](NOTICE).

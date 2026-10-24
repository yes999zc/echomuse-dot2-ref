# Design: two-channel capture uplink

## Problem

The Dot 2's microphone array is captured as 9 channels of S24 at 16 kHz. EchoMuse beams
channels 0–6 and exposes the playback loopback on ch8. That loopback is the 48 kHz speaker
output decimated 3:1 **without an anti-alias filter**, so it carries aliases of the playback
correlated with the echo path but not equal to it. Feeding it to an external canceller is poor:
offline measurement gave **6.9 dB ERLE** for the raw loopback and **38.3 dB** after
`dealias.clean()` (which reconstructs the reference from the output ring).

EchoMuse's own cancellers (`Canceller`) already compute that cleaned reference for the device's
seven-mic AEC. A controller cannot see it because the uplink carries only the beam mono.

## Patch

`patches/0001-ref-uplink-v2.19.0-ea.1.patch` (3 files, +68 lines):

1. **`device/internal/aec/aec.go`** — `Canceller.RefForUplink(rawRef)` returns one captured
   period's ch8 reference after `dealias.clean()`. It cancels nothing, so it is valid while the
   device's own AEC is disabled; the output ring it needs is fed by `WriteFar` on every speaker
   period regardless of that switch.
2. **`device/internal/client/data.go`** — a `refUplink` flag plus `SetRefUplink()`; in
   `streamMic` the 80 ms uplink frame becomes interleaved `[beam | ref]` S16 pairs instead of
   mono, with zero fill if the reference for that period is short. Bandwidth goes from ~31 KB/s
   to ~64 KB/s.
3. **`device/internal/client/control.go`** — after the handshake reads `ack.features`, it calls
   `data.SetRefUplink(HasFeature("dot2_hw_ref"))`. Feature-gated: an old controller still gets
   mono, and the controller can decide per connection.

## Why the base is `v2.19.0-ea.1`

`dealias.go` landed in upstream commit `63c0fe9` (2026-10-19); `v2.18.1` predates it and has no
de-aliased reference. Back-porting the de-alias ring into v2.18.1 would be a larger and riskier
change than building the first tag that contains it. The tag is an **EA** build; the version
string on the device will reflect that. `scripts/install.sh` keeps the previous slot intact for
rollback.

## Compatibility

| controller | uplink | device AEC |
|---|---|---|
| does not announce `dot2_hw_ref` | mono, unchanged | unchanged |
| announces `dot2_hw_ref` | 2ch interleaved | controller asked for reference; device canceller off |

No wire-protocol version bump: the frame size changes only under the feature flag, and both sides
agree on it in the handshake.

## Validation so far

- The patch applies cleanly on the pinned tag and the tree cross-compiles for `android/arm`
  (Go 1.24, upstream NDK image). Artifact: `artifacts/server` (~12.5 MB, 32-bit ARM ELF).
- A 2ch fake device was driven through the reference controller adapter: `aec_enabled=true`,
  `ref_active=true`, 167 frames in 13.4 s — the adapter side accepts mic+ref frames.
- Offline AEC: 6.9 dB (raw ch8) → 38.3 dB (de-aliased) ERLE on the same recording.
- **Not yet installed on hardware.** Expected device-side checks are in `docs/INSTALL.md`.

## Risks / non-goals

- EA firmware: upstream may change behaviour in this tag; the A/B rollback is the mitigation.
- Echo cancellation quality on the real device still depends on the controller's AEC taps, delay
  estimation and the reference alignment; expected ERLE is lower than the offline number.
- This patch does **not** add a per-block play-head/consumption report; that is a separate
  firmware feature.

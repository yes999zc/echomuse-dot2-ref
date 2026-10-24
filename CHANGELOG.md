# Changelog

## v0.1.0 — 2026-10-24

- First build of the two-channel capture uplink patch against EchoMuse `v2.19.0-ea.1`.
- Uplink becomes `[beam mono | de-aliased ch8 reference]`, gated by the controller's
  `dot2_hw_ref` capability so old controllers keep the mono wire format.
- `scripts/build.sh` (pinned tag, submodule, NDK compiler image, sha256),
  `scripts/install.sh` (inactive A/B slot, verify, auto-rollback), `scripts/rollback.sh`.
- Installed on `G090LF0964340RN6` (server_b, build `20261024-1911-dev`); the controller sees
  `ref_uplink` and 5120-byte 2ch blocks. server_a keeps the previous firmware.
- Known: the reference does not lift the acoustic cancellation ceiling of the Dot 2
  (measured ~14-18 dB linear), so a controller that also runs AEC gains little on top of
  the device AEC; see the bridge repo's `docs/aec-*.md`.

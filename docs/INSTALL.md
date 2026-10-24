# Install / verify / roll back

## Prerequisites

- A root-capable (`adb root`/`su`) Echo Dot 2 running EchoMuse, reachable over adb.
- The device's `start_server.sh` A/B layout: `/data/local/bin/server` is a symlink to
  `server_a` or `server_b`; the parent shell restarts it and rolls back after 3 exits shorter
  than 15 s.
- A controller that announces the `dot2_hw_ref` capability if you want the 2ch uplink (the
  patched firmware still works with old controllers; you just get mono).

## Build

```bash
./scripts/build.sh            # artifacts/server
```

## Install

```bash
DOT2_SERIAL=G090LF0964340RN6 ./scripts/install.sh artifacts/server --yes
```

What the script does:

1. reads the active slot and picks the **other** one (never overwrites the slot currently running);
2. `adb push` to `/data/local/tmp`, then a root `cp` into `/data/local/bin/server_<slot>`;
3. re-points `/data/local/bin/server` to the new slot;
4. kills the running server; `start_server.sh` starts the new binary and re-reads the symlink;
5. waits up to ~20 s for `Ready` / `Registered` in `/tmp/server.log`; on timeout it switches the
   symlink back and restarts, so a bad build cannot leave the Dot deaf.

## Verify

Device (`adb shell su -c 'cat /tmp/server.log'`):

```
PcmSpeaker initialised — silence stream running
[aec] enabled: frame=512 tail=...        # or reference resync lines when controller drives AEC
[data] Mic streaming started
Registered as <device-id>
```

Controller side:

- `ack.features` contains `dot2_hw_ref`;
- the adapter receives a 2-channel frame (beam + reference) and enables its AEC;
- uplink bandwidth ~64 KB/s (double the mono rate).

If the controller does not announce the feature you will see the normal mono uplink — that is
expected and proves the gate works backwards-compatibly.

## Roll back

```bash
./scripts/rollback.sh
```

This switches the symlink back to the previous slot and restarts. `start_server.sh` also rolls
back on its own after repeated fast crashes.

## Troubleshooting

| Symptom | Check |
|---|---|
| `adb shell` says `su: not found` | the device needs a root shell; `adb root` first or use `su -c` as this repo's scripts do |
| install stage hangs | another adb client (e.g. IDE) may hold the device; `adb kill-server` and retry |
| new firmware never reports `Ready` | the script rolls back automatically; inspect `/tmp/server.log` before it rotates |
| device reconnects but controller still sees mono | the controller did not announce `dot2_hw_ref`; check its handshake |
| audio pipeline reboots once | expected: the firmware restart re-initialises the speaker/DAC |

## Uninstall / back to stock

Switch the symlink to the slot holding the original firmware (`./scripts/rollback.sh` until the
active slot is the old one) and restart. Nothing outside `/data/local/bin/` is modified.


## Installed

2026-10-24: installed on `G090LF0964340RN6` (server_b), running build `20261024-1911-dev`.
Device logs `Registered as ...` and the controller's handshake sees `ref_uplink`; uplink blocks are
5120 bytes (2ch). server_a still holds the previous firmware for `./scripts/rollback.sh`.

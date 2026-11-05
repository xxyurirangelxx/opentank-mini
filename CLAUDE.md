# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An unofficial editor for the M-VAVE Tank Mini guitar pedal. It speaks a
proprietary SysEx protocol over USB MIDI or a custom BLE service. The protocol
was reverse-engineered from the vendor's M-EFCS app and verified against real
hardware; `docs/PROTOCOL.md` is the reference and `docs/VALIDATION.md` records
what was actually proven on the pedal.

## Commands

Flutter is not always on `PATH`. The scripts look for it in `$FLUTTER`, then
`PATH`, then `~/tools-sdk/flutter/bin/flutter`.

```bash
cd app
flutter pub get
flutter test                                   # full suite, no hardware needed
flutter test test/model/model_format_test.dart # one file
flutter test --plain-name "aceita AM4"         # one test by name
flutter analyze --fatal-infos
dart format lib test tool
flutter run -d windows
```

Full local CI (format, analyze, tests, doc/code cross-checks):

```bash
python tools/verify_repo.py            # everything
python tools/verify_repo.py --quick    # skip format/analyze/tests
```

Windows installer (builds the app, then packages with Inno Setup 6):

```bash
python tools/build_installer.py
python tools/build_installer.py --skip-build   # repackage only
```

Hardware probes (require the pedal connected; read-only unless flagged):

```bash
cd app
dart run tool/hil_probe.dart                 # identity, active preset, 21 slots
dart run tool/hil_probe.dart --names-test    # model names vs flash headers
dart run tool/hil_probe.dart --write-test    # writes a sacrificial slot, restores
dart run tool/hil_probe.dart --flash-test    # full model-flash backup/restore/audit
```

Research scripts live in `tools/research/` and use the Python venv at
`.venv-validation` (bleak, frida, pywinauto).

## Architecture

Layers, from the wire up:

```
platform/          MidiTransport (SysEx, 7-bit packing) | BleTransport (raw payload)
core/transport/    TankTransport interface (+ BleDisconnectHook)
core/device/       TankDevice — protocol operations over a transport
core/protocol/     message builders, checksum, 7-bit packing
core/model/        preset layout, bank format, AMP/CAB buffers, model flash, catalog
state/             TankController — draft/bank state, polling, reconnect
ui/                screens and widgets (provider)
```

**`core/` must not import Flutter.** `tool/hil_probe.dart` runs under plain
`dart run` to validate the production code against hardware; importing
`dart:ui` (even for `VoidCallback`) breaks that. Use `void Function()` instead.

`TankDevice` owns the conversation rules:

- **One request in flight.** The protocol has no correlation ID, so `_exchange`
  serializes everything through a queue. Concurrent calls used to fail with
  "requisição anterior em andamento".
- **Retry on timeout** (3 attempts) with a short drain window, because BLE
  drops notifications.
- **`lost` stream** fires when the transport reports a disconnect, so the UI
  can react instead of waiting out a timeout.

`TankController` keeps three states apart, and mixing them up causes bugs:

- `_draft` — what the UI shows and what is being edited.
- `_lastSent` — last state confirmed on the pedal; the diff base for `_push`.
- `_bank` — the 21 saved slots read from flash.

A 1-second poll (`pollInterval`) reads the active preset and adopts changes
made on the pedal itself. The pedal sends **nothing** spontaneously — this was
verified by listening for 20 s on both SysEx and short MIDI messages. The
vendor app polls at exactly 1.000 s, which is where the interval comes from.

## Protocol invariants that break the pedal if wrong

These are the ones that cost real debugging time. `docs/PROTOCOL.md` has the
full detail.

- **Checksum starts at index 5**, not 4: `(255 - sum(raw[5:-1])) % 256`.
- **Area matters.** `0x04` = presets, `0x05` = model buffer/flash. Reading
  `0x70xxxxxx` with area `0x04` silently returns zeros.
- **No commit for model flash.** A commit `F0` with `area 0x05` is ACKed and
  then discards the whole block. `writeModelFlash` erases sectors (`0x21`),
  writes (`0x22`), and verifies by read-back.
- **Model index is 0-based.** The max value in the 21 factory presets is
  `modelCount - 1` for all six blocks, and some presets have FX `0` with FX
  enabled. `0` is a real model, not "none".
- **Reads cap at 431 bytes, writes at 1015.**
- **BLE sends the payload raw** — no `F0`/`F7`, no 7-bit packing.
- **Model name tables** at `0x90000000` (AMP) and `0x80000000` (CAB) are 20
  records of 14 bytes and are **live**: writing a model updates the name
  immediately. Reading from an offset inside the block returns a mirrored copy
  with the first byte corrupted, so always read from the base address.
- FX, MOD, DLY and REV have **no name table** in the pedal; their names and
  parameter labels come from `core/model/model_catalog.dart` (taken from the
  vendor app).

## Testing

`test/support/fake_transport.dart` simulates the pedal: it takes a handler that
maps a request frame to a reply frame. Tests never need hardware. When adding a
protocol operation, add a fake-transport test with a real captured frame where
possible.

`tools/verify_repo.py` also cross-checks documentation against code: every
camelCase identifier in backticks in `docs/REQUIREMENTS.md` must exist in
`lib/` or `test/`, and `block_panel.dart` must not contain a hardcoded model
list.

## Build gotchas

- **Always build with `--no-tree-shake-icons`.** The icon subset is cached and
  the cache is not invalidated when only the UI changes; new icons then render
  as empty squares. `tools/build_installer.py` already passes the flag.
- Fonts are vendored in `app/assets/fonts/` (Roboto + full MaterialIcons) and
  declared in `pubspec.yaml`. `uses-material-design` is `false` on purpose.
- The Windows runner uses `opentank_mini.exe` as the binary name; the window
  title and version metadata are in `windows/runner/main.cpp` and `Runner.rc`.

## Conventions

- Code comments are in Portuguese **without accents** (ASCII only); user-facing
  strings are in Portuguese **with** correct accents.
- Comments explain *why*, not *what*.
- No new dependency without justification.

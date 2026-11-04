# OpenTank Mini

Unofficial, open-source desktop and mobile editor for the **M-VAVE Tank Mini**
guitar pedal. It replaces the vendor's M-EFCS app with something you can read,
fork and improve.

> Not affiliated with M-VAVE. Use at your own risk; keep a backup before writing
> anything to your pedal.

## What it does

- Read all 21 preset slots and the active preset
- Edit volume, effect chain order, block on/off, model and parameters
- Preview changes on the pedal in real time (RAM), before saving
- Save to the current slot, save to another slot, or swap two slots
- Import amplifier models (`.am2Data`) and cabinet IRs (`.wav`) and audition them
- Toggle bypass, loopback and the tuner
- Export and restore the whole preset bank (`.atkm`)

## Platforms

| Platform | USB MIDI | Bluetooth LE |
|---|---|---|
| Windows | yes | yes |
| Linux | yes | yes¹ |
| Android | — | yes |

¹ BLE on Linux needs BlueZ and is not yet exercised on real hardware; see
[VALIDATION.md](docs/VALIDATION.md).

## Status

The protocol layer is verified against hardware for reading, writing, swapping,
selecting and the global toggles. Model upload (AMP/CAB) is verified up to the
pedal's RAM buffer; permanent storage of models was **not** verified, because
the vendor app crashes before that step. Details and evidence live in
[docs/VALIDATION.md](docs/VALIDATION.md).

## Getting started

```bash
cd app
flutter pub get
flutter test          # 84 unit tests, no hardware needed
flutter run -d windows
```

Requires Flutter 3.47 or newer. On Windows you need the "Desktop development
with C++" workload from Visual Studio 2022 (MSVC, CMake and the Windows SDK).

## How it works

The app is split so that everything except the transport is testable without a
pedal:

```
app/lib/
  core/protocol/   framing, checksum and message builders
  core/model/      preset layout, bank format, AMP/CAB buffers
  core/io/         WAV reader and file pickers
  core/device/     TankDevice: high-level operations over a transport
  core/transport/  the Transport interface
  platform/        MIDI and BLE implementations
  state/           controller shared by the UI
  ui/              screens and widgets
```

The wire protocol is documented in [docs/PROTOCOL.md](docs/PROTOCOL.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Protocol findings backed by a capture
are especially welcome.

## License

[MIT](LICENSE).

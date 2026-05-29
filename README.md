# OpenWhoop

Open-source, local-first client for the **WHOOP 4.0** band: read your own biometrics over
Bluetooth LE and keep your own data local. A native iOS app (collect → decode → store → sync)
backed by an optional self-hosted server. Decoding is schema-driven (`protocol/whoop_protocol.json`)
and shared by the phone and the server so they never drift.

> **Disclaimer.** This is an independent, unofficial project. It is **not affiliated with,
> endorsed by, or sponsored by WHOOP, Inc.** "WHOOP" is a trademark of its respective owner and
> is used here only descriptively, to identify the hardware this software interoperates with.
> The project is the result of independent reverse-engineering for interoperability and is
> provided **for personal and educational use** with **your own device and your own data**, at
> your own risk. No warranty — see [`LICENSE`](LICENSE).
>
> **Not a medical device.** Heart rate, HRV, recovery, strain, sleep, SpO₂, and related
> outputs are approximations from published methods, are **not** clinically validated, and are
> **not medical advice**. Do not use them for diagnosis or treatment.

## What's here

| Path | What it is |
|---|---|
| `protocol/` | The canonical decode schema — single source of truth. |
| `Packages/WhoopProtocol/` | The Swift decoder (ports the Python reference; cross-language parity-tested). |
| `Packages/WhoopStore/` | Local on-device store (GRDB). |
| `ios/` | The SwiftUI + CoreBluetooth app. |
| `server/` | Optional self-hosted datastore + ingest (FastAPI + TimescaleDB) and the `whoop-protocol` Python package. |
| `dashboard/` | A Mac BLE reference/inspection tool used during development. |
| `re/`, `FINDINGS.md` | Reverse-engineering scripts and the protocol reference write-up. |
| `docs/` | Design specs and implementation plans. |

Start with `docs/specs/2026-05-23-openwhoop-ios-app-design.md` and `FINDINGS.md`.

## Supported hardware

WHOOP 4.0 only. Other generations use different BLE protocols and are not supported.

## Building & running

- **iOS app** — open `ios/` (project generated via XcodeGen / SwiftPM). Copy
  `ios/OpenWhoop/Config/Secrets.example.xcconfig` → `Secrets.xcconfig` and fill in your own
  server URL + API key (the real file is gitignored).
- **Server** — see [`server/README.md`](server/README.md): `cp .env.example .env`, set
  `DATA_ROOT`, then `docker compose up -d --build`.
- **RE scripts (`re/`)** — these depend on third-party clones that are intentionally **not**
  bundled (see below and `re/README.md`); copy `re/device_local.example.py` →
  `re/device_local.py` with your own device identifiers. They are not needed to build the app.

The decompiled vendor app and the third-party clones used during reverse-engineering are **not**
included in this repository (they are gitignored). The committed code is original work plus the
protocol knowledge documented in `FINDINGS.md`.

## Credits & provenance

This work builds on prior community reverse-engineering of the WHOOP protocol. The framing,
command, and event identifiers in `protocol/whoop_protocol.json` were derived from independent
reverse-engineering and from these projects — thanks to their authors:

- [`jogolden/whoomp`](https://github.com/jogolden/whoomp) — the authoritative
  firmware-extracted protocol reference (CRC, framing, packet types).
- [`christianmeurer/whoop-reader`](https://github.com/christianmeurer/whoop-reader) — earlier
  BLE exploration.

## License

[MIT](LICENSE) © 2026 Johnathan Middleton. See [`NOTICE`](NOTICE) for attributions and the
provenance of the protocol facts and analysis methods.

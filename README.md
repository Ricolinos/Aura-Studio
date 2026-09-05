# Aura Studio

A companion app that installs custom firmware on an iPod Classic 6G (2008) and manages its music, photo and video library — no Terminal, no technical knowledge required.

## What is Aura Studio

The iPod Classic doesn't expose a usable file-transfer mode: installing an alternative firmware means speaking the device's DFU protocol by hand, and syncing music means building the indexed database the firmware expects. Aura Studio does both from a graphical interface.

It installs and switches between three sibling firmwares built on Rockbox — [**Aura**](https://github.com/Ricolinos/Aura-Firmware), [**Metro**](https://github.com/Ricolinos/Metro-Aura) and [**moonlit**](https://github.com/Ricolinos/moonlit-aura) — each with its own visual language, published as separate open-source repositories. Aura Studio never reads their source trees directly: it consumes their releases only, over the GitHub API. The full interface contract between this app and the firmwares is [`CONTRATO-firmware-studio.md`](CONTRATO-firmware-studio.md).

## Platforms

- **macOS** 14.4 or later, Apple Silicon (native, universal binary).
- **Windows** 10 (2004+) / 11, x64 and ARM64.

Both are the same app, kept at feature parity — see [`studio/windows/docs/ESTADO-PORT.md`](studio/windows/docs/ESTADO-PORT.md) for the exact state of the Windows port.

## Features

### Installer

Guides you from a stock iPod to a working install: connect over USB, automatic detection, entering DFU mode (the app shows the exact button combo — hold **SELECT + MENU** together for about 12 seconds, until the screen goes black — and detects DFU automatically once you're in it), flashing the bootloader, formatting, and copying the firmware. You can install any of the three families, switch between them from Settings without reflashing (an inactive firmware just sleeps on disk), and restore the original Apple firmware at any time. A separate **"Update bootloader"** flow re-flashes only the NOR bootloader chip when a firmware release needs a newer one — no disk formatting, no file copy, your library and settings untouched.

Every privileged step (pausing a macOS service, formatting the disk, entering DFU) is explained on its own screen *before* the native permission dialog appears — you're told what's about to happen and why, never asked to open a terminal.

### Updates

Aura Studio checks each firmware's GitHub releases (cached for a day, or refreshed on demand) and installs the newest one it finds when you install from scratch or update, always verifying every downloaded file's checksum before writing anything to your iPod. If a download or verification fails for any reason, it falls back to the version already embedded in the app and says so — it never leaves you without a working install path. A personal GitHub token is optional and only raises the API rate limit; it's never required to check for or install updates.

### Library

Syncs your music (in the folder layout you choose — Artist/Album, Album, or Artist), photos, videos and playlists to the iPod, transferring only what changed. Cover art is fetched from MusicBrainz, the Cover Art Archive, Deezer and fanart.tv, scored and picked automatically (front covers and official releases first); artist photos come from fanart.tv (with your own free API key) or Deezer. Lyrics are fetched from LRCLIB and written as sidecar files the firmware reads natively. Ratings, favorites, and photo/video categories carry over across syncs, and the songs table has fully customizable columns — pick exactly what you want to see and sort by.

### Themes builder

Extras → Themes lets you install, activate, remove and build theme packages (fonts, icons, palette, backgrounds) for your iPod, on top of the built-in "Aura" theme and Light/Dark. Aura Studio is a **builder, not a distributor**: a theme built from restricted-license assets already on your own Mac (like Apple's SF Pro or SF Symbols) is marked non-redistributable, and its export/share option is disabled with an on-screen explanation — nothing with a restrictive license is ever bundled with the app or uploaded anywhere.

### Device

Your iPod gets a name that's remembered on the device itself, the clock is synced from your computer automatically on every connection and after every sync — with any of the three firmwares installed — and settings shared across all three firmwares (lock, brightness, sleep timer, language, appearance) carry over when you switch, so switching firmware never means reconfiguring from scratch.

## Tutorials

Step-by-step walkthroughs with real screenshots from the macOS app, in [`docs/readme/`](docs/readme/):

1. **Install from scratch** — connect your iPod, let Aura Studio detect it, enter DFU with the button combo it shows you, and let it flash and copy the firmware.
2. **Update a firmware** — pick up a new release without starting over.
3. **Switch firmware family** — move between Aura, Metro and moonlit on the same iPod.
4. **Update the bootloader** — the one flow that goes through DFU without touching your library.
5. **Sync your library** — bring your music, photos and videos onto the device.
6. **Restore the original Apple firmware** — undo everything, cleanly.

*(Screenshots for this section are being captured against a physical iPod and will land here shortly — the flows above are otherwise fully described under Features.)*

## Why not sandboxed / not in the App Store

Aura Studio talks directly to IOKit/DiskArbitration to detect and unmount the iPod, and runs the embedded `mks5lboot` binary for DFU flashing — exactly what the App Store sandbox restricts. It's distributed outside the App Store, signed locally.

## Security

Every operation that touches your disk or asks for elevated privileges goes through native macOS/Windows paths — you're never asked to use a terminal — with its own explanation screen before the native authorization dialog, and the iPod's disk is identified by multiple independent criteria (never a hardcoded identifier), re-checked immediately before any destructive operation.

## Project status

Builds and passes its test suite with real `xcodebuild` (not just the faster `swift build`/`swift test` path) on macOS, and with `dotnet build`/`dotnet test` on Windows, producing an app with the firmware artifacts embedded and checksum-verified. See [`DECISIONS.md`](DECISIONS.md) for what has and hasn't been verified against physical hardware.

## Building from source

macOS:

```bash
brew install xcodegen gh
scripts/fetch-firmware.sh
cd studio/AuraStudio
xcodegen generate
open AuraStudio.xcodeproj
```

Windows: see [`studio/windows/docs/ESTADO-PORT.md`](studio/windows/docs/ESTADO-PORT.md) and `studio/windows/scripts/`.

Full detail for both platforms in [`docs/guia-desarrollo.md`](docs/guia-desarrollo.md).

## Roadmap

- More app languages (Aura Studio's own interface is Spanish-only today).
- Japanese character support in the firmwares (kana and jōyō kanji, via a glyph cache).

## Key documents

- [`docs/guia-instalacion.md`](docs/guia-instalacion.md) — end-user guide: installing a firmware and syncing your library.
- [`docs/guia-desarrollo.md`](docs/guia-desarrollo.md) — building and testing this repository.
- [`CONTRATO-firmware-studio.md`](CONTRATO-firmware-studio.md) — the contract with the firmware repositories.
- [`CONTRATO-formato-tema.md`](CONTRATO-formato-tema.md) — the installable theme package format, shared with the firmwares.
- [`DECISIONS.md`](DECISIONS.md) — decision log since the repositories were split apart (ST-001+).
- [`DECISIONS-ARCHIVE.md`](DECISIONS-ARCHIVE.md) — the frozen, read-only log of the original monorepo (D-001…D-285), shared with `Aura-Firmware`.

## License, credits and trademarks

Aura Studio is distributed free of charge. Its own source code is proprietary — see [`LICENSE`](LICENSE). The firmware binaries it embeds and installs (`rockbox.ipod`, `rockbox.zip`, `bootloader-ipod6g.ipod`, `mks5lboot`) are forks of [Rockbox](https://www.rockbox.org), released under the GNU General Public License v2 and distributed here as an aggregation within this closed application (see `CONTRATO-firmware-studio.md` §B and the in-app "Licenses" screen for full compliance detail and where to get the corresponding source).

Created and maintained by **Ricolinos**. Rockbox is the work of the Rockbox community; this project is not affiliated with, endorsed by, or sponsored by Rockbox, Apple Inc., Microsoft Corporation or moonlit.market.

iPod is a trademark of Apple Inc. Zune, Metro and Windows are trademarks of Microsoft Corporation. The visual languages of the firmwares Aura Studio installs are original interpretations inspired by those designs and include no proprietary assets (no SF Pro, SF Symbols, Segoe UI or other proprietary fonts or icons) — except in a personal theme you build yourself from assets already on your own machine, which Aura Studio never redistributes (see Themes builder above).

Provided "as is", without warranty of any kind. Flashing firmware to a device is done at your own risk.

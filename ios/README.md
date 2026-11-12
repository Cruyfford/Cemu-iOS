# Cemu for iOS

A native iOS/iPadOS port of [Cemu](https://github.com/cemu-project/Cemu), the Wii U emulator.

- Cemu core built for arm64 iOS with the native **Metal** renderer
- Cemu's **ARM64 PowerPC recompiler**, running from a dual-mapped (RX + RW) JIT arena
- **JIT via StikDebug**, including the iOS 26 / TXM protocol (`universal.js`)
- SwiftUI frontend: game library with icons, settings, in-game menu
- Movable/resizable **touch controls** (Wii U GamePad layout) and **MFi / Xbox / PlayStation controllers**
- **GamePad screen**: TV only, GamePad only, or TV + GamePad (PiP in landscape, stacked in portrait), touch input on the GamePad screen

## Install

1. Download `Cemu-iOS.ipa` from the [nightly release](../../releases/tag/nightly).
2. Install with SideStore, AltStore or TrollStore.
3. Install [StikDebug](https://github.com/StikDebug/StikDebug) for JIT. Open Cemu — it asks StikDebug to attach automatically (or tap **Enable JIT**).

Without JIT Cemu runs on the interpreter, which is far too slow for games.

## Games and keys

- Put games in **Files › On My iPhone › Cemu › games** (or import with **+**): `.wua`, `.wux`, `.wud`, `.rpx`, NUS folders, or extracted game folders. Updates and DLC go in the same folder.
- Encrypted dumps (WUD/WUX/NUS) need `keys.txt` — import it in **Settings › Files**.
- Saves and system files live in **Cemu › mlc01**.

## Notes

- Built entitlements: `extended-virtual-addressing` (Cemu reserves 4 GB of address space for the Wii U memory) and `increased-memory-limit`. Signing services that strip them may cause the app to fail to start a game.
- The first run of a game builds shader caches and will stutter.

## Building

The workflow in `.github/workflows/ios.yml` builds everything on a macOS runner:

1. `vcpkg` dependencies for `arm64-ios` (triplet in `ios/triplets`)
2. Cemu core as the `CemuIOSCore` static library (`-DCEMU_IOS=ON`, see `src/ios`)
3. The Xcode app from `ios/App/project.yml` (XcodeGen), packaged as an unsigned IPA

## Licence

Cemu is licensed under the Mozilla Public License 2.0; this port keeps that licence.

# MacNotchPlayer

A macOS menu-bar agent that turns the MacBook notch into a media player.
Hover the notch and a player slides out with a smooth animation, showing the
**currently playing track from any app** (Apple Music, Spotify, browsers, …),
playback controls, and a scrubber. Styled with **macOS 26 Liquid Glass**.

![player](docs/preview.png)

## Features

- **Liquid Glass UI** (macOS 26): glass transport buttons, glass volume pill,
  continuous-rounded surfaces; sliders stay neutral.
- **Album-colored buttons** (optional): transport buttons take a color sampled
  from the artwork, applied immediately on hover. Toggle in Settings.
- **Transport**: play/pause, next, previous, **shuffle**, **repeat** (cycles
  off → track → playlist).
- **Scrubber** with seek; tap the right time to toggle remaining/total.
- **System volume** slider (responsive drag, throttled apply).
- **Source-app icon**; click the artwork to open the playing app.
- **Marquee** scrolling for long titles.
- **Compact indicator**: album-art thumbnail + animated equalizer beside the
  notch while playing (Dynamic-Island style).
- **Auto-peek**: a compact **mini** card (art + title + artist only) briefly
  slides out when the track changes; hovering expands it to the full player.
- **English / Ukrainian** UI, switchable live.
- **Settings**: a gear button in the player (and ⌘, from the menu) opens a
  window to pick the language and toggle every behavior + Launch-at-Login.

> Requires macOS 26 (Tahoe) for the Liquid Glass design.

## How it works

- **System-wide now playing** is read via [`mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter)
  (BSD-3). On macOS 15.4+/26 Apple locked the private MediaRemote framework for
  un-entitled apps; the adapter works around this by running a bundled Perl
  script through `/usr/bin/perl` (an Apple-entitled binary) that loads a helper
  framework and streams JSON updates. No SIP changes, no special entitlements.
- **The notch UI / animation** uses [`DynamicNotchKit`](https://github.com/MrKai77/DynamicNotchKit)
  (MIT), vendored under `vendor/`. The notch lives in an invisible *compact*
  state; hovering it (`isHovering`) drives the `expand()` transition.

## Layout

```
Sources/MacNotchPlayer/
  App.swift                 # @main, MenuBarExtra, SMAppService login item
  NowPlayingController.swift # perl stream + parse + seek/send commands
  NotchController.swift      # DynamicNotch + hover → expand/compact
  PlayerView.swift           # SwiftUI player (artwork, controls, scrubber)
  Models.swift               # NowPlaying model + JSON merge/parse
Resources/                   # bundled mediaremote-adapter.pl + framework
vendor/                      # mediaremote-adapter source, DynamicNotchKit
scripts/                     # build_app.sh, make_dmg.sh, install.sh
```

## Build / package / install

```bash
./scripts/build_app.sh   # compile, assemble build/MacNotchPlayer.app, codesign
./scripts/make_dmg.sh    # build/MacNotchPlayer.dmg (drag-to-/Applications)
./scripts/install.sh     # copy to /Applications and launch
```

Override the signing identity with `SIGN_ID="…" ./scripts/build_app.sh`.

## Usage

After install, a `♫` icon appears in the menu bar and the app auto-starts at
login. **Hover the notch** to reveal the player. The menu offers play/pause,
next/previous, a Launch-at-Login toggle, and Quit.

## Licenses

- MediaRemoteAdapter © 2025 Jonas van den Berg — BSD 3-Clause
- DynamicNotchKit © Kai Azim — MIT

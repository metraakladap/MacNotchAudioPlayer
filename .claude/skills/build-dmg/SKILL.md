---
name: build-dmg
description: Build and package the distributable MacNotchPlayer.dmg for this project. ALWAYS run this after making code changes to MacNotchPlayer, so build/MacNotchPlayer.dmg always reflects the latest source. Use when asked to build/package/ship the DMG, or whenever a change is finished and verified.
---

# Build the updated DMG

Standing instruction for this repo: **after any code change, rebuild the DMG** so
`build/MacNotchPlayer.dmg` is never stale. Run this skill at the end of a change
(after verifying), or whenever the user asks to build/package/ship.

## Steps

Run both scripts from the project root, in order:

```bash
./scripts/build_app.sh   # swift build -c release → assemble build/MacNotchPlayer.app → codesign
./scripts/make_dmg.sh    # package build/MacNotchPlayer.app → build/MacNotchPlayer.dmg
```

`make_dmg.sh` requires the `.app` to exist, so always run `build_app.sh` first.

## Confirm it actually rebuilt

Don't trust "Done" alone — check the DMG timestamp is fresh:

```bash
stat -f "%Sm %N" build/MacNotchPlayer.dmg
```

The modified time should be ~now. Report the path and size to the user.

## Notes

- **Signing identity**: defaults to `Apple Development: artpadan@gmail.com (BPF43W7H5B)`.
  This is a development cert, **not notarized** — so on other Macs Gatekeeper
  blocks it until the user right-clicks → Open (or removes the quarantine attr).
  Override with `SIGN_ID="…" ./scripts/build_app.sh` if a Developer ID cert is set up.
- **Architecture**: the binary is `arm64`-only → runs on Apple Silicon Macs only,
  not Intel.
- If the app is running while you rebuild, that's fine; to test the new build,
  `pkill -f "MacNotchPlayer.app/Contents/MacOS"` then `open build/MacNotchPlayer.app`.
- Build is fast (`swift build` is incremental); just always run it — never hand the
  user an old DMG.

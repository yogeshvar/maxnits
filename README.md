# MaxNits ☀️

Free, open-source command-line tool that unlocks the full brightness of your MacBook Pro's XDR display — up to ~1000 nits for everyday (SDR) use instead of Apple's default 600-nit limit.

No purchases, no subscriptions, no telemetry, no menu bar icon. MIT licensed.

## Why MaxNits?

Apple's MacBook Pro (14"/16", M1 and later) has a Liquid Retina XDR display capable of 1000 nits sustained (1600 nits peak for HDR), but macOS caps normal use at 600 nits. Paid apps exist that lift this cap — MaxNits does it for free.

- **⌨️ CLI-only** — no menu bar icon, no dropdown. `maxnits on`, and you're done.
- **✨ Center-screen HUD** — a native-feeling bezel pops up in the middle of the screen when the boost level changes, so you always know what's happening.
- Runs as a small background daemon; settings persist across restarts.

## How it works

MaxNits uses only public macOS APIs — no gamma-table hacks, which modern macOS silently clamps to normal SDR range anyway.

1. **EDR activation** — a 1×1 pixel invisible overlay window renders a pixel brighter than SDR white using Metal (`CAMetalLayer` with `wantsExtendedDynamicRangeContent`). This makes macOS switch the display into Extended Dynamic Range mode, unlocking brightness headroom above the SDR ceiling.
2. **Multiply-compositing boost** — a second, fullscreen, click-through overlay window renders a constant color above 1.0 with its layer's `compositingFilter` set to `"multiply"`. The WindowServer scales everything beneath it by that value before it reaches the (now EDR-enabled) display, up to the panel's real headroom.

Both overlays are just windows owned by a small background daemon process — quitting it (`maxnits quit`) or a crash instantly removes them and returns the display to normal.

## Requirements

- Best on a Liquid Retina XDR display: MacBook Pro 14"/16" (M1 Pro/Max or later), Pro Display XDR, or other EDR-capable displays.
- Works with reduced effect on some non-XDR Macs too (recent MacBook Airs report ~2× EDR headroom).
- macOS 13 Ventura or later.

## Install

### Homebrew

```sh
brew tap yogeshvar/maxnits
brew install maxnits
```

This builds MaxNits from source on your machine (there's no precompiled bottle) — takes about a minute.

### From source

Requires Xcode Command Line Tools:

```sh
git clone https://github.com/yogeshvar/maxnits.git
cd maxnits
make install    # builds dist/MaxNits.app and symlinks `maxnits` onto your PATH
```

`make install` puts the symlink at `$HOME/.local/bin/maxnits` by default (make sure that's on your `PATH`); pass `PREFIX=/usr/local` (may need `sudo`) to install system-wide instead.

## Usage

MaxNits runs as a small background daemon that holds the overlay windows; you control it with a normal terminal command, which starts the daemon automatically the first time you need it.

```sh
maxnits on              # turn the boost on
maxnits off              # turn the boost off
maxnits set 70           # set the boost to a specific level (0-100)
maxnits up [amount]      # increase the boost (default 10%), turning it on if it was off
maxnits down [amount]    # decrease the boost (default 10%)
maxnits status            # show whether it's running and its current level
maxnits quit              # stop the background daemon entirely
maxnits enable-login      # start MaxNits automatically at login
maxnits disable-login     # stop starting it automatically
```

Diagnostics, no daemon required:

```sh
maxnits --status   # print raw EDR headroom per display
maxnits --test     # 6-second boost self-test
```

## Caveats

- **Battery & heat**: 1000 nits draws significantly more power than 600.
- **Auto-brightness**: macOS may still dim the display based on ambient light or thermal pressure; MaxNits works on top of whatever the OS allows at that moment.
- **HDR content**: while boosted, true HDR content has less headroom left to stand out.
- After `maxnits quit` or `maxnits off`, the reported EDR headroom (`maxnits --status`) takes a few seconds to visibly decay back to baseline — that's normal WindowServer behavior, not a leak.

## Credits

The EDR + multiply-overlay technique was pioneered by apps like [BrightIntosh](https://github.com/niklasr22/BrightIntosh) (GPL) and used in [FullBright](https://fullbright.app) and [BetterDisplay](https://github.com/waydabber/BetterDisplay)'s "Software Metal Upscaling" mode. MaxNits is an independent, from-scratch MIT-licensed implementation of the same idea.

## License

[MIT](LICENSE)

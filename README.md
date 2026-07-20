# MaxNits ☀️

Free, open-source menu bar app that unlocks the full brightness of your MacBook Pro's XDR display — up to ~1000 nits for everyday (SDR) use instead of Apple's default 600-nit limit.

No purchases, no subscriptions, no telemetry. MIT licensed.

## Why MaxNits?

Apple's MacBook Pro (14"/16", M1 and later) has a Liquid Retina XDR display capable of 1000 nits sustained (1600 nits peak for HDR), but macOS caps normal use at 600 nits. Paid apps exist that lift this cap — MaxNits does it for free.

- **☀️ Minimal** — one toggle, one slider with a live percentage readout, nothing else to learn.
- **⌨️ Global shortcuts** — ⌘F2 brightens, ⌘F1 dims, from anywhere, even with the menu closed.
- **✨ Center-screen HUD** — a native-feeling bezel pops up in the middle of the screen when the boost level changes, so you always know what's happening.
- Settings persist across restarts.

## How it works

MaxNits uses only public macOS APIs — no gamma-table hacks, which modern macOS silently clamps to normal SDR range anyway.

1. **EDR activation** — a 1×1 pixel invisible overlay window renders a pixel brighter than SDR white using Metal (`CAMetalLayer` with `wantsExtendedDynamicRangeContent`). This makes macOS switch the display into Extended Dynamic Range mode, unlocking brightness headroom above the SDR ceiling.
2. **Multiply-compositing boost** — a second, fullscreen, click-through overlay window renders a constant color above 1.0 with its layer's `compositingFilter` set to `"multiply"`. The WindowServer scales everything beneath it by that value before it reaches the (now EDR-enabled) display, up to the panel's real headroom.

Both overlays are just windows owned by MaxNits — quitting or crashing the app instantly removes them and returns the display to normal.

## Requirements

- Best on a Liquid Retina XDR display: MacBook Pro 14"/16" (M1 Pro/Max or later), Pro Display XDR, or other EDR-capable displays.
- Works with reduced effect on some non-XDR Macs too (recent MacBook Airs report ~2× EDR headroom).
- macOS 13 Ventura or later.

## Install

Build from source (requires Xcode Command Line Tools):

```sh
git clone https://github.com/yogeshvar/maxnits.git
cd maxnits
make app        # builds dist/MaxNits.app
make run        # builds and launches
```

Then optionally drag `dist/MaxNits.app` into `/Applications`.

## Usage

- Click the ☀️ icon in the menu bar.
- **Boost Brightness** toggles the extra brightness on/off.
- The slider controls how much of the available headroom to use, with the current percentage shown next to it.
- **⌘F2** increases the boost 10% at a time (turning it on if it was off); **⌘F1** decreases it — works system-wide, no need to open the menu.
- **Launch at Login** keeps it running.

If ⌘F1/⌘F2 don't do anything, something else on your Mac (another app, or a system shortcut like "Turn display mirroring on/off" under System Settings → Keyboard → Keyboard Shortcuts) may already be using that combination — free it up there or open an issue to request configurable shortcuts.

Check what your display supports from the terminal:

```sh
./dist/MaxNits.app/Contents/MacOS/MaxNits --status      # print EDR headroom per display
./dist/MaxNits.app/Contents/MacOS/MaxNits --test        # 6-second boost self-test
./dist/MaxNits.app/Contents/MacOS/MaxNits --hotkeytest  # confirm ⌘F1/⌘F2 aren't already claimed
```

## Caveats

- **Battery & heat**: 1000 nits draws significantly more power than 600.
- **Auto-brightness**: macOS may still dim the display based on ambient light or thermal pressure; MaxNits works on top of whatever the OS allows at that moment.
- **HDR content**: while boosted, true HDR content has less headroom left to stand out.

## Credits

The EDR + multiply-overlay technique was pioneered by apps like [BrightIntosh](https://github.com/niklasr22/BrightIntosh) (GPL) and used in [FullBright](https://fullbright.app) and [BetterDisplay](https://github.com/waydabber/BetterDisplay)'s "Software Metal Upscaling" mode. MaxNits is an independent, from-scratch MIT-licensed implementation of the same idea.

## License

[MIT](LICENSE)

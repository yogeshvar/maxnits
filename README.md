# MaxNits ☀️

Free, open-source menu bar app that unlocks the full brightness of your MacBook Pro's XDR display — up to ~1000 nits for everyday (SDR) use instead of Apple's default 600-nit limit.

No purchases, no subscriptions, no telemetry. MIT licensed.

## Why MaxNits?

Apple's MacBook Pro (14"/16", M1 and later) has a Liquid Retina XDR display capable of 1000 nits sustained (1600 nits peak for HDR), but macOS caps normal use at 600 nits. Paid apps exist that lift this cap — MaxNits does it for free, plus a couple of things the paid ones don't:

- **🔋 Battery Guard** — the boost can automatically pause when you unplug, and always pauses in Low Power Mode, then resumes by itself when power is back. Max brightness when you're plugged in, max battery when you're not.
- **✨ Center-screen HUD** — a native-feeling bezel pops up in the middle of the screen when the boost changes (on, off, level, paused, resumed), so you always know what's happening.
- **☀️ Simple** — one toggle, one slider, nothing else to learn. Settings persist across restarts.

## How it works

MaxNits uses only public macOS APIs:

1. **EDR activation** — a 1×1 pixel invisible overlay window renders a single pixel brighter than SDR white using Metal (`CAMetalLayer` with `wantsExtendedDynamicRangeContent`). This makes macOS switch the display into Extended Dynamic Range mode, which unlocks brightness headroom above the SDR ceiling.
2. **Gamma shift** — the display's gamma tables are scaled above 1.0 with `CGSetDisplayTransferByTable`, mapping all normal content into the unlocked extended range. Result: everything on screen gets brighter, up to the panel's real limit.

Because gamma tables are per-process and macOS restores them automatically when the process exits, MaxNits can never leave your display stuck in a weird state — even if it crashes.

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
- The slider controls how much of the available headroom to use.
- **Pause on Battery** enables Battery Guard.
- **Launch at Login** keeps it running.

Check what your display supports from the terminal:

```sh
./dist/MaxNits.app/Contents/MacOS/MaxNits --status   # print EDR headroom per display
./dist/MaxNits.app/Contents/MacOS/MaxNits --test     # 6-second boost self-test
```

## Caveats

- **Battery & heat**: 1000 nits draws significantly more power than 600 (that's what Battery Guard is for).
- **Auto-brightness**: macOS may still dim the display based on ambient light or thermal pressure; MaxNits works on top of whatever the OS allows at that moment.
- **HDR content**: while boosted, true HDR content has less headroom left to stand out.
- Apps that also modify gamma (f.lux, some color-calibration tools) may conflict.

## Credits

The EDR + gamma technique was pioneered by apps like [BrightIntosh](https://github.com/niklasr22/BrightIntosh) (GPL) and [FullBright](https://fullbright.app). MaxNits is an independent, from-scratch MIT-licensed implementation of the same idea.

## License

[MIT](LICENSE)

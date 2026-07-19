# Overbright ☀️

Free, open-source menu bar app that unlocks the full brightness of your MacBook Pro's XDR display — up to ~1000 nits for everyday (SDR) use instead of Apple's default 600-nit limit.

No subscriptions, no purchases, no telemetry. MIT licensed.

## Why

Apple's MacBook Pro (14"/16", M1 and later) has a Liquid Retina XDR display capable of 1000 nits sustained (1600 nits peak for HDR), but macOS caps normal use at 600 nits to save battery. Paid apps exist that lift this cap — Overbright does the same thing for free.

## How it works

Overbright uses only public macOS APIs:

1. **EDR activation** — a 1×1 pixel invisible overlay window renders a single pixel brighter than SDR white using Metal (`CAMetalLayer` with `wantsExtendedDynamicRangeContent`). This makes macOS switch the display into Extended Dynamic Range mode, which unlocks brightness headroom above the SDR ceiling.
2. **Gamma shift** — the display's gamma tables are scaled above 1.0 with `CGSetDisplayTransferByTable`, mapping all normal content into the unlocked extended range. Result: everything on screen gets brighter, up to the panel's real limit.

Because gamma tables are per-process and macOS restores them automatically when the process exits, Overbright can never leave your display stuck in a weird state — even if it crashes.

## Requirements

- A Mac with a Liquid Retina XDR display: MacBook Pro 14"/16" (M1 Pro/Max or later) or Pro Display XDR / other EDR-capable external displays.
- macOS 13 Ventura or later.

On non-XDR displays (e.g. MacBook Air) there is little or no headroom to unlock, and the app will tell you so.

## Install

Build from source (requires Xcode Command Line Tools):

```sh
git clone <this repo>
cd overbright
make app        # builds dist/Overbright.app
make run        # builds and launches
```

Then optionally drag `dist/Overbright.app` into `/Applications`.

## Usage

- Click the ☀️ icon in the menu bar.
- **Boost Brightness** toggles the extra brightness on/off.
- The slider controls how much of the available headroom to use.
- **Launch at Login** keeps it running.

Check what your display supports from the terminal:

```sh
./dist/Overbright.app/Contents/MacOS/Overbright --status
```

## Caveats

- **Battery & heat**: 1000 nits draws significantly more power than 600. Your battery will drain faster and the machine will run warmer.
- **Auto-brightness**: macOS may still dim the display based on ambient light or thermal pressure; Overbright works on top of whatever the OS allows at that moment.
- **HDR content**: while boosted, true HDR content has less headroom left to stand out.
- Apps that also modify gamma (f.lux, some color-calibration tools) may conflict.

## Credits

The EDR + gamma technique was pioneered by apps like [BrightIntosh](https://github.com/niklasr22/BrightIntosh) (GPL) and [FullBright](https://fullbright.app). Overbright is an independent, from-scratch MIT-licensed implementation of the same idea.

## License

[MIT](LICENSE)

# Background Crop

An Omarchy shell plugin that replaces the stock desktop background renderer's
fixed centered crop with a pan/zoom crop you control yourself — per monitor,
and per background image.

Omarchy's default background always centers and crops a wallpaper to fill the
screen (Qt's `PreserveAspectCrop`). That's fine until the interesting part of
an image lands off to one side, or you have two monitors with different
aspect ratios and want each to frame the image differently. This plugin adds
that control, with no extra config file to hand-edit: you drag and scroll,
and it remembers.

## Features

- **Drag to pan, scroll to zoom** — live, right on the desktop.
- **Per monitor** — a 21:9 ultrawide and a 16:9 panel can each show a
  different crop of the same wallpaper.
- **Per background image** — settings are keyed by image path, so switching
  wallpapers (or `omarchy theme bg next`) recalls whatever crop you last set
  for that specific image on that specific monitor, or falls back to the
  stock centered crop if you never touched it.
- **Autosaved** — no explicit save step; state is written (debounced) to
  `~/.local/state/omarchy/background-crop.json`.
- Everything else about the stock background plugin (theme transitions,
  double-click to open the background/theme switcher) is unchanged.

## Install

```sh
omarchy plugin add https://github.com/danshephard-hub/omarchy-background-crop.git --enable
```

This clones the plugin, disables the built-in `omarchy.background`, and
switches the desktop background renderer to this one.

Then copy the helper script onto your `PATH` (used by the keybindings below):

```sh
cp ~/.config/omarchy/plugins/danshephard-hub.background-crop/bin/omarchy-background-crop ~/.local/bin/
chmod +x ~/.local/bin/omarchy-background-crop
```

## Keybindings

Add to `~/.config/hypr/bindings.lua` (pick whatever combo you like — these
two are free on a stock Omarchy install):

```lua
o.bind("SUPER + CTRL + ALT + C", "Crop background", "omarchy-background-crop edit")
o.bind("SUPER + CTRL + ALT + SHIFT + C", "Reset background crop", "omarchy-background-crop reset")
```

## Usage

1. Press your "Crop background" keybind. Each monitor shows a HUD with its
   name, current zoom, and position, plus a reminder of the controls.
2. Drag anywhere on the desktop to pan; scroll to zoom in (crops tighter).
   Each monitor is independent — what you do on one doesn't affect another.
3. Press the same keybind again to leave edit mode. There's nothing to
   confirm — every change is already saved.
4. Made a mess of it? Your "Reset background crop" keybind resets just the
   focused monitor's crop for the current background back to centered.

While edit mode is on, dragging or scrolling *anywhere on the empty desktop*
on either monitor is treated as a crop edit — so only leave it toggled on
while you're deliberately adjusting.

### CLI reference

```
omarchy-background-crop edit        # toggle crop editing mode
omarchy-background-crop start       # enter crop editing mode
omarchy-background-crop stop        # leave crop editing mode
omarchy-background-crop reset       # reset the focused monitor's current crop
omarchy-background-crop reset-all   # reset every monitor's current crop
```

## How it works

The plugin swaps the stock `Image.PreserveAspectCrop` fill mode for a small
custom `CropImage` component: the image is scaled to the minimum size needed
to cover the screen (identical to the stock crop when zoom is 1), then an
`offsetX`/`offsetY` pair in `[0, 1]` (0.5/0.5 = centered, matching the
default) slides which part of the overflow is shown, and `zoom` (≥ 1) scales
further so there's room to pan on both axes. Settings are looked up by
`(monitor name, background image path)` from a small JSON file and applied
reactively, so hot-reloading and theme/background transitions keep working
exactly as they do in the stock plugin.

## Uninstall / revert to stock

```sh
omarchy plugin disable danshephard-hub.background-crop
omarchy plugin enable omarchy.background
omarchy plugin remove danshephard-hub.background-crop
```

## License

MIT — see [LICENSE](LICENSE).

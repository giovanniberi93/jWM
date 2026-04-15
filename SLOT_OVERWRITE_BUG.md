# Bug: promoteIfFullScreen overwrites slot, losing track of previous occupant

## Problem

`SlotState` tracks one fullscreen app per display. When a second app is focused (not tiled) and happens to be fullscreen-sized on the same display, `promoteIfFullScreen` overwrites the slot — evicting the first app. When the second app is later tiled to a half, the displacement logic can't find the first app because it's no longer in any slot.

## Reproduction

1. Tile kitty to fullscreen on a display (slot gets set)
2. Focus WhatsApp (no tile) — WhatsApp was previously fullscreen on the same display, so `promoteIfFullScreen` detects it and overwrites kitty's slot
3. Tile WhatsApp to right — displacement checks the slot, finds WhatsApp itself (`fullPid == pid`), skips displacement
4. kitty stays fullscreen behind WhatsApp, never gets displaced to left

## Logs

```
[19:04:29.430] jwm: App activated: kitty
[19:04:29.637] jwm: Promoted kitty to fullScreen slot on display 1
[19:06:16.403] jwm: Focusing app5 -> net.whatsapp.WhatsApp
[19:06:16.477] jwm: Promoted WhatsApp to fullScreen slot on display 1   <-- kitty evicted
[19:06:18.943] jwm: Chord complete: app5 -> right
[19:06:18.943] jwm: Tile + focus app5 -> net.whatsapp.WhatsApp -> right
[19:06:18.945] jwm: Tiling WhatsApp to right
[19:06:18.946] jwm: Target app is on screen 0 (frame: (0.0, 0.0, 1728.0, 1117.0))
[19:06:18.946] jwm: Setting window to (864.0, 33.0, 864.0, 1084.0)
                                        <-- kitty NOT displaced to left
[19:06:24.625] jwm: App activated: kitty
[19:06:24.681] jwm: Promoted kitty to fullScreen slot on display 1
```

## Root cause

`SlotState` is a `[CGDirectDisplayID: pid_t]` — one slot per display. This is fine when only one app is fullscreen at a time (the normal case after tiling). But when a second app is *focused* (not tiled) and it happens to be fullscreen-sized, `promoteIfFullScreen` has no choice but to overwrite. The evicted app is lost.

## Possible directions

- **Track multiple fullscreen apps per display** — e.g. `[CGDirectDisplayID: [pid_t]]` as a stack. When one is promoted, push it; when one is tiled to a half, pop it and check if there's still a fullscreen app underneath.
- **Track all tiled positions, not just fullscreen** — e.g. `[CGDirectDisplayID: (left: pid_t?, right: pid_t?, full: pid_t?)]`. This would let displacement work correctly in more cases (e.g. replacing a half-tiled app).
- **On tile-to-half, scan for other fullscreen windows on the display** instead of relying solely on slot state. Use `getWindowRect` to find apps that are still fullscreen-sized, regardless of whether they're in the slot.

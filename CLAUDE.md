# jwm — janzo window manager

A macOS tiling window manager optimized for single-screen usage. Combines app focusing (like Raycast) and window tiling (like Rectangle) into a single key-chord interaction.

## Design Decisions

### Core Interaction: cmd+N chord

The user selects apps with `cmd+N` (e.g. cmd+1 for Terminal). This focuses the app. Within a short timeout (~500ms), a follow-up position key tiles the window. If no follow-up key is pressed, the app is simply focused in its current position/size.

### Position Keys

| Key | Position |
|-----|----------|
| `h` | Left half |
| `l` | Right half |
| `j` | Full screen |

Top/bottom halves are out of scope for now.

### Examples

| Keys | Action |
|------|--------|
| `cmd+1` | Focus app 1, keep current position |
| `cmd+1`, `h` | Focus app 1, tile to left half |
| `cmd+2`, `l` | Focus app 2, tile to right half |
| `cmd+1`, `h`, `cmd+2`, `l` | App 1 left, app 2 right |
| `cmd+3`, `j` | Focus app 3, full screen |

### App Bindings

App-to-key mappings (cmd+1, cmd+2, etc.) are user-configurable via config file or UI. Do not hardcode specific app assignments.

### Automatic Window Rearrangement

When tiling a window, the system automatically adjusts other visible windows:

- **Full-screen app + new half tile:** The full-screen app shrinks to the opposite half. E.g., app1 is full screen, `cmd+2, h` → app2 takes left, app1 moves to right.
- **Half tile replaces existing half tile:** The new app takes the slot, the previous occupant goes behind (no repositioning). E.g., app1 left, app2 right, `cmd+3, l` → app3 takes right, app2 goes behind.
- **New full-screen app:** Covers everything, other apps remain in their positions behind it.

The mental model is two slots (left, right). Full screen occupies both. Only a full-screen app auto-repositions when displaced; other displaced apps simply lose focus.

### Direct Window Positioning: ctrl+cmd+position

To move the currently focused app without selecting it by number:

| Keys | Action |
|------|--------|
| `ctrl+cmd+h` | Current app → left half |
| `ctrl+cmd+l` | Current app → right half |
| `ctrl+cmd+j` | Current app → full screen |

No chord/timeout needed — single keystroke, immediate effect. Same h/l/j position keys for consistency.

### Alternative Interaction (Option C — future consideration)

Instead of a timeout-based chord, detect whether `cmd` is released to distinguish "just focus" from "focus + position." This would be a localized change in the input handling layer if we switch later.

## Scope

### In scope
- App focusing via global hotkeys (cmd+N)
- Window tiling (left half, right half, full screen)
- Single screen only
- Configurable app bindings (config file or UI)
- macOS menu bar app

### Out of scope (for now)
- Multi-monitor support
- Thirds / quarters
- Saved layouts
- Top / bottom halves

### Nice to have
- Drag-and-drop window tiling

## Tech

- **Platform:** macOS native Swift app
- **Distribution:** Menu bar app
- **License:** Open source (license TBD)

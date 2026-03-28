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

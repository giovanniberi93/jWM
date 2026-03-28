# jwm — janzo window manager

A macOS tiling window manager optimized for single-screen usage. Combines app focusing (like Raycast) and window tiling (like Rectangle) into a single key-chord interaction.

## Design Decisions

### Core Interaction: cmd+N hold-based chord

The user selects apps with `cmd+N` (e.g. cmd+1 for Terminal). The behaviour depends on whether `cmd` is held or released:

- **`cmd+N`, release `cmd`** → Focus the app, keep current position/size (instant, no delay).
- **`cmd+N`, keep holding `cmd`, press position key** → Focus the app and tile it. The window is moved to position *before* being brought to front, so it appears already in place.

### Position Keys

| Key | Position |
|-----|----------|
| `h` | Left half |
| `l` | Right half |
| `j` | Full screen |

Top/bottom halves are out of scope for now. "Full screen" means maximized to the screen's visible area (excluding menu bar and Dock) — NOT macOS native fullscreen which creates a new desktop/space.

### Examples

| Keys | Action |
|------|--------|
| `cmd+1`, release cmd | Focus app 1, keep current position |
| `cmd+1`, hold cmd, `h` | Focus app 1, tile to left half |
| `cmd+2`, hold cmd, `l` | Focus app 2, tile to right half |
| `cmd+1`, hold cmd, `h`, `cmd+2`, hold cmd, `l` | App 1 left, app 2 right |
| `cmd+3`, hold cmd, `j` | Focus app 3, full screen |
| `cmd+shift+1`, release cmd | Focus alternate app for slot 1 |
| `cmd+shift+1`, hold cmd, `h` | Focus alternate app for slot 1, tile left |

### App Bindings

Each slot (0-9) has two bindings:
- `cmd+N` — primary app
- `cmd+shift+N` — alternate app (e.g. cmd+3 = Chrome, cmd+shift+3 = Firefox)

App-to-key mappings are user-configurable via the Settings UI. Do not hardcode specific app assignments.

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

### Design Note: hold-based vs timeout-based chord

We initially tried a timeout-based approach (500ms window after cmd+N for a position key). This added noticeable delay to plain focus. The hold-based approach (detect cmd release) eliminates the delay entirely. The timeout approach was discarded.

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

# jWM — janzo window manager

A macOS tiling window manager optimized for single-screen usage. Combines app focusing and window tiling into a single key-chord interaction.

## Setup

### Disable macOS built-in window tiling

macOS Sequoia has its own drag-to-edge tiling that conflicts with jWM. Disable it:

**Option A:** Open jWM Settings, click "Go to settings" and disable the "Drag windows to left or right edge of screen to tile".

**Option B:** Run in terminal:

```bash
defaults write com.apple.WindowManager EnableTilingByEdgeDrag -bool false
```

### Grant Accessibility permission

jWM needs Accessibility access to manage windows. macOS will prompt on first launch. If it stops working after a rebuild, reset the permission:

```bash
tccutil reset Accessibility giober.jwm
```

## Usage

### App focusing: ⌘+N

Each number key (0-9) is bound to an app in Settings. `cmd+shift+N` activates the alternate binding for that slot.

### Focusing and tiling a different app

After pressing `cmd+N`, keep holding `cmd` and press a position key:

| Key | Position |
|-----|----------|
| `h` | Left half |
| `l` | Right half |
| `j` | Full screen |

Release `cmd` without a position key to just focus the app.

### Tiling currently focused window

Move the currently focused window without selecting by number:

| Keys | Action |
|------|--------|
| `ctrl+cmd+h` | Left half |
| `ctrl+cmd+l` | Right half |
| `ctrl+cmd+j` | Full screen |

### Drag to edge

Drag any window to the left or right screen edge to tile it. A preview overlay shows the target position.

## License

MIT

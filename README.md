<p align="center">
  <img src="jwm/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="jWM icon">
  <h2 align="center">jWM — janzo's Window Manager</h2>
</p>

<p align="center">A simple tiling window manager for MacOS.</p>
<p align="center">It combines app focusing and window tiling into a single key-chord interaction.</p>

<table>
  <tr>
    <th>App Focusing<br><code>⌘</code> + <code>&lt;N&gt;</code></th>
    <th>Window Tiling<br><code>⌘</code> + <code>⌃</code> + <code>h</code>/<code>j</code>/<code>l</code><br>(or mouse)</th>
    <th>✨ App Focusing + Window Tiling ✨<br><code>⌘</code> + <code>⌃</code> + <code>&lt;N&gt;</code></th>
  </tr>
  <tr>
    <td>
      <img src="assets/focus.gif" />
    </td>
    <td>
      <img src="assets/tile.gif" />
    </td>
    <td>
      <img src="assets/focus+tile.gif" />
    </td>
  </tr>
</table>

## Why jWM?

I've been a happy [Rectangle](https://rectangleapp.com/) user for a few years, but the problem with it is that you always have to focus the app you're interested in, _and then_ you can move it around using Rectangle. My solution was to use [Raycast](https://www.raycast.com/) to quickly launch or focus the application I wanted to move with Rectangle.

That worked, but I came to dislike having to always perform two separate operations to move a single window. `jWM` solves this issue by combining app focusing and window tiling in a single key-chord.

## Requirements

[Xcode](https://xcodereleases.com/) to build the application.

The application was developed using [Xcode 26.3](https://developer.apple.com/services-account/download?path=/Developer_Tools/Xcode_26.3/Xcode_26.3_Universal.xip) on macOS Tahoe 26.3.1

> ***Wait, no pre-built binaries?***
>
> No, there's currently only 1 jWM user so it doesn't feel necessary for now.

## Installation

Run `make install` in the repo root to build and install the app in `~/Applications/`.

Run `make dev` in the repo root to build and run the application without installing it.

## Usage

### App focusing: `⌘`+`<N>`, `⌘`+`⇧`+`<N>`

In jWM settings in the menu bar, each number key (0-9) can be bound to two apps:
- main app binding: `⌘`+`<N>`
- alternate app binding: `⌘`+`⇧`+`<N>`

For example, you could use `⌘`+`3` for Chrome, and `⌘`+`⇧`+`3` for Safari.

The app bindings can then be used to focus (or launch) the corresponding apps.

### Tiling currently focused window

Tile the currently focused window:

| Keys | Action |
|------|--------|
| `⌃`+`⌘`+`h` | Left half of the screen |
| `⌃`+`⌘`+`l` | Right half of the screen |
| `⌃`+`⌘`+`j` | Full screen |

> ***Wait, no screen thirds, or horizontal halves? Why `h`/`l`/`j`?***
>
> I pretty much only use vertical screen halves, so I'm focusing on those now.
> 
> `h`/`l`/`j` are vim-like keybindings, they're convenient because they live in the home row of your keyboard.
### Focusing and tiling a different app

After pressing `⌘`+`<N>` or `⌘`+`⇧`+`<N>`, keep holding `⌘` and press a position key to tile the window of the selected app:

| Key | Position |
|-----|----------|
| `h` | Left half of the screen |
| `l` | Right half of the screen |
| `j` | Full screen |

### Mouse support

Drag any window to the left or right screen edge to tile it. A preview overlay shows the target position.

Double click on the title bar to make a window full screen.

## Troubleshooting

### Disable macOS built-in window tiling

macOS Sequoia has its own drag-to-edge tiling that conflicts with jWM. Disable it:

**Option A:** Open jWM Settings, click "Go to settings" and disable the "Drag windows to left or right edge of screen to tile".

**Option B:** Run in terminal:

```bash
defaults write com.apple.WindowManager EnableTilingByEdgeDrag -bool false
```

### Reset accessibility permissions

jWM needs Accessibility access to manage windows. macOS will prompt on first launch. If it stops working after a rebuild, reset the permission:

```bash
make reset-accessibility-permissions
```

## Contributors

- **janzo**
- **Claude** <img src="https://media.tenor.com/WvYJnr85GLoAAAAi/cl aude-claude-code.gif" width="20" />

## License

Do whatever you want with jWM.

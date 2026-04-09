# jwm — janzo window manager

A macOS tiling window manager. Combines app focusing (like Raycast) and window tiling (like Rectangle) into a single key-chord interaction. See README.md for user-facing docs.

## Design Constraints

- **"Full screen" = maximized, NOT macOS native fullscreen.** It fills the screen's visible area (excluding menu bar and Dock). It must never create a new desktop/space.
- **Window moves before activation.** When tiling via chord (cmd+N + position), the window is repositioned *before* being brought to front, so it appears already in place.
- **Hold-based chord, not timeout-based.** A 500ms timeout approach was tried and discarded — it added noticeable delay to plain focus. The current hold-based approach (hold cmd → press position key) eliminates this.
- **Two-slot mental model for auto-rearrangement.** There are two slots: left and right. Full screen occupies both. When a half tile displaces a full-screen app, the full-screen app shrinks to the opposite half. When a half tile replaces another half tile, the previous occupant simply loses focus (no repositioning). Only full-screen apps auto-reposition when displaced.
- **Cross-screen moves need position-first ordering.** The normal `setWindowPosition` does size→position→size to avoid macOS clamping. Cross-screen moves must do position→size→position→size instead, because setting the target screen's size while still on the original screen causes macOS to clamp incorrectly.
- **AppKit→CG coordinate conversion always uses primary screen height.** CG coordinates have origin at the primary screen's top-left. The y-flip formula `cgY = primaryHeight - appKitY - height` must use `NSScreen.screens[0].frame.height`, not the current screen's height, even when tiling on a secondary screen.
- **Do not hardcode app assignments.** App-to-key mappings are user-configurable via Settings UI and stored in UserDefaults.
- **Every change must be assessed for multi-screen correctness.** Before considering a change done, verify that it works correctly when multiple screens are connected — coordinate conversions, screen selection, slot tracking, and window positioning must all account for the multi-screen case.

## References

- **[Rectangle](https://rectangleapp.com/)** — similar macOS window manager, useful as reference for solving window management problems. Source available at `/Users/giovanni.beri/workspace/Rectangle` (clone from `https://github.com/rxhanson/rectangle` if needed).

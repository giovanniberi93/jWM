import Cocoa
import SwiftUI

/// Visual feedback during the cmd+N → (position-key | cmd-release) pending
/// window. Rendered only — no state mutation, no AX writes, no app activation.
/// HotkeyManager owns the state machine; this window only renders the current
/// pending target.
///
/// Always a halo around the rect the chord will affect: the target window's
/// frame if it exists, or the would-be-launch rect (visibleFrame of the
/// active screen, which is also where onFocus tiles fullscreen on launch)
/// otherwise. Predictive — the rectangle the user sees IS where the app will
/// end up.
final class ChordPreviewWindow: NSWindow {
    private let host: NSHostingView<AnyView>
    /// Bumped on every show/hide/animate. Pending animation completions
    /// check this and bail if the value moved on — so a chord that arrives
    /// mid-animation isn't clobbered by the previous animation's orderOut.
    private var generation: Int = 0

    init() {
        host = NSHostingView(rootView: AnyView(EmptyView()))
        // Non-zero initial contentRect so the first layout pass isn't degenerate.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // .popUpMenu (101) — same level Spotlight-class overlays use.
        level = .popUpMenu
        // .fullScreenAuxiliary lets the preview appear on a fullscreen-app
        // Space without kicking the user out of it.
        collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true

        // Host as contentView directly — no NSView container. The container
        // indirection caused intermittent clipping in card mode: SwiftUI could
        // lay out at the container's stale bounds before autoresizing settled.
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    /// Window frame is the rect the chord will affect (existing target window
    /// or would-be-launch rect). The SwiftUI border strokes inside that rect.
    func showHalo(state: ChordPreviewState, around rect: NSRect) {
        generation += 1
        host.rootView = AnyView(ChordPreviewContent(state: state))
        setFrame(rect, display: true)
        host.layoutSubtreeIfNeeded()
        orderFrontRegardless()
    }

    func hide() {
        generation += 1
        orderOut(nil)
    }

    /// "Arrival" animation: jump instantly to a point 2/3 of the way toward
    /// `dest`, then animate the last 1/3 into `dest`, then hide. The halo
    /// reads as settling into the destination rather than drifting away from
    /// the start. Short animated distance keeps per-frame deltas small and
    /// the motion smooth.
    func animateOut(to dest: NSRect) {
        generation += 1
        let gen = generation
        let start = frame
        let skip: CGFloat = 0.67
        let animStart = NSRect(
            x: start.origin.x + (dest.origin.x - start.origin.x) * skip,
            y: start.origin.y + (dest.origin.y - start.origin.y) * skip,
            width: start.size.width + (dest.size.width - start.size.width) * skip,
            height: start.size.height + (dest.size.height - start.size.height) * skip
        )
        setFrame(animStart, display: true)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(dest, display: true)
        }, completionHandler: { [weak self] in
            guard let self, self.generation == gen else { return }
            self.orderOut(nil)
        })
    }
}

struct ChordPreviewState: Equatable {
    let appLabel: String
    let chord: String
    let icon: NSImage?

    static func == (lhs: ChordPreviewState, rhs: ChordPreviewState) -> Bool {
        lhs.appLabel == rhs.appLabel && lhs.chord == rhs.chord && lhs.icon === rhs.icon
    }
}

private struct ChordPreviewContent: View {
    let state: ChordPreviewState

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.08))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 3)
            chip.padding(10)
        }
    }

    private var chip: some View {
        HStack(spacing: 10) {
            if let icon = state.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.appLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(state.chord)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            // Solid window-background fill. .regularMaterial was the previous
            // choice but glitched intermittently on a borderless transparent
            // window — the blur backing buffer didn't always update with the
            // window's frame on show. Solid is reliable.
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .fixedSize()
    }
}

import SwiftUI
import AppKit
import Combine

/// AppStorage key conventions for slot bindings. Used by both Settings and
/// the onboarding tutorial so the two surfaces share state.
func slotBundleIDKey(slot: Int, shifted: Bool) -> String {
    "\(shifted ? "shiftApp" : "app")\(slot)_bundleID"
}

func slotAppNameKey(slot: Int, shifted: Bool) -> String {
    "\(shifted ? "shiftApp" : "app")\(slot)_appName"
}

/// Identifies a single slot binding across the two Settings KeyRows.
struct SlotID: Hashable {
    let slot: Int
    let shifted: Bool
}

/// SwiftUI preference key used to collect per-slot frames (in the shared
/// "slotGrid" coordinate space) for the Settings drag-and-drop coordinator.
struct SlotFramePreferenceKey: PreferenceKey {
    static var defaultValue: [SlotID: CGRect] = [:]
    static func reduce(value: inout [SlotID: CGRect], nextValue: () -> [SlotID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Coordinates dragging an app binding from one slot to another in Settings.
/// Knows the on-screen frame of every slot (in the "slotGrid" coordinate
/// space) and the currently in-flight drag, if any. The view layer reads
/// `dragState` to render a floating ghost icon and to hide the icon on the
/// source slot while the drag is active.
@MainActor
final class SlotDragCoordinator: ObservableObject {
    struct DragState {
        let source: SlotID
        let bundleID: String
        let appName: String
        let sourceCenter: CGPoint
        /// Cursor position in the "slotGrid" coordinate space — the ghost
        /// icon is rendered centered on this point so it stays under the
        /// pointer regardless of where on the source keycap the press began.
        var currentLocation: CGPoint
        /// While false, location updates are routed through a spring so the
        /// icon eases up to the cursor instead of teleporting. Flips to true
        /// a moment after `startDrag` so subsequent tracking is 1:1.
        var trackingEnabled: Bool = false
    }

    /// Spring used both for the initial pickup snap and for the drop/snap-back.
    private let snapAnimation: Animation = .spring(response: 0.22, dampingFraction: 0.85)

    @Published var frames: [SlotID: CGRect] = [:]
    @Published var dragState: DragState? = nil

    /// Distance (in points) from the cursor to an empty slot's center that
    /// still counts as a successful drop. Roughly 0.8× the slot width — a
    /// drop just outside an empty slot still snaps in.
    private let dropTolerance: CGFloat = 50

    /// Begin a drag from `source`. No-op if a drag is already active, the
    /// frame hasn't been registered yet, or the source slot is unbound.
    /// The ghost starts at the source keycap's center and springs to the
    /// cursor on the next runloop tick — same animation as drop/snap-back.
    func startDrag(source: SlotID, at location: CGPoint) {
        guard dragState == nil, let frame = frames[source] else { return }
        let bid = UserDefaults.standard.string(forKey: slotBundleIDKey(slot: source.slot, shifted: source.shifted)) ?? ""
        let name = UserDefaults.standard.string(forKey: slotAppNameKey(slot: source.slot, shifted: source.shifted)) ?? ""
        guard !bid.isEmpty else { return }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        dragState = DragState(
            source: source,
            bundleID: bid,
            appName: name,
            sourceCenter: center,
            currentLocation: center
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(self.snapAnimation) {
                self.dragState?.currentLocation = location
            } completion: { [weak self] in
                self?.dragState?.trackingEnabled = true
            }
        }
    }

    func updateLocation(_ location: CGPoint) {
        guard let state = dragState else { return }
        if state.trackingEnabled {
            dragState?.currentLocation = location
        } else {
            withAnimation(snapAnimation) {
                dragState?.currentLocation = location
            }
        }
    }

    /// Resolve the drop. If `location` lands close to an empty slot, animate
    /// the ghost into that slot and commit the binding move. Otherwise snap
    /// the ghost back to the source and leave bindings untouched.
    func endDrag(at location: CGPoint) {
        guard let drag = dragState else { return }

        var bestID: SlotID? = nil
        var bestDist: CGFloat = .infinity
        for (id, frame) in frames where id != drag.source {
            let bid = UserDefaults.standard.string(forKey: slotBundleIDKey(slot: id.slot, shifted: id.shifted)) ?? ""
            guard bid.isEmpty else { continue }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let dx = center.x - location.x
            let dy = center.y - location.y
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist < bestDist {
                bestDist = dist
                bestID = id
            }
        }

        if let target = bestID, bestDist <= dropTolerance, let targetFrame = frames[target] {
            let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            withAnimation(snapAnimation) {
                dragState?.currentLocation = targetCenter
            } completion: { [weak self] in
                guard let self else { return }
                let defaults = UserDefaults.standard
                defaults.set(drag.bundleID, forKey: slotBundleIDKey(slot: target.slot, shifted: target.shifted))
                defaults.set(drag.appName, forKey: slotAppNameKey(slot: target.slot, shifted: target.shifted))
                defaults.removeObject(forKey: slotBundleIDKey(slot: drag.source.slot, shifted: drag.source.shifted))
                defaults.removeObject(forKey: slotAppNameKey(slot: drag.source.slot, shifted: drag.source.shifted))
                self.dragState = nil
            }
        } else {
            withAnimation(snapAnimation) {
                dragState?.currentLocation = drag.sourceCenter
            } completion: { [weak self] in
                self?.dragState = nil
            }
        }
    }
}

/// Visual keycap for a single slot binding. Reads its bundleID/appName via
/// `@AppStorage`, so changes from any caller (Settings, tutorial, or a
/// direct UserDefaults write) propagate automatically.
///
/// Used in two places:
/// - Settings → KeyRow: `target=false`, `showClearBadge=true`, `onTap` opens NSOpenPanel
/// - Tutorial → SlotRail: `target=true` for the slot the user is binding now,
///   `showClearBadge=false`, `onTap` is a no-op (the AppGrid below handles picking)
struct SlotKeycap: View {
    let slot: Int
    let shifted: Bool
    let hovered: Bool
    let target: Bool
    let showClearBadge: Bool
    /// Render the cap as if no app were bound, regardless of AppStorage. The
    /// tutorial uses this for slots 2…0 so it can present a clean rail
    /// even when the user has prior bindings from Settings.
    let forceEmpty: Bool
    /// True while this slot is acting as the source of an in-flight drag in
    /// Settings. The keycap chrome stays put but the icon is hidden — the
    /// ghost overlay rendered by the parent represents it instead.
    let isDragSource: Bool
    /// True briefly after a Finder drop is refused (the file wasn't a valid
    /// `.app` bundle). Renders the ring and shadow in red instead of the
    /// usual `target` blue. Overrides `target` while set.
    let isRejecting: Bool
    let onHoverChange: (Bool, String?) -> Void
    let onTap: () -> Void

    @AppStorage var bundleID: String
    @AppStorage var appName: String

    init(
        slot: Int,
        shifted: Bool = false,
        hovered: Bool,
        target: Bool = false,
        showClearBadge: Bool = true,
        forceEmpty: Bool = false,
        isDragSource: Bool = false,
        isRejecting: Bool = false,
        onHoverChange: @escaping (Bool, String?) -> Void = { _, _ in },
        onTap: @escaping () -> Void = {}
    ) {
        self.slot = slot
        self.shifted = shifted
        self.hovered = hovered
        self.target = target
        self.showClearBadge = showClearBadge
        self.forceEmpty = forceEmpty
        self.isDragSource = isDragSource
        self.isRejecting = isRejecting
        self.onHoverChange = onHoverChange
        self.onTap = onTap
        _bundleID = AppStorage(wrappedValue: "", slotBundleIDKey(slot: slot, shifted: shifted))
        _appName = AppStorage(wrappedValue: "", slotAppNameKey(slot: slot, shifted: shifted))
    }

    private var filled: Bool { !forceEmpty && !appName.isEmpty }
    private var showsIcon: Bool { filled && !isDragSource }
    private var isAccented: Bool { isRejecting || target }
    private var accentColor: Color? {
        if isRejecting { return Self.rejectRed }
        if target { return Self.targetBlue }
        return nil
    }

    private static let targetBlue = Color(red: 0x0a/255, green: 0x84/255, blue: 0xff/255)
    private static let rejectRed = Color(red: 0xdc/255, green: 0x26/255, blue: 0x26/255)

    var body: some View {
        ZStack {
            // body
            RoundedRectangle(cornerRadius: 8)
                .fill(filled ? AnyShapeStyle(.background) : AnyShapeStyle(Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            accentColor.map { AnyShapeStyle($0) }
                                ?? AnyShapeStyle(Color.secondary.opacity(filled ? 0.35 : 0.25)),
                            style: StrokeStyle(
                                lineWidth: isAccented ? 1.5 : 1,
                                dash: (filled && !isRejecting) || target ? [] : [3, 3]
                            )
                        )
                )
                .shadow(
                    color: accentColor?.opacity(0.28) ?? .black.opacity(filled ? 0.08 : 0),
                    radius: isAccented ? 4 : 1, y: 1
                )

            // icon or empty placeholder
            if showsIcon {
                BoundAppIcon(bundleID: bundleID)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .padding(.top, 8)
                    .overlay(alignment: .topLeading) {
                        if hovered && showClearBadge {
                            ClearBadge { clear() }
                                .offset(x: -5, y: 3)
                        }
                    }
            } else {
                Circle()
                    .strokeBorder(
                        isRejecting ? Self.rejectRed : Color.secondary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )
                    .frame(width: 16, height: 16)
                    .padding(.top, 8)
            }

            // slot digit notch
            VStack {
                Text("\(slot)")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 0, bottomLeading: 6, bottomTrailing: 6, topTrailing: 0)
                        )
                        .fill(.quaternary)
                    )
                    .overlay(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(topLeading: 0, bottomLeading: 6, bottomTrailing: 6, topTrailing: 0)
                        )
                        .strokeBorder(.separator, lineWidth: 1)
                    )
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .offset(y: hovered ? -1 : 0)
        .animation(.easeInOut(duration: 0.1), value: hovered)
        .contentShape(Rectangle())
        .onHover { isHover in
            onHoverChange(isHover, filled ? appName : nil)
        }
        .onTapGesture {
            guard !filled else { return }
            onTap()
        }
    }

    private func clear() {
        bundleID = ""
        appName = ""
    }
}

/// Renders an app icon by bundle id, falling back to a neutral tile.
struct BoundAppIcon: View {
    let bundleID: String

    var body: some View {
        if let image = Self.icon(for: bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
        }
    }

    private static func icon(for bundleID: String) -> NSImage? {
        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Hover-revealed × badge that clears the binding.
struct ClearBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.black.opacity(0.65))
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }
}

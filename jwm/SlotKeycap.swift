import SwiftUI
import AppKit

/// AppStorage key conventions for slot bindings. Used by both Settings and
/// the onboarding tutorial so the two surfaces share state.
func slotBundleIDKey(slot: Int, shifted: Bool) -> String {
    "\(shifted ? "shiftApp" : "app")\(slot)_bundleID"
}

func slotAppNameKey(slot: Int, shifted: Bool) -> String {
    "\(shifted ? "shiftApp" : "app")\(slot)_appName"
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
        onHoverChange: @escaping (Bool, String?) -> Void = { _, _ in },
        onTap: @escaping () -> Void = {}
    ) {
        self.slot = slot
        self.shifted = shifted
        self.hovered = hovered
        self.target = target
        self.showClearBadge = showClearBadge
        self.forceEmpty = forceEmpty
        self.onHoverChange = onHoverChange
        self.onTap = onTap
        _bundleID = AppStorage(wrappedValue: "", slotBundleIDKey(slot: slot, shifted: shifted))
        _appName = AppStorage(wrappedValue: "", slotAppNameKey(slot: slot, shifted: shifted))
    }

    private var filled: Bool { !forceEmpty && !appName.isEmpty }

    private static let targetBlue = Color(red: 0x0a/255, green: 0x84/255, blue: 0xff/255)

    var body: some View {
        ZStack {
            // body
            RoundedRectangle(cornerRadius: 8)
                .fill(filled ? AnyShapeStyle(.background) : AnyShapeStyle(Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            target
                                ? AnyShapeStyle(Self.targetBlue)
                                : AnyShapeStyle(Color.secondary.opacity(filled ? 0.35 : 0.25)),
                            style: StrokeStyle(
                                lineWidth: target ? 1.5 : 1,
                                dash: (filled || target) ? [] : [3, 3]
                            )
                        )
                )
                .shadow(
                    color: target
                        ? Self.targetBlue.opacity(0.18)
                        : .black.opacity(filled ? 0.08 : 0),
                    radius: target ? 4 : 1, y: 1
                )

            // icon or empty placeholder
            if filled {
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
                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
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
        .onTapGesture { onTap() }
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

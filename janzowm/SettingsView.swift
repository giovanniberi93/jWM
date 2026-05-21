import SwiftUI
import os
import ServiceManagement
import UniformTypeIdentifiers
import AppKit

// MARK: - Visual tokens

private enum DS {
    static let green = Color(red: 0x16/255, green: 0xa3/255, blue: 0x4a/255)
    static let okBg = Color(red: 0x16/255, green: 0xa3/255, blue: 0x4a/255).opacity(0.15)
    static let amber = Color(red: 0xb4/255, green: 0x53/255, blue: 0x09/255)
    static let amberBg = Color(red: 0xb4/255, green: 0x53/255, blue: 0x09/255).opacity(0.15)
    static let blue = Color(red: 0x0a/255, green: 0x84/255, blue: 0xff/255)
    static let mono = Font.system(size: 10.5, weight: .semibold, design: .monospaced)
}

// MARK: - Slot order (keyboard row: 1..9 then 0)

private let slotOrder: [Int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]

// MARK: - Root

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct SettingsView: View {
    var onContentHeightChange: ((CGFloat) -> Void)? = nil

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var macOSTilingEnabled = Self.isMacOSTilingEnabled()
    @State private var showResetConfirm = false
    @AppStorage("useArrowKeys") private var useArrowKeys: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHeader("App Bindings")
                    Spacer()
                    Button("Reset") { showResetConfirm = true }
                        .controlSize(.small)
                }
                .padding(.bottom, 10)

                SlotsBoard()
                    .padding(.bottom, 22)

                sectionHeader("General")
                    .padding(.bottom, 10)

                VStack(spacing: 6) {
                    LaunchAtLoginRow(
                        isOn: launchAtLogin,
                        setLaunchAtLogin: setLaunchAtLogin
                    )
                    UseArrowKeysRow(isOn: $useArrowKeys)
                }
                .padding(.bottom, 22)

                sectionHeader("Mouse support — Conflicting MacOS settings")
                    .padding(.bottom, 10)

                VStack(spacing: 6) {
                    EdgeTilingRow(
                        macOSTilingEnabled: macOSTilingEnabled,
                        openSettings: openMacOSTilingSettings
                    )
                }
                .padding(.bottom, 22)
            }
            .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
                .padding(.horizontal, -18)
                .padding(.bottom, 16)

            TilingFocusReference(useArrowKeys: useArrowKeys)

            VersionFooter()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(width: 760)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(ContentHeightKey.self) { height in
            onContentHeightChange?(height)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            macOSTilingEnabled = Self.isMacOSTilingEnabled()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .alert("Clear all app bindings?",
               isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) { resetAllBindings() }
        } message: {
            Text("This will remove all 20 app bindings (⌘1–0 and ⌘⇧1–0).")
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
    }

    private func setLaunchAtLogin(_ newValue: Bool) {
        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = newValue
        } catch {
            logger.error("Failed to update launch at login: \(error)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func openMacOSTilingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
    }

    private func resetAllBindings() {
        let defaults = UserDefaults.standard
        for slot in 0...9 {
            for shifted in [false, true] {
                defaults.removeObject(forKey: slotBundleIDKey(slot: slot, shifted: shifted))
                defaults.removeObject(forKey: slotAppNameKey(slot: slot, shifted: shifted))
            }
        }
    }

    private static func isMacOSTilingEnabled() -> Bool {
        guard #available(macOS 15, *),
              let defaults = UserDefaults(suiteName: "com.apple.WindowManager")
        else { return false }
        if defaults.object(forKey: "EnableTilingByEdgeDrag") == nil { return true }
        return defaults.bool(forKey: "EnableTilingByEdgeDrag")
    }

}

// MARK: - Other options rows

private struct LaunchAtLoginRow: View {
    let isOn: Bool
    let setLaunchAtLogin: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Launch at login")
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { isOn }, set: { setLaunchAtLogin($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
    }
}

private struct UseArrowKeysRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("Keys for tiling windows")
                .font(.system(size: 13, weight: .medium))
            StatusChip(
                text: isOn ? "← ↓ ↑ →" : "H J K L",
                fg: DS.blue,
                bg: DS.blue.opacity(0.15)
            )
            Spacer(minLength: 0)
            Picker("", selection: $isOn) {
                Text("Vim mode").tag(false)
                Text("Arrow keys").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .font(.system(size: 11))
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
    }
}

private struct EdgeTilingRow: View {
    let macOSTilingEnabled: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Drag windows to left or right edge of screen to tile")
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 6) {
                    if macOSTilingEnabled {
                        StatusChip(text: "FIX", fg: DS.amber, bg: DS.amberBg)
                        Text("Should be disabled — conflicts with janzoWM's drag-to-edge snapping")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    } else {
                        StatusChip(text: "OK", fg: DS.green, bg: DS.okBg)
                        Text("Already disabled — no conflict with janzoWM")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Button("Open Settings", action: openSettings)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
    }
}

private struct StatusChip: View {
    let text: String
    let fg: Color
    let bg: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(bg))
    }
}

// MARK: - Bindings board (drag & drop between slots)

/// Wraps the two `KeyRow`s in a shared coordinate space so a binding can be
/// dragged from any slot to any other empty slot — including across rows.
/// Owns the `SlotDragCoordinator` and renders the floating ghost overlay.
private struct SlotsBoard: View {
    @StateObject private var coord = SlotDragCoordinator()

    var body: some View {
        VStack(spacing: 10) {
            KeyRow(modifiers: ["⌘"], shifted: false, coord: coord)
            KeyRow(modifiers: ["⌘", "⇧"], shifted: true, coord: coord)
        }
        .coordinateSpace(name: "slotGrid")
        .onPreferenceChange(SlotFramePreferenceKey.self) { frames in
            coord.frames = frames
        }
        .overlay { dragGhost }
    }

    @ViewBuilder
    private var dragGhost: some View {
        if let drag = coord.dragState {
            BoundAppIcon(bundleID: drag.bundleID)
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .scaleEffect(1.18)
                .opacity(0.72)
                .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
                .position(drag.currentLocation)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Key row (binding strip)

private struct KeyRow: View {
    let modifiers: [String]
    let shifted: Bool
    @ObservedObject var coord: SlotDragCoordinator
    @State private var hoveredSlot: Int? = nil
    @State private var hoveredAppName: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(slotOrder, id: \.self) { slot in
                KeyRowCell(
                    slot: slot,
                    shifted: shifted,
                    coord: coord,
                    isHovered: hoveredSlot == slot,
                    onHoverChange: { isHover, name in
                        if isHover {
                            hoveredSlot = slot
                            hoveredAppName = name
                        } else if hoveredSlot == slot {
                            hoveredSlot = nil
                            hoveredAppName = nil
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 34)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quinary))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) { ChordCornerTab(modifiers: modifiers) }
    }

    @ViewBuilder
    private var readout: some View {
        if hoveredSlot != nil {
            if let name = hoveredAppName, !name.isEmpty {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            } else {
                Text("unbound — click to assign")
                    .font(.system(size: 11).italic())
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text(" ").font(.system(size: 12)).frame(minHeight: 16)
        }
    }

}

// MARK: - Key row cell

/// One slot inside a `KeyRow`. Owns its own drop-target state so a Finder
/// drag of an `.app` over an empty cell can light it up; commits the
/// binding when an `.app` is dropped on an empty slot. Filled slots reject
/// drops — the user must drag the existing binding away (or clear it via
/// the × badge) before another app can take that slot.
private struct KeyRowCell: View {
    let slot: Int
    let shifted: Bool
    @ObservedObject var coord: SlotDragCoordinator
    let isHovered: Bool
    let onHoverChange: (Bool, String?) -> Void

    @State private var isDropTargeted: Bool = false
    @State private var isRejecting: Bool = false

    private var id: SlotID { SlotID(slot: slot, shifted: shifted) }
    private var isDragSource: Bool { coord.dragState?.source == id }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: SlotFramePreferenceKey.self,
                            value: [id: proxy.frame(in: .named("slotGrid"))]
                        )
                }
            )
            .overlay {
                SlotKeycap(
                    slot: slot,
                    shifted: shifted,
                    hovered: isHovered,
                    target: isDropTargeted && !isFilled,
                    isDragSource: isDragSource,
                    isRejecting: isRejecting,
                    onHoverChange: onHoverChange,
                    onTap: pickApp
                )
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("slotGrid"))
                    .onChanged { value in
                        if coord.dragState == nil {
                            coord.startDrag(source: id, at: value.location)
                        } else {
                            coord.updateLocation(value.location)
                        }
                    }
                    .onEnded { value in
                        coord.endDrag(at: value.location)
                    }
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleFinderDrop(providers)
            }
    }

    private var isFilled: Bool {
        let bid = UserDefaults.standard.string(forKey: slotBundleIDKey(slot: slot, shifted: shifted)) ?? ""
        return !bid.isEmpty
    }

    private func handleFinderDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !isFilled else { return false }
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            DispatchQueue.main.async {
                let ok = url.map { bindAppIfValid(url: $0, slot: slot, shifted: shifted) } ?? false
                if !ok { flashRejection() }
            }
        }
        return true
    }

    /// Briefly paint the keycap red after a Finder drop that isn't a valid
    /// `.app` bundle, so the user sees the file was refused.
    private func flashRejection() {
        withAnimation(.easeIn(duration: 0.08)) { isRejecting = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.35)) { isRejecting = false }
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            bindAppIfValid(url: url, slot: slot, shifted: shifted)
        }
        if let parent = SettingsWindowController.shared.sheetParentWindow {
            panel.beginSheetModal(for: parent, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}

/// Writes a slot binding for `url` if it points to a real `.app` bundle
/// with a bundle identifier. Shared by the NSOpenPanel picker and the
/// Finder drop path so both gates apply the same validation. Returns
/// `true` if the binding was written, `false` if `url` failed validation
/// — callers (notably the drop handler) use this to drive the red
/// rejection flash.
@discardableResult
private func bindAppIfValid(url: URL, slot: Int, shifted: Bool) -> Bool {
    guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
          type.conforms(to: .application) else { return false }
    guard let bundle = Bundle(url: url),
          let bid = bundle.bundleIdentifier else { return false }
    UserDefaults.standard.set(bid, forKey: slotBundleIDKey(slot: slot, shifted: shifted))
    UserDefaults.standard.set(
        FileManager.default.displayName(atPath: url.path),
        forKey: slotAppNameKey(slot: slot, shifted: shifted)
    )
    return true
}

// MARK: - Tiling & focus reference (read-only)

/// Collapsible "Keyboard shortcuts" entry in Settings. Wraps the shared
/// `TilingReferenceCard` (which is reused by the tutorial's done step) and
/// adds the chevron summary row plus a "Replay onboarding tutorial" link.
private struct TilingFocusReference: View {
    let useArrowKeys: Bool
    @State private var isExpanded: Bool = false
    @State private var isHovering: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    TilingReferenceCard(useArrowKeys: useArrowKeys)
                    replayLink
                }
                .transition(.opacity)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
    }

    private var summaryRow: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(TilingReferenceCard.accent)
                Text("Keyboard shortcuts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("— focus, tile, and chord reference")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isExpanded ? "Hide" : "Show")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? AnyShapeStyle(.quinary) : AnyShapeStyle(Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var replayLink: some View {
        HStack {
            Spacer()
            Button {
                OnboardingCoordinator.shared.show()
            } label: {
                Text("Replay onboarding tutorial →")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(TilingReferenceCard.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 4)
    }
}

// MARK: - Version footer

private struct VersionFooter: View {
    var body: some View {
        HStack {
            Spacer()
            Text("v\(BuildInfo.displayString)")
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Button(action: copyVersion) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.quinary))
            }
            .buttonStyle(.plain)
            .help("Copy version")
            Spacer()
        }
        .padding(.top, 12)
    }

    private func copyVersion() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("v\(BuildInfo.displayString)", forType: .string)
    }
}

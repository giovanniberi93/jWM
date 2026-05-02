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
    static let slotAccents: [Color] = [
        Color(red: 0xa2/255, green: 0x62/255, blue: 0x00/255),
        Color(red: 0x1c/255, green: 0x8c/255, blue: 0x4a/255),
        Color(red: 0x0a/255, green: 0x84/255, blue: 0xff/255),
        Color(red: 0xa8/255, green: 0x55/255, blue: 0xf7/255),
    ]
}

// MARK: - Slot order (keyboard row: 1..9 then 0)

private let slotOrder: [Int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]

// MARK: - Storage helpers

private func bundleIDKey(slot: Int, shifted: Bool) -> String {
    "\(shifted ? "shiftApp" : "app")\(slot)_bundleID"
}
private func appNameKey(slot: Int, shifted: Bool) -> String {
    "\(shifted ? "shiftApp" : "app")\(slot)_appName"
}

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("General")
                    .padding(.bottom, 10)

                VStack(spacing: 6) {
                    LaunchAtLoginRow(
                        isOn: launchAtLogin,
                        setLaunchAtLogin: setLaunchAtLogin
                    )
                    EdgeTilingRow(
                        macOSTilingEnabled: macOSTilingEnabled,
                        openSettings: openMacOSTilingSettings
                    )
                }
                .padding(.bottom, 22)

                HStack(alignment: .firstTextBaseline) {
                    sectionHeader("App Bindings")
                    Spacer()
                    Button("Reset") { showResetConfirm = true }
                        .controlSize(.small)
                }
                .padding(.bottom, 10)

                VStack(spacing: 10) {
                    KeyRow(modifiers: ["⌘"], shifted: false)
                    KeyRow(modifiers: ["⌘", "⇧"], shifted: true)
                }
                .padding(.bottom, 22)
            }
            .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
                .padding(.horizontal, -18)
                .padding(.bottom, 16)

            TilingFocusReference()

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
                defaults.removeObject(forKey: bundleIDKey(slot: slot, shifted: shifted))
                defaults.removeObject(forKey: appNameKey(slot: slot, shifted: shifted))
            }
        }
    }

    private static func isMacOSTilingEnabled() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "com.apple.WindowManager", "EnableTilingByEdgeDrag"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.launch()
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return output != "0"
    }
}

// MARK: - General rows

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

private struct EdgeTilingRow: View {
    let macOSTilingEnabled: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MacOS tiling on dragging to left/right edge")
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 6) {
                    if macOSTilingEnabled {
                        StatusChip(text: "FIX", fg: DS.amber, bg: DS.amberBg)
                        Text("Should be disabled — conflicts with jWM's drag-to-edge snapping")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    } else {
                        StatusChip(text: "OK", fg: DS.green, bg: DS.okBg)
                        Text("Already disabled — no conflict with jWM")
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

// MARK: - Key row (binding strip)

private struct KeyRow: View {
    let modifiers: [String]
    let shifted: Bool
    @State private var hoveredSlot: Int? = nil
    @State private var hoveredAppName: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(slotOrder, id: \.self) { slot in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Keycap(
                            slot: slot,
                            shifted: shifted,
                            hovered: hoveredSlot == slot,
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
        .overlay(alignment: .topLeading) { cornerTab }
    }

    private var cornerTab: some View {
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 12, bottomLeading: 0, bottomTrailing: 8, topTrailing: 0)
        )
        return HStack(spacing: 3) {
            ForEach(Array(modifiers.enumerated()), id: \.offset) { idx, m in
                if idx > 0 { plusSign }
                modChip(m, dashed: false)
            }
            plusSign
            modChip("N", dashed: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(shape.fill(.tertiary))
        .overlay(shape.strokeBorder(.separator, lineWidth: 1))
    }

    private var plusSign: some View {
        Text("+")
            .font(DS.mono)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 1)
    }

    private func modChip(_ text: String, dashed: Bool) -> some View {
        Text(text)
            .font(DS.mono)
            .foregroundStyle(dashed ? .secondary : .primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(dashed ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        Color.secondary.opacity(dashed ? 0.5 : 0.25),
                        style: StrokeStyle(lineWidth: 1, dash: dashed ? [2, 2] : [])
                    )
            )
            .frame(minWidth: 14)
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

// MARK: - Keycap

private struct Keycap: View {
    let slot: Int
    let shifted: Bool
    let hovered: Bool
    let onHoverChange: (Bool, String?) -> Void

    @AppStorage var bundleID: String
    @AppStorage var appName: String

    init(slot: Int, shifted: Bool, hovered: Bool, onHoverChange: @escaping (Bool, String?) -> Void) {
        self.slot = slot
        self.shifted = shifted
        self.hovered = hovered
        self.onHoverChange = onHoverChange
        _bundleID = AppStorage(wrappedValue: "", bundleIDKey(slot: slot, shifted: shifted))
        _appName = AppStorage(wrappedValue: "", appNameKey(slot: slot, shifted: shifted))
    }

    private var filled: Bool { !appName.isEmpty }

    var body: some View {
        ZStack {
            // body
            RoundedRectangle(cornerRadius: 8)
                .fill(filled ? AnyShapeStyle(.background) : AnyShapeStyle(Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            Color.secondary.opacity(filled ? 0.35 : 0.25),
                            style: StrokeStyle(lineWidth: 1, dash: filled ? [] : [3, 3])
                        )
                )
                .shadow(color: .black.opacity(filled ? 0.08 : 0), radius: 1, y: 1)

            // icon or empty placeholder
            if filled {
                AppIcon(bundleID: bundleID)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .padding(.top, 8)
                    .overlay(alignment: .topLeading) {
                        if hovered {
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
        .onTapGesture { pickApp() }
    }

    private func clear() {
        bundleID = ""
        appName = ""
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url),
                  let bid = bundle.bundleIdentifier else { return }
            bundleID = bid
            appName = FileManager.default.displayName(atPath: url.path)
        }
    }
}

// MARK: - App icon

private struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let image = Self.icon(for: bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
        }
    }

    private static func icon(for bundleID: String) -> NSImage? {
        guard !bundleID.isEmpty else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Clear badge

private struct ClearBadge: View {
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

// MARK: - Tiling & focus reference (read-only)

private struct NextScreenGlyph: View {
    var size: CGSize = CGSize(width: 26, height: 16)
    var accent: Color = DS.blue
    var active: Bool = true

    var body: some View {
        let w = size.width
        let h = size.height
        let stroke = active ? Color.secondary.opacity(0.5) : Color.secondary
        let fill = active ? accent.opacity(0.6) : Color.clear

        let screenW = (w - 3) / 2 - 1
        let screenH = h - 6

        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .stroke(stroke, lineWidth: 1)
                .frame(width: screenW, height: screenH)
                .position(x: 1 + screenW / 2, y: h / 2)

            RoundedRectangle(cornerRadius: 2)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(stroke, lineWidth: 1)
                )
                .frame(width: screenW, height: screenH)
                .position(x: (w - 3) / 2 + 2 + screenW / 2, y: h / 2)

            Path { p in
                p.move(to: CGPoint(x: w / 2 - 2, y: h / 2))
                p.addLine(to: CGPoint(x: w / 2 + 2, y: h / 2))
                p.move(to: CGPoint(x: w / 2, y: h / 2 - 2))
                p.addLine(to: CGPoint(x: w / 2 + 2, y: h / 2))
                p.addLine(to: CGPoint(x: w / 2, y: h / 2 + 2))
            }
            .stroke(stroke, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
        .frame(width: w, height: h)
    }
}

private enum GlyphKind {
    case focus, launchAll, left, right, max, next
}

private struct ResultGlyph: View {
    let kind: GlyphKind

    var body: some View {
        switch kind {
        case .focus:
            ZStack {
                RoundedRectangle(cornerRadius: 2.5)
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                Circle()
                    .fill(DS.blue)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 36, height: 22)
        case .launchAll:
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DS.slotAccents[i].opacity(0.85))
                        .frame(width: 12, height: 12)
                }
            }
        case .left:
            monitorHalf(filledLeft: true)
        case .right:
            monitorHalf(filledLeft: false)
        case .max:
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1)
                    .fill(DS.blue.opacity(0.6))
                    .padding(2)
            }
            .frame(width: 26, height: 16)
        case .next:
            NextScreenGlyph()
        }
    }

    private func monitorHalf(filledLeft: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
            HStack(spacing: 0) {
                if filledLeft {
                    Rectangle().fill(DS.blue.opacity(0.6))
                    Color.clear
                } else {
                    Color.clear
                    Rectangle().fill(DS.blue.opacity(0.6))
                }
            }
            .padding(2)
        }
        .frame(width: 26, height: 16)
    }
}

private struct TilingFocusReference: View {
    @State private var isExpanded: Bool = false
    @State private var isHovering: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow
            if isExpanded {
                expandedPanel
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
                    .foregroundStyle(Color(red: 10/255, green: 132/255, blue: 255/255))
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
                    .fill(isHovering ? Color.black.opacity(0.03) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 10) {
                tier1
                tier2
                tier3
                tier4
            }
        }
        .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8).fill(DS.blue.opacity(0.025))
                Rectangle().fill(DS.blue.opacity(0.4)).frame(width: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(DS.blue)
            Text("TILING & FOCUS")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(DS.blue)
            StatusChip(
                text: "REFERENCE",
                fg: .secondary,
                bg: Color.secondary.opacity(0.15)
            )
        }
        .padding(.bottom, 10)
    }

    private func tierLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(.secondary)
            .padding(.bottom, 5)
            .padding(.leading, 2)
    }

    private var plus: some View {
        Text("+")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
    }

    private var slash: some View {
        Text("/")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 2)
    }

    private var arrow: some View {
        Text("→")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.tertiary)
    }

    private var tier1: some View {
        VStack(alignment: .leading, spacing: 0) {
            tierLabel("1 · Focus an app")
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Kbd("⌘"); plus; Kbd("N", dashed: true)
                }
                arrow
                ResultGlyph(kind: .focus)
                Text("Bring slot N to the front.")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quinary))
        }
    }

    private var tier2: some View {
        VStack(alignment: .leading, spacing: 0) {
            tierLabel("2 · Launch all apps")
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Kbd("⌃"); plus; Kbd("⌘"); plus; Kbd("A")
                }
                arrow
                ResultGlyph(kind: .launchAll)
                Text("Launch (or focus) every app with a binding.")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quinary))
        }
    }

    private var tier3: some View {
        VStack(alignment: .leading, spacing: 0) {
            tierLabel("3 · Tile the front window")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                ],
                spacing: 6
            ) {
                tileCell(keys: ["⌃", "⌘", "H"], glyph: .left, label: "Left half")
                tileCell(keys: ["⌃", "⌘", "L"], glyph: .right, label: "Right half")
                tileCell(keys: ["⌃", "⌘", "J"], glyph: .max, label: "Maximize")
                tileCell(keys: ["⌃", "⌘", "K"], glyph: .next, label: "Next screen")
            }
        }
    }

    private func tileCell(keys: [String], glyph: GlyphKind, label: String) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { Kbd($0, size: .small) }
            }
            ResultGlyph(kind: glyph)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quinary))
        .frame(maxWidth: .infinity)
    }

    private var tier4: some View {
        VStack(alignment: .leading, spacing: 0) {
            tierLabel("4 · Focus + tile in one chord")
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Kbd("⌘"); plus; Kbd("N", dashed: true); plus
                    Kbd("H"); slash; Kbd("L"); slash; Kbd("J"); slash; Kbd("K")
                }
                arrow
                Text(tier4Caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(DS.blue.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(DS.blue.opacity(0.2), lineWidth: 1))
        }
    }

    private var tier4Caption: AttributedString {
        var attr = AttributedString("Focus slot N and tile it in one motion.")
        if let range = attr.range(of: "N") {
            attr[range].font = .system(size: 12).italic()
            attr[range].foregroundColor = .secondary
        }
        return attr
    }
}

private struct Kbd: View {
    enum Size { case small, medium }
    let text: String
    let dashed: Bool
    let size: Size
    init(_ text: String, dashed: Bool = false, size: Size = .medium) {
        self.text = text
        self.dashed = dashed
        self.size = size
    }
    var body: some View {
        let fs: CGFloat = size == .small ? 10.5 : 11.5
        let hpad: CGFloat = size == .small ? 5 : 7
        let vpad: CGFloat = size == .small ? 1 : 3
        let minW: CGFloat = size == .small ? 14 : 18
        let br: CGFloat = size == .small ? 3 : 4
        Text(text)
            .font(.system(size: fs, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(minWidth: minW)
            .padding(.horizontal, hpad)
            .padding(.vertical, vpad)
            .background(RoundedRectangle(cornerRadius: br).fill(.quaternary))
            .overlay(border(radius: br))
    }

    @ViewBuilder
    private func border(radius: CGFloat) -> some View {
        if dashed {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(
                    Color.secondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
        } else {
            RoundedRectangle(cornerRadius: radius).stroke(.separator, lineWidth: 1)
        }
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
            Spacer()
        }
        .padding(.top, 12)
    }
}

import SwiftUI

/// "Tiling & Focus" reference card. Renders the four shortcut tiers — focus,
/// launch-all, tile, and focus+tile chord — with their key chips and result
/// glyphs. Used in two places:
/// - Settings: keyboard shortcuts expanded panel
/// - Tutorial: the "You're set up" recap on the done step
///
/// Both call sites get the same exact look so the user sees consistent
/// reference material in both surfaces.
struct TilingReferenceCard: View {
    let useArrowKeys: Bool

    static let accent = Color(red: 10/255, green: 132/255, blue: 255/255)
    static let slotAccents: [Color] = [
        Color(red: 0xa2/255, green: 0x62/255, blue: 0x00/255),
        Color(red: 0x1c/255, green: 0x8c/255, blue: 0x4a/255),
        Color(red: 0x0a/255, green: 0x84/255, blue: 0xff/255),
        Color(red: 0xa8/255, green: 0x55/255, blue: 0xf7/255),
    ]

    /// Direction-key glyphs in either Vim or Arrow mode. Source of truth
    /// for the mapping is `HotkeyManager.swift` — keep these in sync with
    /// `keyCodeToPositionLetters` / `keyCodeToPositionArrows`.
    private var dirKeys: (left: String, right: String, full: String, next: String) {
        useArrowKeys ? ("←", "→", "↓", "↑") : ("H", "L", "J", "K")
    }

    var body: some View {
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
                RoundedRectangle(cornerRadius: 8).fill(Self.accent.opacity(0.025))
                Rectangle().fill(Self.accent.opacity(0.4)).frame(width: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Self.accent)
            Text("TILING & FOCUS")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Self.accent)
            Text("REFERENCE")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
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
                tileCell(keys: ["⌃", "⌘", dirKeys.left], glyph: .left, label: "Left half")
                tileCell(keys: ["⌃", "⌘", dirKeys.right], glyph: .right, label: "Right half")
                tileCell(keys: ["⌃", "⌘", dirKeys.full], glyph: .max, label: "Maximize")
                tileCell(keys: ["⌃", "⌘", dirKeys.next], glyph: .next, label: "Next screen")
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
                    Kbd(dirKeys.left); slash; Kbd(dirKeys.right); slash; Kbd(dirKeys.full); slash; Kbd(dirKeys.next)
                }
                arrow
                Text(tier4Caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(Self.accent.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Self.accent.opacity(0.2), lineWidth: 1))
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

// MARK: - Glyphs and key chips (shared with the reference card only)

enum GlyphKind {
    case focus, launchAll, left, right, max, next
}

struct ResultGlyph: View {
    let kind: GlyphKind

    var body: some View {
        switch kind {
        case .focus:
            ZStack {
                RoundedRectangle(cornerRadius: 2.5)
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                Circle()
                    .fill(TilingReferenceCard.accent)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 36, height: 22)
        case .launchAll:
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(TilingReferenceCard.slotAccents[i].opacity(0.85))
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
                    .fill(TilingReferenceCard.accent.opacity(0.6))
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
                    Rectangle().fill(TilingReferenceCard.accent.opacity(0.6))
                    Color.clear
                } else {
                    Color.clear
                    Rectangle().fill(TilingReferenceCard.accent.opacity(0.6))
                }
            }
            .padding(2)
        }
        .frame(width: 26, height: 16)
    }
}

struct NextScreenGlyph: View {
    var size: CGSize = CGSize(width: 26, height: 16)
    var active: Bool = true

    var body: some View {
        let w = size.width
        let h = size.height
        let stroke = active ? Color.secondary.opacity(0.5) : Color.secondary
        let fill = active ? TilingReferenceCard.accent.opacity(0.6) : Color.clear

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

struct Kbd: View {
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

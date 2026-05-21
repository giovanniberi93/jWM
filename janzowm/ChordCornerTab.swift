import SwiftUI

/// Corner tab that hangs off the top-leading edge of a keycap row,
/// rendering "<modifiers> + N" — the N is dashed to indicate "any slot".
/// Used by both Settings (`KeyRow`) and onboarding (`SlotRail`) so the two
/// surfaces render the chord identically.
struct ChordCornerTab: View {
    let modifiers: [String]

    var body: some View {
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
        .fixedSize()
    }

    private var plusSign: some View {
        Text("+")
            .font(Self.chipFont)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 1)
    }

    private func modChip(_ text: String, dashed: Bool) -> some View {
        Text(text)
            .font(Self.chipFont)
            .foregroundStyle(dashed ? .secondary : .primary)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
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

    static let chipFont = Font.system(size: 10.5, weight: .semibold, design: .monospaced)
}

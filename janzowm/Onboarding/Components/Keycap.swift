import SwiftUI

/// TutorialKeycap glyph used in chord rows and the keymode picker. Matches the
/// HTML mock's `.keycap` styling: white pill with a soft drop shadow and an
/// optional sublabel underneath the main glyph.
struct TutorialKeycap: View {
    enum Size { case small, hero }

    let glyph: String
    let sublabel: String?
    let size: Size
    let pulsing: Bool

    init(_ glyph: String, sublabel: String? = nil, size: Size = .hero, pulsing: Bool = false) {
        self.glyph = glyph
        self.sublabel = sublabel
        self.size = size
        self.pulsing = pulsing
    }

    var body: some View {
        Group {
            switch size {
            case .small: smallBody
            case .hero: heroBody
            }
        }
        .modifier(PulseRing(active: pulsing))
    }

    /// Small keycap: fixed 56×52 frame with content split into two equal
    /// halves — glyph in the top, sublabel in the bottom. The glyph row is
    /// reserved at half height regardless of sublabel content, so all caps
    /// in a row align at the same baseline even when one of them carries a
    /// 2-line label like "next\nscreen".
    private var smallBody: some View {
        ZStack {
            keycapBackground
            VStack(spacing: 0) {
                Text(glyph)
                    .font(glyphFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(TutorialTokens.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(sublabel ?? " ")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(TutorialTokens.ink3)
                    .tracking(0.3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.vertical, 4)
        }
        .frame(width: 56, height: 52)
    }

    /// Hero keycap: content-sized via padding, used in chord rows where
    /// caps sit naturally next to `+` separators.
    private var heroBody: some View {
        VStack(spacing: 2) {
            Text(glyph)
                .font(glyphFont)
                .fontWeight(.semibold)
                .foregroundStyle(TutorialTokens.ink)
            if let sublabel {
                Text(sublabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(TutorialTokens.ink3)
                    .tracking(0.3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: 44)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(keycapBackground)
    }

    private var keycapBackground: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(.background)
            .shadow(color: .black.opacity(0.06), radius: 4, y: 4)
            .shadow(color: .black.opacity(0.08), radius: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(TutorialTokens.rule, lineWidth: 0.5)
            )
    }

    private var glyphFont: Font {
        switch size {
        case .hero: return .system(size: 17, weight: .semibold, design: .monospaced)
        case .small: return .system(size: 13, weight: .semibold, design: .monospaced)
        }
    }
}

/// Animated blue ring around a pulsing keycap. Matches the HTML
/// `pulse` keyframes — opacity 0.7→0, scale 0.96→1.08 over 1.6s.
private struct PulseRing: ViewModifier {
    let active: Bool
    @State private var animate = false

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if active {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(TutorialTokens.blue, lineWidth: 2)
                            .padding(-6)
                            .opacity(animate ? 0 : 0.7)
                            .scaleEffect(animate ? 1.08 : 0.96)
                            .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: animate)
                            .onAppear { animate = true }
                            .allowsHitTesting(false)
                    }
                }
            )
    }
}

/// `+` separator between hero keycaps.
struct PlusSeparator: View {
    var body: some View {
        Text("+")
            .font(.system(size: 16, weight: .light))
            .foregroundStyle(TutorialTokens.ink3)
    }
}

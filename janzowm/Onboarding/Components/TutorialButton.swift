import SwiftUI

/// Three button styles used by the tutorial: primary blue, neutral default,
/// and a transparent ghost variant for low-emphasis actions like "Skip".
enum TutorialButton {
    static func primary(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        TutorialButtonView(title: title, kind: .primary, disabled: disabled, action: action)
    }

    static func neutral(_ title: String, action: @escaping () -> Void) -> some View {
        TutorialButtonView(title: title, kind: .neutral, disabled: false, action: action)
    }

    static func ghost(_ title: String, action: @escaping () -> Void) -> some View {
        TutorialButtonView(title: title, kind: .ghost, disabled: false, action: action)
    }
}

private struct TutorialButtonView: View {
    enum Kind { case primary, neutral, ghost }

    let title: String
    let kind: Kind
    let disabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            if !disabled { action() }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.4 : 1)
        .allowsHitTesting(!disabled)
        .onHover { hovering = $0 }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary:
            return AnyShapeStyle(hovering
                ? Color(red: 0/255, green: 0x70/255, blue: 0xe0/255)
                : TutorialTokens.blue)
        case .neutral:
            return hovering ? AnyShapeStyle(.quinary) : AnyShapeStyle(.background)
        case .ghost:
            return hovering ? AnyShapeStyle(.quinary) : AnyShapeStyle(Color.clear)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .neutral: return TutorialTokens.ink
        case .ghost: return hovering ? TutorialTokens.ink : TutorialTokens.ink3
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary: return .clear
        case .neutral: return TutorialTokens.rule
        case .ghost: return .clear
        }
    }
}

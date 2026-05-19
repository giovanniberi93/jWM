import SwiftUI

/// Step 1 — pick Vim vs Arrow keys for tiling. Selection writes through to
/// `useArrowKeys` AppStorage, which `HotkeyManager` reads on every chord
/// dispatch.
struct KeyModeStep: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @AppStorage("useArrowKeys") private var useArrowKeys: Bool = true
    @State private var pickedMode: KeyMode? = nil

    enum KeyMode: String { case vim, arrow }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(eyebrow: "Step 1 of 4 · Keys for tiling",
                       heading: "Vim or arrows?",
                       lede: "jWM uses four directional keys for tiling: left, right, fill screen, and next screen.\nPick the layout you prefer.")

            HStack(spacing: 12) {
                modeCard(
                    .vim,
                    keys: [("H", "left"), ("J", "fill"), ("K", "next\nscreen"), ("L", "right")],
                    title: "Vim mode",
                    sub: "Home-row directions. Stays under your fingers."
                )
                modeCard(
                    .arrow,
                    keys: [("←", "left"), ("↓", "fill"), ("↑", "next\nscreen"), ("→", "right")],
                    title: "Arrow keys",
                    sub: "Direction is literal. Easier to discover."
                )
            }
            .padding(.top, 14)

            Text("You can switch any time in Settings → Keys for tiling windows.")
                .font(.system(size: 11.5))
                .foregroundStyle(TutorialTokens.ink3)
                .padding(.top, 12)

            Spacer(minLength: 16)

            HStack {
                TutorialButton.neutral("Back", action: onBack)
                Spacer()
                TutorialButton.primary("Continue", disabled: pickedMode == nil) {
                    if let m = pickedMode { useArrowKeys = (m == .arrow) }
                    onContinue()
                }
            }
        }
    }

    @ViewBuilder
    private func modeCard(_ mode: KeyMode,
                          keys: [(String, String)],
                          title: String,
                          sub: String) -> some View {
        let selected = pickedMode == mode
        Button {
            pickedMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(keys, id: \.0) { glyph, label in
                        TutorialKeycap(glyph, sublabel: label, size: .small)
                    }
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TutorialTokens.ink)
                Text(sub)
                    .font(.system(size: 12.5))
                    .foregroundStyle(TutorialTokens.ink3)
                    .multilineTextAlignment(.leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected
                          ? AnyShapeStyle(TutorialTokens.blue.opacity(0.04))
                          : AnyShapeStyle(.background))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? TutorialTokens.blue : TutorialTokens.rule,
                                  lineWidth: 1.5)
            )
            .shadow(color: selected ? TutorialTokens.blue.opacity(0.12) : .clear,
                    radius: selected ? 4 : 0)
        }
        .buttonStyle(.plain)
    }
}

/// Eyebrow + heading + lede header used at the top of most steps.
struct StepHeader: View {
    let eyebrow: String?
    let heading: String
    let lede: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(TutorialTokens.ink3)
            }
            Text(heading)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(TutorialTokens.ink)
            if let lede {
                Text(lede)
                    .font(.system(size: 14))
                    .foregroundStyle(TutorialTokens.ink2)
                    .lineLimit(nil)
                    .frame(maxWidth: 540, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

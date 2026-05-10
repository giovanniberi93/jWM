import SwiftUI

/// Steps 4 / 5 / 6 / 8 — "press the chord and we'll advance". Renders the
/// hero keycap row, press hint, and success banner. Listening for the real
/// keypress happens in `TutorialAdvancer` via the AppDelegate observer; this
/// view just shows what to press and the resulting banner.
struct TryChordStep: View {
    let eyebrow: String
    let heading: String
    let lede: AttributedString
    let chord: ChordRow
    let pressHint: String
    let footerExtra: AnyView?

    @ObservedObject var model: TutorialModel
    let onBack: () -> Void
    let onSkip: () -> Void

    init(
        eyebrow: String,
        heading: String,
        lede: AttributedString,
        chord: ChordRow,
        pressHint: String,
        footerExtra: AnyView? = nil,
        model: TutorialModel,
        onBack: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.eyebrow = eyebrow
        self.heading = heading
        self.lede = lede
        self.chord = chord
        self.pressHint = pressHint
        self.footerExtra = footerExtra
        self.model = model
        self.onBack = onBack
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(eyebrow: eyebrow, heading: heading, lede: nil)
            Text(lede)
                .font(.system(size: 14))
                .foregroundStyle(TutorialTokens.ink2)
                .padding(.top, 8)
                .frame(maxWidth: 540, alignment: .leading)

            Spacer(minLength: 12)

            chord
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)

            if let footerExtra { footerExtra }

            Text(pressHint)
                .font(.system(size: 13))
                .foregroundStyle(TutorialTokens.ink2)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            StatusBanner(text: model.statusBannerText)
                .padding(.top, 10)

            Spacer(minLength: 10)

            HStack {
                TutorialButton.neutral("Back", action: onBack)
                Spacer()
                TutorialButton.ghost("Skip this", action: onSkip)
            }
        }
    }
}

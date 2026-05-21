import SwiftUI

/// Root tutorial view: progress dots header, step body, top-right "Skip
/// tutorial" link. Steps drive themselves through `model.step` mutations.
struct TutorialView: View {
    @StateObject private var model: TutorialModel
    let onFinish: () -> Void

    @AppStorage("useArrowKeys") private var useArrowKeys: Bool = true

    init(model: TutorialModel, onFinish: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model)
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TutorialTokens.windowBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                if model.step != .welcome && model.step != .done {
                    ProgressDots(step: model.step)
                        .padding(.bottom, 18)
                }

                stepBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 24)

            if model.step == .welcome {
                skipTutorialLink
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            }
        }
        .frame(width: 720, height: 620)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch model.step {
        case .welcome:
            WelcomeStep(onContinue: { advance(to: .keyMode) })
        case .keyMode:
            KeyModeStep(
                onBack: { advance(to: .welcome) },
                onContinue: { advance(to: .pickSlot1) }
            )
        case .pickSlot1:
            AppPickerStep(
                model: model,
                slot: 1,
                onBack: { advance(to: .keyMode) },
                onContinue: { advance(to: .tryFocus) }
            )
        case .tryFocus:
            tryFocusStep
        case .tryChord:
            tryChordStepView
        case .done:
            DoneStep(onFinish: onFinish)
        }
    }

    private var tryFocusStep: some View {
        var lede = AttributedString("Press ⌘1 anywhere on your Mac. janzoWM will focus the app you just bound.")
        if let r = lede.range(of: "⌘1") { lede[r].font = .system(size: 14, weight: .semibold) }
        return TryChordStep(
            eyebrow: "Step 3 of 4 · Try it",
            heading: "Bring up \(model.slot1Name).",
            lede: lede,
            chord: ChordRow(caps: [
                .init("⌘", sublabel: "command", pulsing: true),
                .init("1", sublabel: model.slot1Name, pulsing: true),
            ]),
            pressHint: "Press ⌘1 anywhere on your Mac.",
            model: model,
            onBack: { advance(to: .pickSlot1) },
            onSkip: { advance(to: .tryChord) }
        )
    }

    private var tryChordStepView: some View {
        let rightKey = useArrowKeys ? "→" : "L"
        var lede = AttributedString("Hold ⌘, then press 1 and \(rightKey); release the keys. That focuses slot 1 and tiles it right — one chord, one move.")
        for term in ["⌘", "1", rightKey] {
            if let r = lede.range(of: term) { lede[r].font = .system(size: 14, weight: .semibold) }
        }
        return TryChordStep(
            eyebrow: "Step 4 of 4 · The chord",
            heading: "Now tile it in one motion.",
            lede: lede,
            chord: ChordRow(caps: [
                .init("⌘", sublabel: "command", pulsing: true),
                .init("1", sublabel: model.slot1Name, pulsing: true),
                .init(rightKey, sublabel: "right", pulsing: true),
            ]),
            pressHint: "Press the chord on your Mac.",
            model: model,
            onBack: { advance(to: .tryFocus) },
            onSkip: { advance(to: .done) }
        )
    }

    private var skipTutorialLink: some View {
        Button {
            advance(to: .done)
        } label: {
            Text("Skip tutorial")
                .font(.system(size: 12))
                .foregroundStyle(TutorialTokens.ink3)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func advance(to step: TutorialStep) {
        withAnimation(.easeInOut(duration: 0.25)) {
            model.step = step
            model.statusBannerText = nil
        }
    }
}

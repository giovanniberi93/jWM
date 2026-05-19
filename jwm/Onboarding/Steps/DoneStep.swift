import SwiftUI

/// Step 9 — success page. Big ✓ badge, recap card with three rows, and a
/// "Start using jWM" primary that closes the window and sets the
/// completion flag (handled by the coordinator).
struct DoneStep: View {
    let onFinish: () -> Void

    @AppStorage("useArrowKeys") private var useArrowKeys: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                checkBadge
                Text("You're set up.")
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.4)
                Text(ledeText)
                    .font(.system(size: 14))
                    .foregroundStyle(TutorialTokens.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 550)
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity)

            TilingReferenceCard(useArrowKeys: useArrowKeys)
                .padding(.top, 18)

            Spacer(minLength: 10)

            HStack {
                Spacer()
                TutorialButton.primary("Start using jWM", action: onFinish)
            }
        }
    }

    private var checkBadge: some View {
        Text("✓")
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(TutorialTokens.blue)
            .frame(width: 64, height: 64)
            .background(Circle().fill(TutorialTokens.blueBg))
    }

    private var ledeText: AttributedString {
        AttributedString("Bind more apps to ⌘2–⌘0 in Settings.\nYou can replay this tutorial any time from Settings → Keyboard shortcuts.")
    }
}

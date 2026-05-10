import SwiftUI

/// Step 0 — welcome screen. Just the app icon, headline, lede, and a
/// "Get started" primary button. Skipping the whole tutorial is still
/// possible via the top-right "Skip tutorial" link rendered by `TutorialView`.
struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 22) {
                appIcon
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: TutorialTokens.blue.opacity(0.25), radius: 12, y: 8)
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)

                VStack(spacing: 8) {
                    Text("Welcome to jWM.")
                        .font(.system(size: 26, weight: .semibold))
                        .tracking(-0.4)
                    Text("Tile windows with one chord.\nTakes about 30 seconds to set up.")
                        .font(.system(size: 14))
                        .foregroundStyle(TutorialTokens.ink2)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer(minLength: 0)

            HStack {
                Spacer()
                TutorialButton.primary("Get started", action: onContinue)
            }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSImage(named: "AppIcon") {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 22).fill(TutorialTokens.blue)
        }
    }
}

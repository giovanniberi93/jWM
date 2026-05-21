import SwiftUI

/// Green "✓ <message>" banner that fades in after a real-key advance.
/// Always occupies its layout slot — when `text` is nil it renders invisibly,
/// so showing/hiding the banner doesn't shift surrounding content.
struct StatusBanner: View {
    let text: String?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(TutorialTokens.green)
                Text("✓")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 18, height: 18)

            Text(text ?? " ")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TutorialTokens.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TutorialTokens.greenBg)
        )
        .opacity(text == nil ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: text)
    }
}

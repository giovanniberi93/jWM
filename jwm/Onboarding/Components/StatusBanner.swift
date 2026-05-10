import SwiftUI

/// Green "✓ <message>" banner that fades in after a real-key advance.
/// Hidden when text is nil.
struct StatusBanner: View {
    let text: String?

    var body: some View {
        if let text {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(TutorialTokens.green)
                    Text("✓")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)

                Text(text)
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
            .transition(.opacity.combined(with: .offset(y: 4)))
        }
    }
}

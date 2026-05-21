import SwiftUI

/// Header progress dots: one per numbered step (welcome and done are framing
/// and excluded). Past steps are filled blue, the current step is a wider
/// blue pill, future steps are muted grey. A "Step N of <total>" label
/// trails the dots.
struct ProgressDots: View {
    let step: TutorialStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...TutorialStep.totalNumbered, id: \.self) { n in
                dot(for: n)
            }
            if let n = step.displayNumber {
                Text("Step \(n) of \(TutorialStep.totalNumbered)")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(TutorialTokens.ink3)
                    .textCase(.uppercase)
                    .padding(.leading, 2)
            }
        }
    }

    @ViewBuilder
    private func dot(for n: Int) -> some View {
        let current = step.displayNumber
        if let current, n < current {
            Capsule().fill(TutorialTokens.blue)
                .frame(width: 7, height: 7)
        } else if let current, n == current {
            Capsule().fill(TutorialTokens.blue)
                .frame(width: 22, height: 7)
        } else {
            Capsule().fill(.tertiary)
                .frame(width: 7, height: 7)
        }
    }
}

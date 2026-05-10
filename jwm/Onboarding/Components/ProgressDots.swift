import SwiftUI

/// Header progress dots: one per step (10 total — welcome…done). Past steps
/// are filled blue, the current step is a wider blue pill, future steps are
/// muted grey. A "Step N of 8" label trails the dots for the numbered
/// steps; welcome and done hide it.
struct ProgressDots: View {
    let step: TutorialStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TutorialStep.allCases, id: \.rawValue) { s in
                dot(for: s)
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
    private func dot(for s: TutorialStep) -> some View {
        if s.rawValue < step.rawValue {
            Capsule().fill(TutorialTokens.blue)
                .frame(width: 7, height: 7)
        } else if s.rawValue == step.rawValue {
            Capsule().fill(TutorialTokens.blue)
                .frame(width: 22, height: 7)
        } else {
            Capsule().fill(.tertiary)
                .frame(width: 7, height: 7)
        }
    }
}

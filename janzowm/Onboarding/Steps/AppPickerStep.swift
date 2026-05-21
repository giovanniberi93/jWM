import SwiftUI

/// Step 2 — pick the app that goes in slot 1. Tapping an app writes the
/// binding through to UserDefaults via `TutorialModel.bind`, so the Settings
/// UI sees the same change. (Slots 2–9, 0 stay empty here; the user binds
/// the rest later in Settings.)
struct AppPickerStep: View {
    @ObservedObject var model: TutorialModel
    let slot: Int  // always 1 in the slim flow; kept parameterized for clarity
    let onBack: () -> Void
    let onContinue: () -> Void

    private var eyebrow: String { "Step 2 of 4 · App binding" }
    private var heading: String { "Pick your most-used app." }
    private var lede: String {
        "It'll go in slot 1. From anywhere on your Mac, ⌘1 will jump to it.\nYou can bind more apps to ⌘2–⌘0 later in Settings."
    }

    // Observe slot 1's binding via AppStorage so the view re-renders when the
    // user clears it through SlotKeycap's × badge (which writes UserDefaults
    // directly and doesn't go through TutorialModel.bind).
    @AppStorage("app1_bundleID") private var currentBundleID: String = ""

    private var dimmed: Set<String> { [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(eyebrow: eyebrow, heading: heading, lede: lede)

            SlotRail(targetSlot: slot, modifiers: ["⌘"])
                .padding(.top, 10)

            Text("CHOOSE FROM YOUR INSTALLED APPS")
                .font(.system(size: 11.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(TutorialTokens.ink3)
                .padding(.top, 18)
                .padding(.bottom, 8)

            AppGrid(
                apps: model.installedApps,
                dimmedBundleIDs: dimmed,
                selectedBundleID: currentBundleID,
                onPick: { app in model.bind(slot: slot, app: app) }
            )

            Spacer(minLength: 14)

            HStack {
                TutorialButton.neutral("Back", action: onBack)
                Spacer()
                TutorialButton.primary("Continue", disabled: currentBundleID.isEmpty, action: onContinue)
            }
        }
    }

}

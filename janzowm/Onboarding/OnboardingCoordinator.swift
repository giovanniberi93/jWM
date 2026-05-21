import AppKit
import SwiftUI

/// Owns the tutorial NSWindow and forwards real keypress actions from
/// HotkeyManager dispatch to the live TutorialModel. `shared` is the only
/// entry point — call `presentIfFirstRun()` once at launch and `show()` for
/// the Settings replay link.
@MainActor
final class OnboardingCoordinator: NSObject, NSWindowDelegate {
    static let shared = OnboardingCoordinator()

    static let hasCompletedKey = "hasCompletedFirstRunTutorial"

    private var window: NSWindow?
    private var model: TutorialModel?

    /// Show the tutorial window if the user hasn't finished it. Skipping or
    /// closing the window without finishing leaves the flag false, so it
    /// reappears next launch.
    func presentIfFirstRun() {
        if UserDefaults.standard.bool(forKey: Self.hasCompletedKey) { return }
        show()
    }

    /// Open the tutorial window from step 0. Idempotent — focuses the
    /// existing window if already open. Does NOT reset the completion flag.
    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let model = TutorialModel()
        self.model = model

        let view = TutorialView(model: model, onFinish: { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.hasCompletedKey)
            self?.closeWindow()
        })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to janzoWM"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: view)
        // Floating level keeps the tutorial above the apps the user is
        // about to focus/tile during the chord rehearsal — without this,
        // ⌘1 would bring the bound app forward and bury the tutorial.
        window.level = .floating
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        model = nil
    }

    private func closeWindow() {
        window?.close()
    }

    /// Called from AppDelegate after each HotkeyManager-dispatched action so
    /// the tutorial can advance on real chords. No-op when the tutorial is
    /// not on screen.
    func observeAction(_ action: TutorialAction) {
        guard let model else { return }
        TutorialAdvancer.handle(action: action, model: model)
    }
}

/// Decides whether an observed action matches the current step, runs the
/// success banner, and advances after a short delay. Pulled out of the
/// coordinator so it stays testable as the step list grows.
@MainActor
enum TutorialAdvancer {
    static func handle(action: TutorialAction, model: TutorialModel) {
        switch (model.step, action) {
        case (.tryFocus, .focus(let key)) where key == "app1":
            advance(model: model, banner: "Focused \(model.slot1Name).", to: .tryChord)
        case (.tryChord, .focusTile(let key, .right)) where key == "app1":
            advance(model: model, banner: "Focused and tiled. That's the move.", to: .done)
        default:
            break
        }
    }

    private static func advance(
        model: TutorialModel,
        banner: String,
        to next: TutorialStep,
        delay: TimeInterval = 0.7
    ) {
        model.statusBannerText = banner
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak model] in
            guard let model else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                model.step = next
                model.statusBannerText = nil
            }
        }
    }
}

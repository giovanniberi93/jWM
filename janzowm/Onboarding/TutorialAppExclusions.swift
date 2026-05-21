import Foundation

/// Bundle IDs excluded from the tutorial's app catalog. Maintained manually,
/// seeded from `scripts/survey-tutorial-apps.swift` output (excluded-apps.txt).
/// Re-run the survey when macOS upgrades or new apps appear in /Applications
/// and copy any new entries here.
///
/// Apps land here because the survey saw their window refuse to resize to
/// half/full visibleFrame, or because they're on the survey's denylist
/// (installers, setup wizards). Daemon/agent apps (LSUIElement /
/// LSBackgroundOnly) are filtered separately in `InstalledAppCatalog.load`
/// from the bundle's Info.plist, so they don't need to be listed here.
enum TutorialAppExclusions {
    static let bundleIDs: Set<String> = [
        "com.apple.AppStore",
        "com.apple.Automator",
        "com.apple.Chess",
        "com.apple.FaceTime",
        "com.apple.GenerativePlaygroundApp",
        "com.apple.Image_Capture",
        "com.apple.Music",
        "com.apple.Passwords",
        "com.apple.PhotoBooth",
        "com.apple.Preview",
        "com.apple.QuickTimePlayerX",
        "com.apple.ScreenContinuity",
        "com.apple.Stickies",
        "com.apple.TV",
        "com.apple.VoiceMemos",
        "com.apple.apps.launcher",
        "com.apple.backup.launcher",
        "com.apple.calculator",
        "com.apple.configurator.ui",
        "com.apple.dt.Xcode",
        "com.apple.exposelauncher",
        "com.apple.freeform",
        "com.apple.games",
        "com.apple.iBooksX",
        "com.apple.podcasts",
        "com.apple.reminders",
        "com.apple.siri.launcher",
        "com.apple.systempreferences",
        "com.apple.weather",
        "com.crowdstrike.falcon.App",
        "com.docker.docker",
        "com.giovanniberi93.janzowm",
        "com.google.drivefs",
        "com.google.drivefs.shortcuts.docs",
        "com.google.drivefs.shortcuts.sheets",
        "com.google.drivefs.shortcuts.slides",
        "com.knollsoft.Rectangle",
        "com.raycast.macos",
        "com.superultra.Homerow",
        "info.marcel-dierkes.KeepingYouAwake",
        "io.github.keycastr",
        "us.zoom.xos",
    ]
}

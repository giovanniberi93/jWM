import SwiftUI
import AppKit

/// Visual tokens for the tutorial. All neutrals come from NSColor's semantic
/// palette so dark/light appearance is handled by the system the same way
/// SettingsView gets it.
enum TutorialTokens {
    /// Window content background — matches the chrome NSWindow paints itself.
    static let windowBg = Color(NSColor.windowBackgroundColor)

    /// Card / inner-panel background. Uses NSColor.controlBackgroundColor so
    /// it sits one level above the window in both modes.
    static let card = Color(NSColor.controlBackgroundColor)

    // Ink hierarchy — semantic, adapts automatically.
    static let ink = Color(NSColor.labelColor)
    static let ink2 = Color(NSColor.secondaryLabelColor)
    static let ink3 = Color(NSColor.tertiaryLabelColor)

    /// Hairline rule — same color as `Color.separator` / NSColor.separatorColor.
    static let rule = Color(NSColor.separatorColor)

    /// macOS system blue. Identical hex in light and dark mode (Apple keeps
    /// the accent visible on both backgrounds), so a fixed RGB is correct.
    static let blue = Color(red: 0x0a/255, green: 0x84/255, blue: 0xff/255)
    static let blueBg = Color(red: 0x0a/255, green: 0x84/255, blue: 0xff/255).opacity(0.15)

    /// System green. Adapts via SwiftUI's color set.
    static let green = Color.green
    static let greenBg = Color.green.opacity(0.15)

    static let mono = Font.system(size: 11, design: .monospaced)
}

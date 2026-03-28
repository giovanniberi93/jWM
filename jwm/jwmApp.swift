//
//  jwmApp.swift
//  jwm
//
//  Created by Giovanni Beri on 2026-03-28.
//

import SwiftUI

@main
struct jwmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("jwm", systemImage: "rectangle.split.2x1") {
            Button("Settings...") {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

/// Manages a standalone settings window for the menu bar app.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "jwm Settings"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkeyManager = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let trusted = AXIsProcessTrusted()
        print("jwm: Accessibility trusted = \(trusted)")
        if !trusted {
            print("jwm: Requesting Accessibility permission...")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        hotkeyManager.start(
            slotHandler: { slotKey in
                let bundleID = UserDefaults.standard.string(forKey: "\(slotKey)_bundleID") ?? ""
                guard !bundleID.isEmpty else {
                    print("jwm: \(slotKey) has no app configured")
                    return
                }
                print("jwm: Focusing \(slotKey) -> \(bundleID)")
                AppFocuser.focusOrLaunch(bundleID: bundleID)
            },
            tileHandler: { position in
                print("jwm: Tiling current window -> \(position)")
                WindowTiler.tile(position)
            },
            slotTileHandler: { slotKey, position in
                let bundleID = UserDefaults.standard.string(forKey: "\(slotKey)_bundleID") ?? ""
                guard !bundleID.isEmpty else {
                    print("jwm: \(slotKey) has no app configured")
                    return
                }
                print("jwm: Tile + focus \(slotKey) -> \(bundleID) -> \(position)")
                // Tile first (while app is still in background), then bring it forward
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                    WindowTiler.tile(position, app: app)
                    app.activate()
                } else {
                    print("jwm: App \(bundleID) not running, launching...")
                    AppFocuser.focusOrLaunch(bundleID: bundleID)
                }
            }
        )
    }
}

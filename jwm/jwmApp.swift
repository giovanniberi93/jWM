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
            slotHandler: { slot in
                let bundleID = UserDefaults.standard.string(forKey: "slot\(slot)_bundleID") ?? ""
                guard !bundleID.isEmpty else {
                    print("jwm: Slot \(slot) has no app configured")
                    return
                }
                print("jwm: Focusing slot \(slot) -> \(bundleID)")
                AppFocuser.focusOrLaunch(bundleID: bundleID)
            },
            tileHandler: { position in
                print("jwm: Tiling current window -> \(position)")
                WindowTiler.tile(position)
            },
            slotTileHandler: { slot, position in
                let bundleID = UserDefaults.standard.string(forKey: "slot\(slot)_bundleID") ?? ""
                guard !bundleID.isEmpty else {
                    print("jwm: Slot \(slot) has no app configured")
                    return
                }
                print("jwm: Focus + tile slot \(slot) -> \(bundleID) -> \(position)")
                AppFocuser.focusOrLaunch(bundleID: bundleID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                        WindowTiler.tile(position, app: app)
                    } else {
                        print("jwm: App \(bundleID) not running after focus attempt")
                    }
                }
            }
        )
    }
}

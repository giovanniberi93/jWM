//
//  AppFocuser.swift
//  jwm
//
//  Created by Giovanni Beri on 2026-03-28.
//

import AppKit

enum AppFocuser {
    /// Focus a running app or launch it if not running.
    static func focusOrLaunch(bundleID: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        } else {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}

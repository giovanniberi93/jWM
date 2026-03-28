//
//  SettingsView.swift
//  jwm
//
//  Created by Giovanni Beri on 2026-03-28.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        Form {
            Section("App Bindings") {
                ForEach(0...9, id: \.self) { slot in
                    SlotRow(slot: slot)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 450)
    }
}

struct SlotRow: View {
    let slot: Int
    @AppStorage var bundleID: String
    @AppStorage var appName: String

    init(slot: Int) {
        self.slot = slot
        _bundleID = AppStorage(wrappedValue: "", "slot\(slot)_bundleID")
        _appName = AppStorage(wrappedValue: "", "slot\(slot)_appName")
    }

    var body: some View {
        HStack {
            Text("⌘+\(slot)")
                .font(.system(.body, design: .monospaced))
                .frame(width: 60, alignment: .leading)
            Text(appName.isEmpty ? "Not set" : appName)
                .foregroundStyle(appName.isEmpty ? .secondary : .primary)
            Spacer()
            if !appName.isEmpty {
                Button("Clear") {
                    bundleID = ""
                    appName = ""
                }
            }
            Button("Choose...") {
                pickApp()
            }
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url),
                  let bid = bundle.bundleIdentifier else { return }
            bundleID = bid
            appName = FileManager.default.displayName(atPath: url.path)
        }
    }
}

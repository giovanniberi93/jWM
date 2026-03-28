//
//  SettingsView.swift
//  jwm
//
//  Created by Giovanni Beri on 2026-03-28.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("slot1_bundleID") private var slot1BundleID: String = ""
    @AppStorage("slot1_appName") private var slot1AppName: String = ""

    var body: some View {
        Form {
            Section("App Bindings") {
                HStack {
                    Text("cmd+1")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 60, alignment: .leading)
                    Text(slot1AppName.isEmpty ? "Not set" : slot1AppName)
                        .foregroundStyle(slot1AppName.isEmpty ? .secondary : .primary)
                    Spacer()
                    if !slot1AppName.isEmpty {
                        Button("Clear") {
                            slot1BundleID = ""
                            slot1AppName = ""
                        }
                    }
                    Button("Choose...") {
                        pickApp { bundleID, name in
                            slot1BundleID = bundleID
                            slot1AppName = name
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 150)
    }

    private func pickApp(completion: @escaping (String, String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else { return }
            let name = FileManager.default.displayName(atPath: url.path)
            completion(bundleID, name)
        }
    }
}

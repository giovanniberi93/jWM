import SwiftUI
import os
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            logger.error("Failed to update launch at login: \(error)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section("App Bindings") {
                ForEach(0...9, id: \.self) { slot in
                    SlotPairRow(slot: slot)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 650)
    }
}

struct SlotPairRow: View {
    let slot: Int

    var body: some View {
        VStack(spacing: 4) {
            SlotRow(slot: slot, shifted: false)
            SlotRow(slot: slot, shifted: true)
        }
    }
}

struct SlotRow: View {
    let slot: Int
    let shifted: Bool
    @AppStorage var bundleID: String
    @AppStorage var appName: String

    init(slot: Int, shifted: Bool) {
        self.slot = slot
        self.shifted = shifted
        let prefix = shifted ? "shiftSlot\(slot)" : "slot\(slot)"
        _bundleID = AppStorage(wrappedValue: "", "\(prefix)_bundleID")
        _appName = AppStorage(wrappedValue: "", "\(prefix)_appName")
    }

    var label: String {
        shifted ? "⌘ + ⇧ + \(slot)" : "⌘ + \(slot)"
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .frame(width: 90, alignment: .leading)
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

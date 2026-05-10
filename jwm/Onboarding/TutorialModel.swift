import AppKit
import Combine
import SwiftUI

enum TutorialStep: Int, CaseIterable {
    case welcome    // 0
    case keyMode    // 1
    case pickSlot1  // 2
    case tryFocus   // 3 — ⌘1 release
    case tryChord   // 4 — ⌘1 + L/→
    case done       // 5

    /// 1-indexed step number shown in the eyebrow ("Step N of 4"). Welcome
    /// and done are excluded from the count.
    var displayNumber: Int? {
        switch self {
        case .welcome, .done: return nil
        case .keyMode: return 1
        case .pickSlot1: return 2
        case .tryFocus: return 3
        case .tryChord: return 4
        }
    }

    static let totalNumbered = 4
}

/// Action observed via the tutorial-side hook into HotkeyManager dispatch.
/// Kept in sync with the `TutorialAdvancer` cases — only the chord variants
/// the slim flow rehearses are observed.
enum TutorialAction: Equatable {
    case focus(slotKey: String)
    case focusTile(slotKey: String, position: TilePosition)
}

/// `TilePosition` has no associated values so Swift auto-synthesizes
/// `==` — declaring conformance is enough to use it in `Equatable` contexts.
extension TilePosition: Equatable {}

/// Mutable state for the tutorial flow. Slot bindings are read straight from
/// UserDefaults (same path Settings uses) so any picks made here are also
/// visible in the Settings UI without an extra sync step.
@MainActor
final class TutorialModel: ObservableObject {
    @Published var step: TutorialStep = .welcome
    @Published var statusBannerText: String? = nil

    /// Cached list of installed apps for the picker grid. Loaded once on
    /// init; the system app set doesn't change during a tutorial session.
    let installedApps: [InstalledApp]

    init() {
        installedApps = InstalledAppCatalog.load()
    }

    var slot1BundleID: String {
        UserDefaults.standard.string(forKey: "app1_bundleID") ?? ""
    }
    var slot1Name: String {
        let n = UserDefaults.standard.string(forKey: "app1_appName") ?? ""
        return n.isEmpty ? "your app" : n
    }

    func bind(slot: Int, app: InstalledApp) {
        let defaults = UserDefaults.standard
        defaults.set(app.bundleID, forKey: "app\(slot)_bundleID")
        defaults.set(app.name, forKey: "app\(slot)_appName")
        objectWillChange.send()
    }

    func clearStatusBanner() {
        statusBannerText = nil
    }
}

struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let url: URL

    var id: String { bundleID }

    func icon() -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum InstalledAppCatalog {
    /// Enumerate `/Applications` (and `/System/Applications`) for `.app`
    /// bundles with a bundle identifier. Sorted by display name.
    static func load() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        let roots = ["/Applications", "/System/Applications"]
        let fm = FileManager.default
        for root in roots {
            guard let contents = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in contents where entry.hasSuffix(".app") {
                let path = "\(root)/\(entry)"
                guard let bundle = Bundle(path: path),
                      let bid = bundle.bundleIdentifier,
                      seen.insert(bid).inserted else { continue }
                let name = fm.displayName(atPath: path)
                apps.append(InstalledApp(bundleID: bid, name: name, url: URL(fileURLWithPath: path)))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

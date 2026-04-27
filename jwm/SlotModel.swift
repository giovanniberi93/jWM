import Cocoa

enum TilePosition: CustomStringConvertible {
    case left
    case right
    case fullScreen
    case nextScreen

    var description: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .fullScreen: return "fullScreen"
        case .nextScreen: return "nextScreen"
        }
    }

    /// Mirror half. Nil for non-half positions.
    var opposite: TilePosition? {
        switch self {
        case .left: return .right
        case .right: return .left
        case .fullScreen, .nextScreen: return nil
        }
    }
}

/// Tracks which apps occupy the full-screen slot on each display.
/// Multiple apps can be fullscreen-sized simultaneously (e.g. one tiled, one
/// just focused) so we keep an ordered list per display rather than a single PID.
struct SlotState {
    private var fullScreen: [CGDirectDisplayID: [pid_t]] = [:]

    /// Primary fullscreen app for a display (last promoted). Returns nil if empty.
    func fullScreen(forDisplay id: CGDirectDisplayID) -> pid_t? {
        fullScreen[id]?.last
    }

    /// All fullscreen PIDs tracked on a display, newest last.
    func allFullScreen(forDisplay id: CGDirectDisplayID) -> [pid_t] {
        fullScreen[id] ?? []
    }

    /// Add a PID to a display's fullscreen list (no-op if already present).
    mutating func addFullScreen(_ pid: pid_t, forDisplay id: CGDirectDisplayID) {
        var list = fullScreen[id] ?? []
        if !list.contains(pid) {
            list.append(pid)
        }
        fullScreen[id] = list
    }

    /// Clear the entire fullscreen list for a display.
    mutating func clearDisplay(_ id: CGDirectDisplayID) {
        fullScreen.removeValue(forKey: id)
    }

    /// Remove a specific PID from all displays.
    mutating func clearFullScreen(pid: pid_t) {
        for id in fullScreen.keys {
            fullScreen[id]?.removeAll { $0 == pid }
            if fullScreen[id]?.isEmpty == true {
                fullScreen.removeValue(forKey: id)
            }
        }
    }

    /// Clear any entries holding PIDs of apps that are no longer running.
    mutating func purgeDeadPids() {
        for id in fullScreen.keys {
            fullScreen[id]?.removeAll { NSRunningApplication(processIdentifier: $0) == nil }
            if fullScreen[id]?.isEmpty == true {
                fullScreen.removeValue(forKey: id)
            }
        }
    }
}

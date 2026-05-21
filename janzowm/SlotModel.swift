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

/// Tracks which *windows* are fullscreen-sized and on which display.
/// One entry per CGWindowID — keying by pid alone hid the multi-window case
/// where two windows of the same app both want independent slot identity
/// (e.g. w1 full while w2 tiles to a half). Recency is captured by a monotonic
/// seq so "next on display X" is a filter+max instead of an order-sensitive
/// list. Entry carries pid for liveness checks and so the bulk
/// `removeAll(forPid:)` path can drop entries when an app dies.
struct SlotState {
    struct Entry: Equatable {
        let pid: pid_t
        let displayID: CGDirectDisplayID
        let seq: UInt64
    }

    private var entries: [CGWindowID: Entry] = [:]
    private var nextSeq: UInt64 = 0

    /// Insert or update the entry for `windowId` with a fresh seq.
    mutating func upsert(windowId: CGWindowID, pid: pid_t, displayID: CGDirectDisplayID) {
        nextSeq += 1
        entries[windowId] = Entry(pid: pid, displayID: displayID, seq: nextSeq)
    }

    /// Remove the entry for `windowId`. No-op if absent.
    mutating func remove(windowId: CGWindowID) {
        entries.removeValue(forKey: windowId)
    }

    /// Drop every entry belonging to `pid`. Cheap path for app-death cleanup.
    mutating func removeAll(forPid pid: pid_t) {
        entries = entries.filter { $0.value.pid != pid }
    }

    /// True if `windowId` has any tracked entry.
    func contains(windowId: CGWindowID) -> Bool {
        entries[windowId] != nil
    }

    /// Most-recently-upserted window on `display`, excluding `excluding`.
    /// Nil if no other entry exists on this display. Returns both the
    /// windowId and the owning pid so callers can drive a per-window
    /// setPosition + run pid-level liveness checks without a second lookup.
    func mostRecentFullScreen(forDisplay display: CGDirectDisplayID, excluding: CGWindowID) -> (windowId: CGWindowID, pid: pid_t)? {
        var best: (windowId: CGWindowID, pid: pid_t)?
        var bestSeq: UInt64 = 0
        for (windowId, entry) in entries where windowId != excluding && entry.displayID == display {
            if entry.seq > bestSeq {
                bestSeq = entry.seq
                best = (windowId, entry.pid)
            }
        }
        return best
    }

    /// Compact one-line snapshot for logs. Sorted by seq desc so most-recent
    /// is first. Empty → "[]". Used at activation/displacement boundaries so
    /// failure-only test logs still reveal what stale entries leaked from
    /// prior tests.
    func dump() -> String {
        if entries.isEmpty { return "[]" }
        let sorted = entries.sorted { $0.value.seq > $1.value.seq }
        let parts = sorted.map { "win=\($0.key)/pid=\($0.value.pid)/disp=\($0.value.displayID)/seq=\($0.value.seq)" }
        return "[" + parts.joined(separator: ", ") + "]"
    }
}

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

/// Tracks which apps are fullscreen-sized and on which display.
/// One entry per pid; recency is captured by a monotonic seq so "next on
/// display X" is a filter+max instead of an order-sensitive list.
struct SlotState {
    struct Entry: Equatable {
        let displayID: CGDirectDisplayID
        let seq: UInt64
    }

    private var entries: [pid_t: Entry] = [:]
    private var nextSeq: UInt64 = 0

    /// Insert or update the entry for `pid` with a fresh seq.
    mutating func upsert(pid: pid_t, displayID: CGDirectDisplayID) {
        nextSeq += 1
        entries[pid] = Entry(displayID: displayID, seq: nextSeq)
    }

    /// Remove the entry for `pid`. No-op if absent.
    mutating func remove(pid: pid_t) {
        entries.removeValue(forKey: pid)
    }

    /// True if `pid` has any tracked entry.
    func contains(pid: pid_t) -> Bool {
        entries[pid] != nil
    }

    /// Most-recently-upserted pid on `display`, excluding `excluding`.
    /// Nil if no other entry exists on this display.
    func mostRecentFullScreen(forDisplay display: CGDirectDisplayID, excluding: pid_t) -> pid_t? {
        var bestPid: pid_t?
        var bestSeq: UInt64 = 0
        for (pid, entry) in entries where pid != excluding && entry.displayID == display {
            if entry.seq > bestSeq {
                bestSeq = entry.seq
                bestPid = pid
            }
        }
        return bestPid
    }

    /// Compact one-line snapshot for logs. Sorted by seq desc so most-recent
    /// is first. Empty → "[]". Used at activation/displacement boundaries so
    /// failure-only test logs still reveal what stale entries leaked from
    /// prior tests.
    func dump() -> String {
        if entries.isEmpty { return "[]" }
        let sorted = entries.sorted { $0.value.seq > $1.value.seq }
        let parts = sorted.map { "pid=\($0.key)/disp=\($0.value.displayID)/seq=\($0.value.seq)" }
        return "[" + parts.joined(separator: ", ") + "]"
    }
}

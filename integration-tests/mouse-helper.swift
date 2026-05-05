#!/usr/bin/env swift
import Cocoa

// CGEvent-based mouse synthesizer for SnapManager drag-to-snap integration
// tests. Posts events at .cghidEventTap so jwm's NSEvent global monitor sees
// them, and AppKit's title-bar drag handling moves the stub window naturally.
//
// Coordinates are CG (top-left origin, primary screen) — the same convention
// the rest of the test harness uses.

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: mouse-helper drag <fromX> <fromY> <toX> <toY> [steps] [stepDelayMs]\n".utf8))
    exit(2)
}

let argv = CommandLine.arguments
guard argv.count >= 2 else { usage() }

func post(_ type: CGEventType, _ p: CGPoint, button: CGMouseButton = .left) {
    guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
    e.post(tap: .cghidEventTap)
}

switch argv[1] {
case "drag":
    guard argv.count >= 6,
          let fx = Double(argv[2]), let fy = Double(argv[3]),
          let tx = Double(argv[4]), let ty = Double(argv[5]) else { usage() }
    let steps = argv.count >= 7 ? max(1, Int(argv[6]) ?? 30) : 30
    let stepDelayMs = argv.count >= 8 ? max(0, Int(argv[7]) ?? 12) : 12
    let from = CGPoint(x: fx, y: fy)
    let to = CGPoint(x: tx, y: ty)

    // Park the cursor on the start point before pressing — otherwise mouseDown
    // fires wherever the user last left the mouse.
    post(.mouseMoved, from)
    usleep(50_000)
    post(.leftMouseDown, from)
    usleep(80_000)

    let stepDelay = useconds_t(stepDelayMs * 1000)
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let p = CGPoint(x: from.x + (to.x - from.x) * t,
                        y: from.y + (to.y - from.y) * t)
        post(.leftMouseDragged, p)
        usleep(stepDelay)
    }

    // Hold a beat so SnapManager's edgeForCursor has a chance to set the
    // overlay before mouseUp commits the tile.
    usleep(120_000)
    post(.leftMouseUp, to)
default:
    usage()
}

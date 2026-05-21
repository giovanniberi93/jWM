#!/usr/bin/env swift
import AppKit

// Real apps (janzowm) initialize NSApplication, which causes AppKit to compute
// `NSScreen.visibleFrame` with the per-screen menu bar inset on secondary
// displays. Without this, a CLI tool sees `visibleFrame == frame` on the
// secondary screen and tests built around it disagree with janzowm's geometry —
// in particular when primary is on a different physical display than the
// one with the menu bar inset janzowm placed against.
_ = NSApplication.shared

enum Position: String { case left, right, full }

func cgRect(_ pos: Position, screen: NSScreen) -> CGRect {
    let f = screen.visibleFrame
    let primaryH = NSScreen.screens[0].frame.height
    let appKit: NSRect
    switch pos {
    case .left:
        appKit = NSRect(x: f.origin.x, y: f.origin.y, width: f.width / 2, height: f.height)
    case .right:
        appKit = NSRect(x: f.origin.x + f.width / 2, y: f.origin.y, width: f.width / 2, height: f.height)
    case .full:
        appKit = f
    }
    return CGRect(
        x: appKit.origin.x,
        y: primaryH - appKit.origin.y - appKit.height,
        width: appKit.width,
        height: appKit.height
    )
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: screen-info-helper.swift <screen-count|expected-rect <left|right|full>>\n".utf8))
    exit(2)
}

switch args[1] {
case "screen-count":
    print(NSScreen.screens.count)
case "expected-rect":
    guard args.count >= 3, let pos = Position(rawValue: args[2]) else {
        FileHandle.standardError.write(Data("expected-rect needs left|right|full\n".utf8))
        exit(2)
    }
    // Pin to screens[0] (primary). NSScreen.main tracks the window with key
    // focus and drifts to whichever display was last active, which makes
    // single-screen test expectations flap on multi-screen hosts. Tests that
    // genuinely need a non-primary screen use `expected-rect-on <idx>`.
    let r = cgRect(pos, screen: NSScreen.screens[0])
    print("\(Int(r.origin.x)) \(Int(r.origin.y)) \(Int(r.width)) \(Int(r.height))")
case "expected-rect-on":
    // Same as expected-rect but pinned to a specific NSScreen index.
    guard args.count >= 4,
          let idx = Int(args[2]),
          let pos = Position(rawValue: args[3]),
          idx >= 0, idx < NSScreen.screens.count else {
        FileHandle.standardError.write(Data("expected-rect-on needs <screen-index> <left|right|full>\n".utf8))
        exit(2)
    }
    let r = cgRect(pos, screen: NSScreen.screens[idx])
    print("\(Int(r.origin.x)) \(Int(r.origin.y)) \(Int(r.width)) \(Int(r.height))")
case "screen-top-cg-y":
    // CG y of the physical top of a screen's frame (above the menu bar,
    // unlike visibleFrame). Used by drag-to-top-edge tests to aim the
    // cursor at the actual top edge regardless of arrangement.
    guard args.count >= 3,
          let idx = Int(args[2]),
          idx >= 0, idx < NSScreen.screens.count else {
        FileHandle.standardError.write(Data("screen-top-cg-y needs <screen-index>\n".utf8))
        exit(2)
    }
    let s = NSScreen.screens[idx]
    let primaryH = NSScreen.screens[0].frame.height
    let topCG = primaryH - (s.frame.origin.y + s.frame.height)
    print(Int(topCG))
case "screen-of":
    // Args: x y w h in CG coords (top-left primary). Prints index of NSScreen
    // whose frame contains the rect's center, or -1 if none.
    guard args.count >= 6,
          let x = Double(args[2]), let y = Double(args[3]),
          let w = Double(args[4]), let h = Double(args[5]) else {
        FileHandle.standardError.write(Data("screen-of needs x y w h\n".utf8))
        exit(2)
    }
    let primaryH = NSScreen.screens[0].frame.height
    let cgCenter = CGPoint(x: x + w / 2, y: y + h / 2)
    let akCenter = CGPoint(x: cgCenter.x, y: primaryH - cgCenter.y)
    var idx = -1
    for (i, s) in NSScreen.screens.enumerated() where s.frame.contains(akCenter) {
        idx = i
        break
    }
    print(idx)
default:
    FileHandle.standardError.write(Data("unknown subcommand: \(args[1])\n".utf8))
    exit(2)
}

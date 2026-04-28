#!/usr/bin/env swift
import AppKit

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
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let r = cgRect(pos, screen: screen)
    print("\(Int(r.origin.x)) \(Int(r.origin.y)) \(Int(r.width)) \(Int(r.height))")
default:
    FileHandle.standardError.write(Data("unknown subcommand: \(args[1])\n".utf8))
    exit(2)
}

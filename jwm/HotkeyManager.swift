//
//  HotkeyManager.swift
//  jwm
//
//  Created by Giovanni Beri on 2026-03-28.
//

import Cocoa
import Carbon.HIToolbox

final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var slotHandler: ((Int) -> Void)?
    private var tileHandler: ((TilePosition) -> Void)?
    private var slotTileHandler: ((Int, TilePosition) -> Void)?

    // Chord state: after cmd+N, wait for a position key
    private var pendingSlot: Int?
    private var chordTimer: DispatchWorkItem?
    private let chordTimeout: TimeInterval = 0.5

    private let keyCodeToPosition: [Int64: TilePosition] = [
        Int64(kVK_ANSI_H): .left,
        Int64(kVK_ANSI_L): .right,
        Int64(kVK_ANSI_J): .fullScreen,
    ]

    private let keyCodeToSlot: [Int64: Int] = [
        Int64(kVK_ANSI_0): 0,
        Int64(kVK_ANSI_1): 1,
        Int64(kVK_ANSI_2): 2,
        Int64(kVK_ANSI_3): 3,
        Int64(kVK_ANSI_4): 4,
        Int64(kVK_ANSI_5): 5,
        Int64(kVK_ANSI_6): 6,
        Int64(kVK_ANSI_7): 7,
        Int64(kVK_ANSI_8): 8,
        Int64(kVK_ANSI_9): 9,
    ]

    /// Start listening for global hotkeys.
    /// - slotHandler: called with slot number (0-9) for cmd+N (focus only).
    /// - tileHandler: called with position for ctrl+cmd+h/l/j (tile current window).
    /// - slotTileHandler: called with (slot, position) for cmd+N then h/l/j chord (focus + tile).
    func start(
        slotHandler: @escaping (Int) -> Void,
        tileHandler: @escaping (TilePosition) -> Void,
        slotTileHandler: @escaping (Int, TilePosition) -> Void
    ) {
        self.slotHandler = slotHandler
        self.tileHandler = tileHandler
        self.slotTileHandler = slotTileHandler

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            print("jwm: Failed to create event tap. Grant Accessibility permission in System Settings.")
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("jwm: Event tap started successfully")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it gets disabled by the system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("jwm: Event tap was disabled, re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)
        let hasAlt = flags.contains(.maskAlternate)

        // If we're waiting for a position key after cmd+N...
        if let slot = pendingSlot {
            if let position = keyCodeToPosition[keyCode], !hasCmd && !hasCtrl && !hasAlt {
                // Bare h/l/j → complete the chord
                print("jwm: Chord complete: slot \(slot) -> \(position)")
                cancelChord()
                slotTileHandler?(slot, position)
                return nil
            }
            // Any other key cancels the chord
            cancelChord()
        }

        // ctrl+cmd+h/l/j → tile current window
        if hasCmd && hasCtrl && !hasAlt {
            if let position = keyCodeToPosition[keyCode] {
                print("jwm: Tile current window -> \(position)")
                tileHandler?(position)
                return nil
            }
        }

        // cmd+N → focus app slot, start chord timer
        if hasCmd && !hasCtrl && !hasAlt {
            if let slot = keyCodeToSlot[keyCode] {
                print("jwm: Slot \(slot) triggered, waiting for position key...")
                slotHandler?(slot)
                startChord(slot: slot)
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func startChord(slot: Int) {
        cancelChord()
        pendingSlot = slot
        let timer = DispatchWorkItem { [weak self] in
            guard let self = self, self.pendingSlot == slot else { return }
            print("jwm: Chord timeout for slot \(slot), focus only")
            self.pendingSlot = nil
        }
        chordTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + chordTimeout, execute: timer)
    }

    private func cancelChord() {
        chordTimer?.cancel()
        chordTimer = nil
        pendingSlot = nil
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}

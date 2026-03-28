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
    private var handler: ((Int) -> Void)?

    /// Start listening for global cmd+N hotkeys.
    /// The handler is called with the slot number (1-9).
    func start(handler: @escaping (Int) -> Void) {
        self.handler = handler

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
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it gets disabled by the system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Only handle cmd+N (cmd held, no other modifiers except shift)
        guard flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              !flags.contains(.maskAlternate) else {
            return Unmanaged.passRetained(event)
        }

        // Map key codes for 0-9
        let keyCodeToSlot: [Int64: Int] = [
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

        guard let slot = keyCodeToSlot[keyCode] else {
            return Unmanaged.passRetained(event)
        }

        handler?(slot)
        return nil // Swallow the event
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

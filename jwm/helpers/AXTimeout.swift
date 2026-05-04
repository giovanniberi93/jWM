import ApplicationServices

// Bounds blocking time when an AX target is slow or unresponsive (e.g. hung
// foreign app, NSOpenPanel XPC service). Default AX timeout is 6s, which
// freezes the main thread; keep it tight since SnapManager/HotkeyManager call
// AX synchronously from the main run loop.
let axMessagingTimeout: Float = 0.1

func makeSystemWideAXElement() -> AXUIElement {
    let element = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
    return element
}

func makeApplicationAXElement(pid: pid_t) -> AXUIElement {
    let element = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
    return element
}
